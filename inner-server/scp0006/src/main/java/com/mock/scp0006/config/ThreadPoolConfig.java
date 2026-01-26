package com.mock.scp0006.config;

import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.concurrent.*;

/**
 * 线程池配置
 *
 * 共用线程池，配合超时控制实现快速失败
 */
@Slf4j
@Configuration
public class ThreadPoolConfig {

    /**
     * 共用业务线程池
     * - 核心线程数：100
     * - 最大线程数：200
     * - 队列：5000
     * - 拒绝策略：CallerRunsPolicy（调用者线程执行，实现背压）
     */
    @Bean("businessExecutor")
    public ExecutorService businessExecutor() {
        ThreadPoolExecutor executor = new ThreadPoolExecutor(
                100,                             // 核心线程数（增加到100）
                200,                             // 最大线程数（增加到200）
                60L, TimeUnit.SECONDS,           // 空闲线程存活时间
                new LinkedBlockingQueue<>(5000), // 任务队列（增加到5000）
                new ThreadFactory() {
                    private int count = 0;
                    @Override
                    public Thread newThread(Runnable r) {
                        return new Thread(r, "business-" + (++count));
                    }
                },
                new ThreadPoolExecutor.CallerRunsPolicy() // 队列满时由调用者线程执行（实现背压，不丢弃任务）
        );
        log.info("业务线程池初始化完成: core=100, max=200, queue=5000, policy=CallerRunsPolicy");
        return executor;
    }
}
