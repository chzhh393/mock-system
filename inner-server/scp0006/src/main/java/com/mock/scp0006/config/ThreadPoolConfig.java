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
     * - 核心线程数：20
     * - 最大线程数：50
     * - 队列：200
     * - 拒绝策略：丢弃并记录日志（快速失败）
     */
    @Bean("businessExecutor")
    public ExecutorService businessExecutor() {
        ThreadPoolExecutor executor = new ThreadPoolExecutor(
                20,                              // 核心线程数
                50,                              // 最大线程数
                60L, TimeUnit.SECONDS,           // 空闲线程存活时间
                new LinkedBlockingQueue<>(200),  // 任务队列
                new ThreadFactory() {
                    private int count = 0;
                    @Override
                    public Thread newThread(Runnable r) {
                        return new Thread(r, "business-" + (++count));
                    }
                },
                (r, executor1) -> {
                    // 队列满时拒绝，快速失败
                    log.warn("线程池已满，拒绝任务（快速失败）");
                }
        );
        log.info("业务线程池初始化完成: core=20, max=50, queue=200");
        return executor;
    }
}
