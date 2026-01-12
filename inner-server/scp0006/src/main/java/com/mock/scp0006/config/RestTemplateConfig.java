package com.mock.scp0006.config;

import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;
import org.springframework.http.client.SimpleClientHttpRequestFactory; // Added import

import java.time.Duration;

/**
 * RestTemplate 配置
 */
@Configuration
public class RestTemplateConfig {

    @Bean
    public RestTemplate restTemplate(RestTemplateBuilder builder, GatewayConfig gatewayConfig) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout((int) gatewayConfig.getRequestTimeoutMs());
        factory.setReadTimeout((int) gatewayConfig.getRequestTimeoutMs());
        return builder
                .requestFactory(() -> factory) // Use the configured factory
                .build();
    }
}
