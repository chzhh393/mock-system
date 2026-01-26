package com.mock.scp0005.controller;

import com.mock.scp0005.service.StatsService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 统计接口
 *
 * 提供统计数据查询和重置功能
 */
@Slf4j
@RestController
@RequestMapping("/api/stats")
@RequiredArgsConstructor
public class StatsController {

    private final StatsService statsService;

    /**
     * 获取统计数据
     */
    @GetMapping
    public ResponseEntity<Map<String, Object>> getStats() {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("code", "200");
        response.put("data", statsService.getStats());
        return ResponseEntity.ok(response);
    }

    /**
     * 重置统计数据
     */
    @PostMapping("/reset")
    public ResponseEntity<Map<String, Object>> resetStats() {
        statsService.resetStats();
        log.info("统计数据已重置");
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("code", "200");
        response.put("data", "Stats reset successfully");
        return ResponseEntity.ok(response);
    }
}
