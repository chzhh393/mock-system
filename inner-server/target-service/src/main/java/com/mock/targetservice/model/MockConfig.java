package com.mock.targetservice.model;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

import java.util.HashMap;
import java.util.Map;

/**
 * Mock 服务配置
 *
 * 支持配置多个服务端点，每个有不同的延迟时间
 */
@Data
@Configuration
@ConfigurationProperties(prefix = "mock")
public class MockConfig {

    /**
     * 默认处理延迟（毫秒）
     */
    private long delayMs = 50;

    /**
     * 模拟错误率（0-100）
     */
    private int errorRate = 0;

    /**
     * 各服务的延迟配置
     * key: 服务编码 (code)
     * value: 延迟配置
     */
    private Map<String, ServiceDelay> services = new HashMap<>();

    /**
     * 服务延迟配置
     */
    @Data
    public static class ServiceDelay {
        /**
         * 最小延迟（毫秒）
         */
        private long minMs = 50;

        /**
         * 最大延迟（毫秒）
         */
        private long maxMs = 100;

        /**
         * 错误率（0-100），-1 表示使用全局配置
         */
        private int errorRate = -1;
    }
}
