package com.mock.scp0005.controller;

import com.mock.scp0005.service.PendingRequestManager;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

/**
 * 内部回调接口
 *
 * 供 outer-consumer 调用，通知请求处理完成
 */
@Slf4j
@RestController
@RequestMapping("/internal")
@RequiredArgsConstructor
public class CallbackController {

    private final PendingRequestManager pendingRequestManager;

    /**
     * 接收回调通知
     *
     * @param requestId    请求ID
     * @param responseData 响应数据
     * @return 处理结果
     */
    @PostMapping("/callback/{requestId}")
    public Mono<ResponseEntity<String>> callback(
            @PathVariable String requestId,
            @RequestBody String responseData) {

        log.info("流水号:{}, 收到回调请求", requestId);

        return Mono.fromSupplier(() -> {
            boolean success = pendingRequestManager.completeRequest(requestId, responseData);
            if (success) {
                return ResponseEntity.ok("{\"success\":true}");
            } else {
                // 请求可能已超时，但仍返回 200，避免 outer-consumer 重试
                return ResponseEntity.ok("{\"success\":false,\"reason\":\"request not found or timeout\"}");
            }
        });
    }

    /**
     * 获取当前等待的请求数量（用于监控）
     */
    @GetMapping("/pending-count")
    public Mono<ResponseEntity<String>> getPendingCount() {
        int count = pendingRequestManager.getPendingCount();
        return Mono.just(ResponseEntity.ok("{\"pendingCount\":" + count + "}"));
    }
}
