package com.mock.outerconsumer;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * 外网消费者服务
 *
 * 职责：
 * 1. 消费 Kafka 中来自外网 MySQL 响应表的 Binlog 消息（Canal 推送）
 * 2. 解析响应数据
 * 3. 将响应结果写入 Redis，供 scp0005 轮询获取
 */
@SpringBootApplication
public class OuterConsumerApplication {

    public static void main(String[] args) {
        SpringApplication.run(OuterConsumerApplication.class, args);
    }
}
