package com.mock.scp0006.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;

/**
 * 外网数据库服务
 *
 * 将响应结果写入外网 MySQL 的 outer_response 表
 * 通过强隔离装置穿透连接外网数据库
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class OuterDatabaseService {

    private final JdbcTemplate jdbcTemplate;
    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * 写入响应结果到外网数据库
     *
     * @param requestId    请求ID
     * @param responseData 响应数据 JSON
     */
    public void writeResponse(String requestId, String responseData) {
        // 解析响应数据获取 code 和 message
        String code = extractCode(responseData);
        String message = extractMessage(responseData);

        String sql = """
            INSERT INTO outer_response
            (request_id, response_data, response_code, error_msg, create_time)
            VALUES (?, ?, ?, ?, ?)
            """;

        try {
            int rows = jdbcTemplate.update(sql,
                    requestId,
                    responseData,
                    code,
                    message,
                    LocalDateTime.now()
            );

            if (rows > 0) {
                log.info("流水号:{}, 响应已写入外网数据库, code={}", requestId, code);
            } else {
                log.warn("流水号:{}, 写入外网数据库影响行数为0", requestId);
            }
        } catch (Exception e) {
            log.error("流水号:{}, 写入外网数据库失败: {}", requestId, e.getMessage(), e);
            throw e;
        }
    }

    /**
     * 从响应 JSON 中提取 code
     */
    private String extractCode(String responseData) {
        try {
            JsonNode node = objectMapper.readTree(responseData);
            JsonNode codeNode = node.get("code");
            return codeNode != null ? codeNode.asText() : "200";
        } catch (Exception e) {
            return "200";
        }
    }

    /**
     * 从响应 JSON 中提取 message
     */
    private String extractMessage(String responseData) {
        try {
            JsonNode node = objectMapper.readTree(responseData);
            JsonNode messageNode = node.get("message");
            return messageNode != null ? messageNode.asText() : "success";
        } catch (Exception e) {
            return "success";
        }
    }
}
