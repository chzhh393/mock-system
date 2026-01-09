package com.mock.targetservice.controller;

import com.mock.targetservice.model.ApiResponse;
import com.mock.targetservice.service.MockBusinessService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/**
 * 业务调用接口
 *
 * 接收 scp0006 的业务请求
 */
@Slf4j
@RestController
@RequestMapping("/api/invoke")
@RequiredArgsConstructor
public class InvokeController {

    private final MockBusinessService mockBusinessService;

    /**
     * 通用业务调用接口
     * POST /api/invoke/{code}
     *
     * @param code      服务编码
     * @param paramData 请求参数 JSON
     * @param requestId 请求ID（从请求头获取）
     * @return 响应结果
     */
    @PostMapping("/{code}")
    public ResponseEntity<ApiResponse<Object>> invoke(
            @PathVariable String code,
            @RequestBody(required = false) String paramData,
            @RequestHeader(value = "X-Request-Id", required = false) String requestId) {

        long startTime = System.currentTimeMillis();

        log.info("流水号:{}, 收到业务请求, code={}", requestId, code);

        try {
            // 处理业务请求
            Object result = mockBusinessService.processRequest(code, paramData, requestId);

            long elapsed = System.currentTimeMillis() - startTime;
            log.info("流水号:{}, 业务处理成功, 耗时={}ms", requestId, elapsed);

            return ResponseEntity.ok(ApiResponse.success(result, requestId, elapsed));

        } catch (Exception e) {
            long elapsed = System.currentTimeMillis() - startTime;
            log.error("流水号:{}, 业务处理失败, 耗时={}ms, error={}", requestId, elapsed, e.getMessage());

            return ResponseEntity.ok(ApiResponse.error("500", e.getMessage(), requestId));
        }
    }

    /**
     * 健康检查接口
     */
    @GetMapping("/health")
    public ResponseEntity<ApiResponse<String>> health() {
        return ResponseEntity.ok(ApiResponse.success("OK"));
    }
}
