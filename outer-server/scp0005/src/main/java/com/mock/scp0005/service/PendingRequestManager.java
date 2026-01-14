package com.mock.scp0005.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;

import java.time.Duration;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 待处理请求管理器
 *
 * 使用 Reactor Sinks.One 实现异步等待机制，替代 Redis 轮询
 * 当 outer-consumer 通过 HTTP 回调通知结果时，立即完成等待
 */
@Slf4j
@Component
public class PendingRequestManager {

    private final ConcurrentHashMap<String, Sinks.One<String>> pendingSinks = new ConcurrentHashMap<>();

    /**
     * 等待请求结果
     *
     * @param requestId 请求ID
     * @param timeoutMs 超时时间（毫秒）
     * @return 响应结果的 Mono
     */
    public Mono<String> waitForResult(String requestId, long timeoutMs) {
        Sinks.One<String> sink = Sinks.one();
        pendingSinks.put(requestId, sink);

        log.debug("流水号:{}, 注册等待, 超时={}ms", requestId, timeoutMs);

        return sink.asMono()
                .timeout(Duration.ofMillis(timeoutMs))
                .doOnSuccess(result -> {
                    pendingSinks.remove(requestId);
                    log.debug("流水号:{}, 收到回调结果", requestId);
                })
                .doOnError(e -> {
                    pendingSinks.remove(requestId);
                    log.warn("流水号:{}, 等待超时或出错: {}", requestId, e.getMessage());
                })
                .doOnCancel(() -> {
                    pendingSinks.remove(requestId);
                    log.debug("流水号:{}, 等待被取消", requestId);
                });
    }

    /**
     * 完成请求（被回调接口调用）
     *
     * @param requestId    请求ID
     * @param responseData 响应数据
     * @return 是否成功完成
     */
    public boolean completeRequest(String requestId, String responseData) {
        Sinks.One<String> sink = pendingSinks.remove(requestId);
        if (sink != null) {
            Sinks.EmitResult result = sink.tryEmitValue(responseData);
            if (result.isSuccess()) {
                log.info("流水号:{}, 回调完成请求", requestId);
                return true;
            } else {
                log.warn("流水号:{}, 回调发射失败: {}", requestId, result);
                return false;
            }
        } else {
            log.warn("流水号:{}, 未找到等待的请求（可能已超时）", requestId);
            return false;
        }
    }

    /**
     * 获取当前等待的请求数量
     */
    public int getPendingCount() {
        return pendingSinks.size();
    }
}
