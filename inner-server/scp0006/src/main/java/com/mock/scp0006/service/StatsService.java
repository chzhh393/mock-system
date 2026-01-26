package com.mock.scp0006.service;

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
    private final AtomicLong targetInvokeSuccess = new AtomicLong(0);
    private final AtomicLong targetInvokeFail = new AtomicLong(0);
    private final AtomicLong mysqlWriteSuccess = new AtomicLong(0);
    private final AtomicLong mysqlWriteFail = new AtomicLong(0);

    // 统计开始时间
    private volatile LocalDateTime startTime = LocalDateTime.now();

    /**
     * 记录 Kafka 消费成功
     */
    public void recordKafkaConsumed() {
        kafkaConsumed.incrementAndGet();
    }

    /**
     * 记录目标服务调用成功
     */
    public void recordTargetInvokeSuccess() {
        targetInvokeSuccess.incrementAndGet();
    }

    /**
     * 记录目标服务调用失败
     */
    public void recordTargetInvokeFail() {
        targetInvokeFail.incrementAndGet();
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
     * 获取统计数据
     */
    public Map<String, Object> getStats() {
        Map<String, Object> stats = new LinkedHashMap<>();

        long total = kafkaConsumed.get();
        stats.put("totalRequests", total);

        Map<String, Long> metrics = new LinkedHashMap<>();
        metrics.put("kafkaConsumed", kafkaConsumed.get());
        metrics.put("targetInvokeSuccess", targetInvokeSuccess.get());
        metrics.put("targetInvokeFail", targetInvokeFail.get());
        metrics.put("mysqlWriteSuccess", mysqlWriteSuccess.get());
        metrics.put("mysqlWriteFail", mysqlWriteFail.get());
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
        targetInvokeSuccess.set(0);
        targetInvokeFail.set(0);
        mysqlWriteSuccess.set(0);
        mysqlWriteFail.set(0);
        startTime = LocalDateTime.now();
        log.info("scp0006 统计数据已重置");
    }
}
