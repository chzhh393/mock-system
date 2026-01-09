package com.mock.outerconsumer.consumer;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mock.outerconsumer.model.CanalMessage;
import com.mock.outerconsumer.service.RedisService;
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
    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * 消费响应表 Binlog 消息
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

            // 1. 解析 Canal 消息
            CanalMessage canalMessage = objectMapper.readValue(message, CanalMessage.class);

            // 2. 只处理 INSERT 和 UPDATE 操作
            String type = canalMessage.getType();
            if (!"INSERT".equals(type) && !"UPDATE".equals(type)) {
                log.debug("忽略非 INSERT/UPDATE 操作: type={}", type);
                acknowledgment.acknowledge();
                return;
            }

            // 3. 跳过 DDL 语句
            if (Boolean.TRUE.equals(canalMessage.getIsDdl())) {
                log.debug("忽略 DDL 语句");
                acknowledgment.acknowledge();
                return;
            }

            // 4. 处理数据变更
            if (canalMessage.getData() != null && !canalMessage.getData().isEmpty()) {
                for (Map<String, String> rowData : canalMessage.getData()) {
                    processResponseRow(rowData);
                }
            }

            // 5. 确认消息
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
     * 处理单行响应数据
     *
     * @param rowData 行数据
     */
    private void processResponseRow(Map<String, String> rowData) {
        // 从行数据中提取字段
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
