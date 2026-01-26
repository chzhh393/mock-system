package com.mock.scp0005.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 统计服务
 *
 * 提供全链路吞吐量统计功能
 */
@Slf4j
@Service
public class StatsService {

    private static final DateTimeFormatter FORMATTER = DateTimeFormatter.ISO_LOCAL_DATE_TIME;

    // 统计指标
    private final AtomicLong requestReceived = new AtomicLong(0);
    private final AtomicLong mysqlWriteSuccess = new AtomicLong(0);
    private final AtomicLong mysqlWriteFail = new AtomicLong(0);
    private final AtomicLong redisReadSuccess = new AtomicLong(0);
    private final AtomicLong redisReadTimeout = new AtomicLong(0);

    // 统计开始时间
    private volatile LocalDateTime startTime = LocalDateTime.now();

    /**
     * 记录请求接收
     */
    public void recordRequestReceived() {
        requestReceived.incrementAndGet();
    }

    /**
     * 记录 MySQL 写入成功
     */
    public void recordMysqlWriteSuccess() {
        mysqlWriteSuccess.incrementAndGet();
    }

    /**
     * 记录 MySQL 写入失败
     */
    public void recordMysqlWriteFail() {
        mysqlWriteFail.incrementAndGet();
    }

    /**
     * 记录 Redis 读取成功
     */
    public void recordRedisReadSuccess() {
        redisReadSuccess.incrementAndGet();
    }

    /**
     * 记录 Redis 读取超时
     */
    public void recordRedisReadTimeout() {
        redisReadTimeout.incrementAndGet();
    }

    /**
     * 获取统计数据
     */
    public Map<String, Object> getStats() {
        Map<String, Object> stats = new LinkedHashMap<>();

        long total = requestReceived.get();
        stats.put("totalRequests", total);

        Map<String, Long> metrics = new LinkedHashMap<>();
        metrics.put("requestReceived", requestReceived.get());
        metrics.put("mysqlWriteSuccess", mysqlWriteSuccess.get());
        metrics.put("mysqlWriteFail", mysqlWriteFail.get());
        metrics.put("redisReadSuccess", redisReadSuccess.get());
        metrics.put("redisReadTimeout", redisReadTimeout.get());
        stats.put("metrics", metrics);

        stats.put("startTime", startTime.format(FORMATTER));
        stats.put("durationSeconds", ChronoUnit.SECONDS.between(startTime, LocalDateTime.now()));

        return stats;
    }

    /**
     * 重置统计数据
     */
    public void resetStats() {
        requestReceived.set(0);
        mysqlWriteSuccess.set(0);
        mysqlWriteFail.set(0);
        redisReadSuccess.set(0);
        redisReadTimeout.set(0);
        startTime = LocalDateTime.now();
        log.info("scp0005 统计数据已重置");
    }
}
