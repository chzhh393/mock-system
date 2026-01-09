package com.mock.scp0006.consumer;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mock.scp0006.model.CanalMessage;
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

            // 1. 解析 Canal 消息
            CanalMessage canalMessage = objectMapper.readValue(message, CanalMessage.class);

            // 2. 只处理 INSERT 操作（新请求）
            String type = canalMessage.getType();
            if (!"INSERT".equals(type)) {
                log.debug("忽略非 INSERT 操作: type={}", type);
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
                    processRequestRow(rowData);
                }
            }

            // 5. 确认消息
            acknowledgment.acknowledge();

            long elapsed = System.currentTimeMillis() - startTime;
            log.debug("Binlog 消息处理完成, 耗时={}ms", elapsed);

        } catch (Exception e) {
            log.error("处理 Binlog 消息失败: {}", e.getMessage(), e);
            // 不确认消息，让 Kafka 重新投递
        }
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
