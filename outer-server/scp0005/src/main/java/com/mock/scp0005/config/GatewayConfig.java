package com.mock.scp0005.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/**
 * 网关配置
 */
@Data
@Configuration
@ConfigurationProperties(prefix = "gateway")
public class GatewayConfig {

    /**
     * 轮询 Redis 等待结果的超时时间（毫秒）
     */
    private long pollTimeoutMs = 30000;

    /**
     * 轮询间隔（毫秒）
     */
    private long pollIntervalMs = 100;

    /**
     * Redis 结果 key 前缀
     */
    private String resultKeyPrefix = "gateway:result:";
}
