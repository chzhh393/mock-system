package com.mock.scp0006.consumer;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.mock.scp0006.model.CanalMessage;
import com.mock.scp0006.model.DebeziumMessage;
import com.mock.scp0006.model.InnerRequest;
import com.mock.scp0006.service.OuterDatabaseService;
import com.mock.scp0006.service.TargetServiceClient;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.Acknowledgment;
import org.springframework.stereotype.Component;

import java.util.Map;

/**
 * 请求表 Binlog 消费者
 *
 * 消费 Canal 推送到 Kafka 的请求表 Binlog 消息
 * 处理流程：
 * 1. 解析 Canal 消息
 * 2. 调用目标服务
 * 3. 将响应写入外网数据库
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class RequestBinlogConsumer {

    private final TargetServiceClient targetServiceClient;
    private final OuterDatabaseService outerDatabaseService;
    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * 消费请求表 Binlog 消息
     * 支持 Canal 和 Debezium 两种消息格式
     *
     * @param record         Kafka 消息记录
     * @param acknowledgment 手动确认对象
     */
    @KafkaListener(topics = "${gateway.topic}", groupId = "${spring.kafka.consumer.group-id}")
    public void consume(ConsumerRecord<String, String> record, Acknowledgment acknowledgment) {
        long startTime = System.currentTimeMillis();

        try {
            String message = record.value();
            log.debug("收到 Binlog 消息: partition={}, offset={}", record.partition(), record.offset());

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
        }
    }

    /**
     * 检测是否为 Debezium 消息格式
     */
    private boolean isDebeziumMessage(String message) {
        // Debezium 消息包含 "payload" 字段
        return message.contains("\"payload\"") && message.contains("\"op\"");
    }

    /**
     * 处理 Debezium 消息
     */
    private void processDebeziumMessage(String message) throws Exception {
        DebeziumMessage debeziumMessage = objectMapper.readValue(message, DebeziumMessage.class);

        // 只处理 INSERT 操作（op=c）
        if (!debeziumMessage.isInsert()) {
            log.debug("忽略非 INSERT 操作: op={}",
                debeziumMessage.getPayload() != null ? debeziumMessage.getPayload().getOp() : "null");
            return;
        }

        // 获取变更后的数据
        Map<String, Object> afterData = debeziumMessage.getAfterData();
        if (afterData != null && !afterData.isEmpty()) {
            processRequestRowFromDebezium(afterData);
        }
    }

    /**
     * 处理 Canal 消息
     */
    private void processCanalMessage(String message) throws Exception {
        CanalMessage canalMessage = objectMapper.readValue(message, CanalMessage.class);

        // 只处理 INSERT 操作（新请求）
        String type = canalMessage.getType();
        if (!"INSERT".equals(type)) {
            log.debug("忽略非 INSERT 操作: type={}", type);
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
                processRequestRow(rowData);
            }
        }
    }

    /**
     * 从 Debezium 数据处理请求行
     */
    private void processRequestRowFromDebezium(Map<String, Object> rowData) {
        InnerRequest request = buildInnerRequestFromDebezium(rowData);

        String requestId = request.getRequestId();
        if (requestId == null || requestId.isEmpty()) {
            log.warn("请求数据缺少 request_id，跳过处理");
            return;
        }

        // 记录 scp0006 消费时间 (t3)
        long t3 = System.currentTimeMillis();

        // 从 paramData 提取 t1 时间戳，计算 CDC 延迟
        long t1 = extractTraceTimestamp(request.getParamData(), "_trace_t1_scp0005_start");
        if (t1 > 0) {
            log.info("流水号:{}, CDC延迟(内网)={}ms", requestId, t3 - t1);
        }

        log.info("流水号:{}, 开始处理请求, code={}", requestId, request.getCode());

        try {
            // 1. 调用目标服务
            String responseData = targetServiceClient.invoke(request);

            // 记录目标服务响应时间 (t4)
            long t4 = System.currentTimeMillis();
            log.info("流水号:{}, 目标服务耗时={}ms", requestId, t4 - t3);

            // 2. 将响应写入外网数据库，附带追踪时间戳
            String enrichedResponse = addTraceTimestamps(responseData, t1, t3, t4);
            outerDatabaseService.writeResponse(requestId, enrichedResponse);

            long elapsed = System.currentTimeMillis() - t3;
            log.info("流水号:{}, 请求处理完成, 耗时={}ms", requestId, elapsed);

        } catch (Exception e) {
            long elapsed = System.currentTimeMillis() - t3;
            log.error("流水号:{}, 请求处理失败, 耗时={}ms, error={}", requestId, elapsed, e.getMessage());

            // 写入错误响应
            String errorResponse = String.format(
                    "{\"code\":\"500\",\"message\":\"%s\",\"data\":null}",
                    e.getMessage().replace("\"", "\\\"")
            );
            try {
                outerDatabaseService.writeResponse(requestId, errorResponse);
            } catch (Exception writeError) {
                log.error("流水号:{}, 写入错误响应失败: {}", requestId, writeError.getMessage());
            }
        }
    }

    /**
     * 从 paramData 提取追踪时间戳
     */
    private long extractTraceTimestamp(String paramData, String fieldName) {
        try {
            if (paramData == null || paramData.isEmpty()) {
                return 0;
            }
            JsonNode node = objectMapper.readTree(paramData);
            JsonNode fieldNode = node.get(fieldName);
            return fieldNode != null ? fieldNode.asLong() : 0;
        } catch (Exception e) {
            return 0;
        }
    }

    /**
     * 向响应数据添加追踪时间戳
     */
    private String addTraceTimestamps(String responseData, long t1, long t3, long t4) {
        try {
            ObjectNode node = (ObjectNode) objectMapper.readTree(responseData);
            if (t1 > 0) {
                node.put("_trace_t1_scp0005_start", t1);
            }
            node.put("_trace_t3_scp0006_consume", t3);
            node.put("_trace_t4_target_respond", t4);
            return objectMapper.writeValueAsString(node);
        } catch (Exception e) {
            log.warn("添加追踪时间戳失败: {}", e.getMessage());
            return responseData;
        }
    }

    /**
     * 从 Debezium 数据构建 InnerRequest 对象
     */
    private InnerRequest buildInnerRequestFromDebezium(Map<String, Object> rowData) {
        InnerRequest request = new InnerRequest();
        request.setRequestId(getStringValue(rowData, "request_id"));
        request.setCode(getStringValue(rowData, "code"));
        request.setParamData(getStringValue(rowData, "param_data"));
        request.setChannelType(getStringValue(rowData, "channel_type"));
        request.setSerialNo(getStringValue(rowData, "serial_no"));
        request.setSource(getStringValue(rowData, "source"));
        request.setTarget(getStringValue(rowData, "target"));

        Object statusObj = rowData.get("status");
        if (statusObj != null) {
            request.setStatus(((Number) statusObj).intValue());
        }

        Object createTimeObj = rowData.get("create_time");
        if (createTimeObj != null) {
            request.setCreateTime(String.valueOf(createTimeObj));
        }

        return request;
    }

    /**
     * 从 Map 中安全获取字符串值
     */
    private String getStringValue(Map<String, Object> map, String key) {
        Object value = map.get(key);
        return value != null ? String.valueOf(value) : null;
    }

    /**
     * 处理单行请求数据
     *
     * @param rowData 行数据
     */
    private void processRequestRow(Map<String, String> rowData) {
        // 从行数据中构建 InnerRequest
        InnerRequest request = buildInnerRequest(rowData);

        String requestId = request.getRequestId();
        if (requestId == null || requestId.isEmpty()) {
            log.warn("请求数据缺少 request_id，跳过处理");
            return;
        }

        log.info("流水号:{}, 开始处理请求, code={}", requestId, request.getCode());

        long startTime = System.currentTimeMillis();

        try {
            // 1. 调用目标服务
            String responseData = targetServiceClient.invoke(request);

            // 2. 将响应写入外网数据库
            outerDatabaseService.writeResponse(requestId, responseData);

            long elapsed = System.currentTimeMillis() - startTime;
            log.info("流水号:{}, 请求处理完成, 耗时={}ms", requestId, elapsed);

        } catch (Exception e) {
            long elapsed = System.currentTimeMillis() - startTime;
            log.error("流水号:{}, 请求处理失败, 耗时={}ms, error={}", requestId, elapsed, e.getMessage());

            // 写入错误响应
            String errorResponse = String.format(
                    "{\"code\":\"500\",\"message\":\"%s\",\"data\":null}",
                    e.getMessage().replace("\"", "\\\"")
            );
            try {
                outerDatabaseService.writeResponse(requestId, errorResponse);
            } catch (Exception writeError) {
                log.error("流水号:{}, 写入错误响应失败: {}", requestId, writeError.getMessage());
            }
        }
    }

    /**
     * 从行数据构建 InnerRequest 对象
     *
     * @param rowData 行数据
     * @return InnerRequest 对象
     */
    private InnerRequest buildInnerRequest(Map<String, String> rowData) {
        InnerRequest request = new InnerRequest();
        request.setRequestId(rowData.get("request_id"));
        request.setCode(rowData.get("code"));
        request.setParamData(rowData.get("param_data"));
        request.setChannelType(rowData.get("channel_type"));
        request.setSerialNo(rowData.get("serial_no"));
        request.setSource(rowData.get("source"));
        request.setTarget(rowData.get("target"));

        String statusStr = rowData.get("status");
        if (statusStr != null && !statusStr.isEmpty()) {
            request.setStatus(Integer.parseInt(statusStr));
        }

        request.setCreateTime(rowData.get("create_time"));
        return request;
    }
}
