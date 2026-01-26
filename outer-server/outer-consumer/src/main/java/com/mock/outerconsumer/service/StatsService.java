package com.mock.outerconsumer.service;

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
    private final AtomicLong kafkaConsumed = new AtomicLong(0);
    private final AtomicLong redisWriteSuccess = new AtomicLong(0);
    private final AtomicLong redisWriteFail = new AtomicLong(0);

    // 统计开始时间
    private volatile LocalDateTime startTime = LocalDateTime.now();

    /**
     * 记录 Kafka 消费成功
     */
    public void recordKafkaConsumed() {
        kafkaConsumed.incrementAndGet();
    }

    /**
     * 记录 Redis 写入成功
     */
    public void recordRedisWriteSuccess() {
        redisWriteSuccess.incrementAndGet();
    }

    /**
     * 记录 Redis 写入失败
     */
    public void recordRedisWriteFail() {
        redisWriteFail.incrementAndGet();
    }

    /**
     * 获取统计数据
     */
    public Map<String, Object> getStats() {
        Map<String, Object> stats = new LinkedHashMap<>();

        long total = kafkaConsumed.get();
        stats.put("totalRequests", total);

        Map<String, Long> metrics = new LinkedHashMap<>();
        metrics.put("kafkaConsumed", kafkaConsumed.get());
        metrics.put("redisWriteSuccess", redisWriteSuccess.get());
        metrics.put("redisWriteFail", redisWriteFail.get());
        stats.put("metrics", metrics);

        stats.put("startTime", startTime.format(FORMATTER));
        stats.put("durationSeconds", ChronoUnit.SECONDS.between(startTime, LocalDateTime.now()));

        return stats;
    }

    /**
     * 重置统计数据
     */
    public void resetStats() {
        kafkaConsumed.set(0);
        redisWriteSuccess.set(0);
        redisWriteFail.set(0);
        startTime = LocalDateTime.now();
        log.info("outer-consumer 统计数据已重置");
    }
}
