package com.mock.targetservice.model;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/**
 * Mock 服务配置
 */
@Data
@Configuration
@ConfigurationProperties(prefix = "mock")
public class MockConfig {

    /**
     * 模拟处理延迟（毫秒）
     */
    private long delayMs = 50;

    /**
     * 模拟错误率（0-100）
     */
    private int errorRate = 0;
}
