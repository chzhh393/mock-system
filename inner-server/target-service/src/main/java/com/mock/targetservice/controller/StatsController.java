package com.mock.targetservice.controller;

import com.mock.targetservice.model.ApiResponse;
import com.mock.targetservice.model.MockConfig;
import com.mock.targetservice.service.MockBusinessService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * 统计和配置接口
 *
 * 用于监控和动态调整 Mock 行为
 */
@Slf4j
@RestController
@RequestMapping("/api/stats")
@RequiredArgsConstructor
public class StatsController {

    private final MockBusinessService mockBusinessService;
    private final MockConfig mockConfig;

    /**
     * 获取统计数据
     */
    @GetMapping
    public ResponseEntity<ApiResponse<Map<String, Object>>> getStats() {
        return ResponseEntity.ok(ApiResponse.success(mockBusinessService.getStats()));
    }

    /**
     * 重置统计数据
     */
    @PostMapping("/reset")
    public ResponseEntity<ApiResponse<String>> resetStats() {
        mockBusinessService.resetStats();
        log.info("统计数据已重置");
        return ResponseEntity.ok(ApiResponse.success("Stats reset successfully"));
    }

    /**
     * 获取当前配置
     */
    @GetMapping("/config")
    public ResponseEntity<ApiResponse<Map<String, Object>>> getConfig() {
        Map<String, Object> config = Map.of(
                "delayMs", mockConfig.getDelayMs(),
                "errorRate", mockConfig.getErrorRate()
        );
        return ResponseEntity.ok(ApiResponse.success(config));
    }

    /**
     * 动态更新配置
     */
    @PostMapping("/config")
    public ResponseEntity<ApiResponse<String>> updateConfig(
            @RequestParam(required = false) Long delayMs,
            @RequestParam(required = false) Integer errorRate) {

        if (delayMs != null) {
            mockConfig.setDelayMs(delayMs);
            log.info("更新延迟配置: delayMs={}", delayMs);
        }

        if (errorRate != null) {
            mockConfig.setErrorRate(errorRate);
            log.info("更新错误率配置: errorRate={}", errorRate);
        }

        return ResponseEntity.ok(ApiResponse.success("Config updated successfully"));
    }
}
