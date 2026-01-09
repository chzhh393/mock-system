package com.mock.scp0006.config;

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
     * Kafka Topic - Canal 推送的请求表 Binlog
     */
    private String topic = "inner_request_binlog";

    /**
     * 目标服务地址
     */
    private String targetServiceUrl = "http://target-service:8083";

    /**
     * 请求超时时间（毫秒）
     */
    private long requestTimeoutMs = 30000;
}
