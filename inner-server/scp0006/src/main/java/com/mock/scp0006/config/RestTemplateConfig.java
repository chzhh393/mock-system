package com.mock.scp0006.config;

import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

import java.time.Duration;

/**
 * RestTemplate 配置
 */
@Configuration
public class RestTemplateConfig {

    @Bean
    public RestTemplate restTemplate(RestTemplateBuilder builder, GatewayConfig gatewayConfig) {
        return builder
                .connectTimeout(Duration.ofMillis(gatewayConfig.getRequestTimeoutMs()))
                .readTimeout(Duration.ofMillis(gatewayConfig.getRequestTimeoutMs()))
                .build();
    }
}
