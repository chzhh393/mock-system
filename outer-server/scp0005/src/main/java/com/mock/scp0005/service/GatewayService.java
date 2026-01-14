package com.mock.scp0005.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.mock.scp0005.config.GatewayConfig;
import com.mock.scp0005.model.InnerRequest;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;
import java.util.UUID;

/**
 * 网关核心服务
 *
 * 核心流程：
 * 1. 生成唯一 request_id
 * 2. 将请求写入【内网】数据库的请求表
 * 3. 等待 HTTP 回调结果（使用 Sinks 异步机制，替代 Redis 轮询）
 * 4. 返回结果
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class GatewayService {

    private final DatabaseClient databaseClient;
    private final GatewayConfig gatewayConfig;
    private final PendingRequestManager pendingRequestManager;
    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * 处理请求 - 核心入口
     *
     * @param channel   通道名称（如 yhzx, zdzx）
     * @param code      服务编码
     * @param paramData 请求参数 JSON
     * @return 响应结果
     */
    public Mono<String> requestInvoke(String channel, String code, String paramData) {
        // 1. 生成唯一请求ID
        String requestId = generateRequestId();

        long startTime = System.currentTimeMillis();
        log.info("流水号:{}, 开始处理请求, channel={}, code={}", requestId, channel, code);

        // 2. 解析 paramData 获取额外信息，并添加追踪时间戳
        String enrichedParamData = addTraceTimestamp(paramData, startTime);

        String channelType = extractField(enrichedParamData, "channelType");
        String serialNo = extractField(enrichedParamData, "serialNo");
        String source = extractField(enrichedParamData, "source");
        String target = extractField(enrichedParamData, "target");

        // 如果 serialNo 为空，使用 requestId
        if (serialNo == null || serialNo.isEmpty()) {
            serialNo = requestId;
        }

        final String finalSerialNo = serialNo;

        // 3. 写入内网数据库请求表
        return insertInnerRequest(requestId, code, enrichedParamData, channelType, finalSerialNo, source, target)
                .doOnSuccess(v -> log.info("流水号:{}, 请求已写入内网数据库", requestId))
                .doOnError(e -> log.error("流水号:{}, 写入内网数据库失败: {}", requestId, e.getMessage()))
                // 4. 等待回调结果（使用 Sinks 替代 Redis 轮询）
                .then(pendingRequestManager.waitForResult(requestId, gatewayConfig.getPollTimeoutMs()))
                .doOnSuccess(result -> {
                    long elapsed = System.currentTimeMillis() - startTime;
                    log.info("流水号:{}, 请求处理完成, 耗时={}ms", requestId, elapsed);
                })
                .doOnError(e -> {
                    long elapsed = System.currentTimeMillis() - startTime;
                    log.error("流水号:{}, 请求处理失败, 耗时={}ms, error={}", requestId, elapsed, e.getMessage());
                });
    }

    /**
     * 生成唯一请求ID
     */
    private String generateRequestId() {
        return UUID.randomUUID().toString().replace("-", "");
    }

    /**
     * 从 paramData JSON 中提取字段
     */
    private String extractField(String paramData, String fieldName) {
        try {
            JsonNode node = objectMapper.readTree(paramData);
            JsonNode fieldNode = node.get(fieldName);
            return fieldNode != null ? fieldNode.asText() : null;
        } catch (Exception e) {
            log.warn("解析 paramData 失败: {}", e.getMessage());
            return null;
        }
    }

    /**
     * 向 paramData 添加追踪时间戳
     */
    private String addTraceTimestamp(String paramData, long timestamp) {
        try {
            ObjectNode node = (ObjectNode) objectMapper.readTree(paramData);
            node.put("_trace_t1_scp0005_start", timestamp);
            return objectMapper.writeValueAsString(node);
        } catch (Exception e) {
            log.warn("添加追踪时间戳失败: {}", e.getMessage());
            return paramData;
        }
    }

    /**
     * 写入内网数据库请求表
     */
    private Mono<Void> insertInnerRequest(String requestId, String code, String paramData,
                                          String channelType, String serialNo,
                                          String source, String target) {
        String sql = """
            INSERT INTO inner_request
            (request_id, code, param_data, channel_type, serial_no, source, target, status, create_time)
            VALUES
            (:requestId, :code, :paramData, :channelType, :serialNo, :source, :target, 0, :createTime)
            """;

        return databaseClient.sql(sql)
                .bind("requestId", requestId)
                .bind("code", code)
                .bind("paramData", paramData)
                .bind("channelType", channelType != null ? channelType : "")
                .bind("serialNo", serialNo != null ? serialNo : requestId)
                .bind("source", source != null ? source : "")
                .bind("target", target != null ? target : "")
                .bind("createTime", LocalDateTime.now())
                .fetch()
                .rowsUpdated()
                .then();
    }

}
