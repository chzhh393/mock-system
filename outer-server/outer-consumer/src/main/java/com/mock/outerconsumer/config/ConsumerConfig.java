package com.mock.outerconsumer.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/**
 * 消费者配置
 */
@Data
@Configuration
@ConfigurationProperties(prefix = "consumer")
public class ConsumerConfig {

    /**
     * Kafka Topic - Canal 推送的响应表 Binlog
     */
    private String topic = "outer_response_binlog";

    /**
     * Redis key 前缀 - 与 scp0005 保持一致
     */
    private String resultKeyPrefix = "gateway:result:";

    /**
     * Redis key 过期时间（秒）
     */
    private long resultExpireSeconds = 300;
}
