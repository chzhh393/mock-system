package com.mock.targetservice;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * 目标服务 Mock
 *
 * 模拟内网业务服务，接收 scp0006 的请求并返回响应
 * 支持配置模拟延迟和错误率，用于性能测试
 */
@SpringBootApplication
public class TargetServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(TargetServiceApplication.class, args);
    }
}
