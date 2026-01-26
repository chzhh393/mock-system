package com.mock.outerconsumer.consumer;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.mock.outerconsumer.model.CanalMessage;
import com.mock.outerconsumer.model.DebeziumMessage;
import com.mock.outerconsumer.service.RedisService;
import com.mock.outerconsumer.service.StatsService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.Acknowledgment;
import org.springframework.stereotype.Component;

import java.util.Map;

/**
 * Binlog 消费者
 *
 * 消费 Canal 推送到 Kafka 的响应表 Binlog 消息
 * 解析后写入 Redis，供 scp0005 轮询获取
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class BinlogConsumer {

    private final RedisService redisService;
    private final StatsService statsService;
    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * 消费响应表 Binlog 消息
     * 支持 Canal 和 Debezium 两种消息格式
     *
     * @param record         Kafka 消息记录
     * @param acknowledgment 手动确认对象
     */
    @KafkaListener(topics = "${consumer.topic}", groupId = "${spring.kafka.consumer.group-id}")
    public void consume(ConsumerRecord<String, String> record, Acknowledgment acknowledgment) {
        long startTime = System.currentTimeMillis();

        try {
            String message = record.value();
            log.debug("收到 Binlog 消息: partition={}, offset={}", record.partition(), record.offset());

            // 记录 Kafka 消费
            statsService.recordKafkaConsumed();

            // 检测消息格式并处理
            if (isDebeziumMessage(message)) {
                processDebeziumMessage(message);
            } else {
                processCanalMessage(message);
            }

            // 确认消息
            acknowledgment.acknowledge();

            long elapsed = System.currentTimeMillis() - startTime;
            log.debug("Binlog 消息处理完成, 耗时={}ms", elapsed);

        } catch (Exception e) {
            log.error("处理 Binlog 消息失败: {}", e.getMessage(), e);
            // 不确认消息，让 Kafka 重新投递
            // 注意：生产环境应该有重试次数限制和死信队列
        }
    }

    /**
     * 检测是否为 Debezium 消息格式
     */
    private boolean isDebeziumMessage(String message) {
        return message.contains("\"payload\"") && message.contains("\"op\"");
    }

    /**
     * 处理 Debezium 消息
     */
    private void processDebeziumMessage(String message) throws Exception {
        DebeziumMessage debeziumMessage = objectMapper.readValue(message, DebeziumMessage.class);

        // 只处理 INSERT 和 UPDATE 操作（op=c 或 op=u）
        if (!debeziumMessage.isInsert() && !debeziumMessage.isUpdate()) {
            log.debug("忽略非 INSERT/UPDATE 操作: op={}",
                debeziumMessage.getPayload() != null ? debeziumMessage.getPayload().getOp() : "null");
            return;
        }

        // 获取变更后的数据
        Map<String, Object> afterData = debeziumMessage.getAfterData();
        if (afterData != null && !afterData.isEmpty()) {
            processResponseRowFromDebezium(afterData);
        }
    }

    /**
     * 处理 Canal 消息
     */
    private void processCanalMessage(String message) throws Exception {
        CanalMessage canalMessage = objectMapper.readValue(message, CanalMessage.class);

        // 只处理 INSERT 和 UPDATE 操作
        String type = canalMessage.getType();
        if (!"INSERT".equals(type) && !"UPDATE".equals(type)) {
            log.debug("忽略非 INSERT/UPDATE 操作: type={}", type);
            return;
        }

        // 跳过 DDL 语句
        if (Boolean.TRUE.equals(canalMessage.getIsDdl())) {
            log.debug("忽略 DDL 语句");
            return;
        }

        // 处理数据变更
        if (canalMessage.getData() != null && !canalMessage.getData().isEmpty()) {
            for (Map<String, String> rowData : canalMessage.getData()) {
                processResponseRow(rowData);
            }
        }
    }

    /**
     * 从 Debezium 数据处理响应行
     */
    private void processResponseRowFromDebezium(Map<String, Object> rowData) {
        String requestId = getStringValue(rowData, "request_id");
        String responseData = getStringValue(rowData, "response_data");
        String code = getStringValue(rowData, "code");
        String message = getStringValue(rowData, "message");

        if (requestId == null || requestId.isEmpty()) {
            log.warn("响应数据缺少 request_id，跳过处理");
            return;
        }

        // 记录 outer-consumer 消费时间 (t6)
        long t6 = System.currentTimeMillis();

        log.info("流水号:{}, 收到响应, code={}", requestId, code);

        // 构建完整的响应 JSON
        String fullResponse = buildResponseJson(responseData, code, message);

        // 写入 Redis
        redisService.writeResult(requestId, fullResponse);

        // 输出完整的耗时分布
        logTraceTimings(requestId, responseData, t6);
    }

    /**
     * 输出完整的耗时分布日志
     */
    private void logTraceTimings(String requestId, String responseData, long t6) {
        try {
            if (responseData == null || responseData.isEmpty()) {
                return;
            }

            JsonNode node = objectMapper.readTree(responseData);

            long t1 = getTraceTimestamp(node, "_trace_t1_scp0005_start");
            long t3 = getTraceTimestamp(node, "_trace_t3_scp0006_consume");
            long t4 = getTraceTimestamp(node, "_trace_t4_target_respond");

            if (t1 > 0 && t3 > 0 && t4 > 0) {
                long cdcDelayInner = t3 - t1;       // CDC延迟(内网)
                long targetServiceTime = t4 - t3;   // 目标服务耗时
                long cdcDelayOuter = t6 - t4;       // CDC延迟(外网)
                long totalTime = t6 - t1;           // 总耗时(不含Redis轮询)

                log.info("流水号:{}, 【耗时分布】CDC延迟(内网)={}ms, 目标服务={}ms, CDC延迟(外网)={}ms, 总计={}ms",
                        requestId, cdcDelayInner, targetServiceTime, cdcDelayOuter, totalTime);
            }
        } catch (Exception e) {
            log.debug("解析追踪时间戳失败: {}", e.getMessage());
        }
    }

    /**
     * 从 JSON 节点获取追踪时间戳
     */
    private long getTraceTimestamp(JsonNode node, String fieldName) {
        JsonNode fieldNode = node.get(fieldName);
        return fieldNode != null ? fieldNode.asLong() : 0;
    }

    /**
     * 从 Map 中安全获取字符串值
     */
    private String getStringValue(Map<String, Object> map, String key) {
        Object value = map.get(key);
        return value != null ? String.valueOf(value) : null;
    }

    /**
     * 处理单行响应数据（Canal 格式）
     *
     * @param rowData 行数据
     */
    private void processResponseRow(Map<String, String> rowData) {
        String requestId = rowData.get("request_id");
        String responseData = rowData.get("response_data");
        String code = rowData.get("code");
        String message = rowData.get("message");

        if (requestId == null || requestId.isEmpty()) {
            log.warn("响应数据缺少 request_id，跳过处理");
            return;
        }

        log.info("流水号:{}, 收到响应, code={}", requestId, code);

        // 构建完整的响应 JSON
        String fullResponse = buildResponseJson(responseData, code, message);

        // 写入 Redis
        redisService.writeResult(requestId, fullResponse);
    }

    /**
     * 构建完整的响应 JSON
     *
     * @param responseData 原始响应数据
     * @param code         响应码
     * @param message      响应消息
     * @return 完整的响应 JSON
     */
    private String buildResponseJson(String responseData, String code, String message) {
        // 如果 responseData 已经是完整的 JSON，直接返回
        if (responseData != null && !responseData.isEmpty()) {
            return responseData;
        }

        // 否则构建一个简单的响应
        return String.format("{\"code\":\"%s\",\"message\":\"%s\"}",
                code != null ? code : "200",
                message != null ? message : "success");
    }
}
