package com.mock.scp0006;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * 内网穿透网关服务 (scp0006)
 *
 * 职责：
 * 1. 消费 Kafka 中来自内网 MySQL 请求表的 Binlog 消息（Canal 推送）
 * 2. 解析请求数据，调用目标服务
 * 3. 将响应结果写入外网 MySQL 的响应表
 */
@SpringBootApplication
public class Scp0006Application {

    public static void main(String[] args) {
        SpringApplication.run(Scp0006Application.class, args);
    }
}
