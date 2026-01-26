package com.mock.scp0006.controller;

import com.mock.scp0006.model.InnerRequest;
import com.mock.scp0006.service.StatsService;
import com.mock.scp0006.service.TargetServiceClient;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 压测 Controller
 *
 * 绕过 Canal/Kafka，直接测试 scp0006 发送 HTTP 请求的能力
 */
@Slf4j
@RestController
@RequestMapping("/api/stress")
public class StressTestController {

    private final TargetServiceClient targetServiceClient;
    private final StatsService statsService;

    // 压测专用线程池（独立于业务线程池）
    private ExecutorService stressExecutor;

    public StressTestController(TargetServiceClient targetServiceClient, StatsService statsService) {
        this.targetServiceClient = targetServiceClient;
        this.statsService = statsService;
    }

    private synchronized ExecutorService getStressExecutor(int concurrency) {
        if (stressExecutor != null) {
            stressExecutor.shutdownNow();
        }
        stressExecutor = Executors.newFixedThreadPool(concurrency, r -> {
            Thread t = new Thread(r, "stress-" + System.nanoTime());
            t.setDaemon(true);
            return t;
        });
        return stressExecutor;
    }

    /**
     * 启动压测
     *
     * @param concurrency 并发数（默认 100）
     * @param duration 持续时间秒（默认 30）
     * @return 测试结果
     */
    @PostMapping("/start")
    public Map<String, Object> startStressTest(
            @RequestParam(defaultValue = "100") int concurrency,
            @RequestParam(defaultValue = "30") int duration) {

        log.info("启动压测: concurrency={}, duration={}s", concurrency, duration);

        // 重置统计
        statsService.resetStats();

        AtomicLong totalRequests = new AtomicLong(0);
        AtomicLong successCount = new AtomicLong(0);
        AtomicLong failCount = new AtomicLong(0);

        long startTime = System.currentTimeMillis();
        long endTime = startTime + duration * 1000L;

        // 使用 CountDownLatch 等待所有任务完成
        CountDownLatch latch = new CountDownLatch(concurrency);

        // 获取压测专用线程池
        ExecutorService executor = getStressExecutor(concurrency);

        // 启动并发任务
        for (int i = 0; i < concurrency; i++) {
            final int workerId = i;
            executor.submit(() -> {
                try {
                    while (System.currentTimeMillis() < endTime) {
                        try {
                            // 构造模拟请求
                            InnerRequest request = new InnerRequest();
                            request.setRequestId("stress-" + UUID.randomUUID().toString().substring(0, 8));
                            request.setCode("TEST001");
                            request.setParamData("{\"test\":\"data\",\"worker\":" + workerId + "}");

                            // 调用目标服务
                            targetServiceClient.invoke(request);

                            totalRequests.incrementAndGet();
                            successCount.incrementAndGet();
                        } catch (Exception e) {
                            totalRequests.incrementAndGet();
                            failCount.incrementAndGet();
                        }
                    }
                } finally {
                    latch.countDown();
                }
            });
        }

        // 等待所有任务完成
        try {
            latch.await(duration + 10, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        long actualDuration = System.currentTimeMillis() - startTime;
        double tps = totalRequests.get() * 1000.0 / actualDuration;
        double errorRate = totalRequests.get() > 0 ?
                failCount.get() * 100.0 / totalRequests.get() : 0;

        Map<String, Object> result = new HashMap<>();
        result.put("concurrency", concurrency);
        result.put("durationMs", actualDuration);
        result.put("totalRequests", totalRequests.get());
        result.put("successCount", successCount.get());
        result.put("failCount", failCount.get());
        result.put("tps", String.format("%.2f", tps));
        result.put("errorRate", String.format("%.2f%%", errorRate));

        log.info("压测完成: {}", result);

        return result;
    }

    /**
     * 快速测试（10秒）
     */
    @PostMapping("/quick")
    public Map<String, Object> quickTest(@RequestParam(defaultValue = "100") int concurrency) {
        return startStressTest(concurrency, 10);
    }
}
