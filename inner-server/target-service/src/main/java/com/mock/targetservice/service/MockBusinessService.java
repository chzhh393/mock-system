package com.mock.targetservice.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.mock.targetservice.model.MockConfig;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Map;
import java.util.Random;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Mock 业务服务
 *
 * 模拟各种业务场景的处理逻辑
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MockBusinessService {

    private final MockConfig mockConfig;
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final Random random = new Random();

    // 统计数据
    private final AtomicLong totalRequests = new AtomicLong(0);
    private final AtomicLong successRequests = new AtomicLong(0);
    private final AtomicLong errorRequests = new AtomicLong(0);
    private final Map<String, AtomicLong> codeStats = new ConcurrentHashMap<>();

    /**
     * 处理业务请求
     *
     * @param code      服务编码
     * @param paramData 请求参数 JSON
     * @param requestId 请求ID
     * @return 响应数据
     */
    public Object processRequest(String code, String paramData, String requestId) {
        totalRequests.incrementAndGet();
        codeStats.computeIfAbsent(code, k -> new AtomicLong(0)).incrementAndGet();

        // 1. 模拟处理延迟
        simulateDelay();

        // 2. 模拟随机错误
        if (shouldSimulateError()) {
            errorRequests.incrementAndGet();
            throw new RuntimeException("模拟业务处理错误");
        }

        // 3. 根据 code 路由到不同的处理逻辑
        Object result = routeByCode(code, paramData, requestId);

        successRequests.incrementAndGet();
        return result;
    }

    /**
     * 根据服务编码路由到不同的处理逻辑
     */
    private Object routeByCode(String code, String paramData, String requestId) {
        return switch (code) {
            case "yhzx", "0001" -> handleUserCenter(paramData, requestId);
            case "zdzx", "0002" -> handleBillingCenter(paramData, requestId);
            case "query", "0003" -> handleQuery(paramData, requestId);
            default -> handleGeneric(code, paramData, requestId);
        };
    }

    /**
     * 用户中心业务处理
     */
    private Object handleUserCenter(String paramData, String requestId) {
        ObjectNode response = objectMapper.createObjectNode();
        response.put("userId", "U" + System.currentTimeMillis());
        response.put("userName", "MockUser");
        response.put("status", "active");
        response.put("processTime", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
        return response;
    }

    /**
     * 账单中心业务处理
     */
    private Object handleBillingCenter(String paramData, String requestId) {
        ObjectNode response = objectMapper.createObjectNode();
        response.put("billId", "B" + System.currentTimeMillis());
        response.put("amount", Math.round(random.nextDouble() * 10000) / 100.0);
        response.put("currency", "CNY");
        response.put("status", "paid");
        response.put("processTime", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
        return response;
    }

    /**
     * 查询业务处理
     */
    private Object handleQuery(String paramData, String requestId) {
        ObjectNode response = objectMapper.createObjectNode();

        // 尝试解析请求参数
        try {
            JsonNode params = objectMapper.readTree(paramData);
            response.set("queryParams", params);
        } catch (Exception e) {
            response.put("queryParams", paramData);
        }

        response.put("resultCount", random.nextInt(100));
        response.put("processTime", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
        return response;
    }

    /**
     * 通用业务处理
     */
    private Object handleGeneric(String code, String paramData, String requestId) {
        ObjectNode response = objectMapper.createObjectNode();
        response.put("serviceCode", code);
        response.put("requestId", requestId);
        response.put("processed", true);
        response.put("processTime", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));

        // 回显请求参数
        try {
            JsonNode params = objectMapper.readTree(paramData);
            response.set("echoParams", params);
        } catch (Exception e) {
            response.put("echoParams", paramData);
        }

        return response;
    }

    /**
     * 模拟处理延迟
     */
    private void simulateDelay() {
        long delayMs = mockConfig.getDelayMs();
        if (delayMs > 0) {
            try {
                Thread.sleep(delayMs);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    /**
     * 判断是否模拟错误
     */
    private boolean shouldSimulateError() {
        int errorRate = mockConfig.getErrorRate();
        if (errorRate <= 0) {
            return false;
        }
        return random.nextInt(100) < errorRate;
    }

    /**
     * 获取统计数据
     */
    public Map<String, Object> getStats() {
        return Map.of(
                "totalRequests", totalRequests.get(),
                "successRequests", successRequests.get(),
                "errorRequests", errorRequests.get(),
                "successRate", totalRequests.get() > 0
                        ? String.format("%.2f%%", successRequests.get() * 100.0 / totalRequests.get())
                        : "N/A",
                "codeStats", codeStats
        );
    }

    /**
     * 重置统计数据
     */
    public void resetStats() {
        totalRequests.set(0);
        successRequests.set(0);
        errorRequests.set(0);
        codeStats.clear();
    }
}
