package com.mock.scp0005;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * SCP0005 - 外网网关服务
 *
 * 功能：
 * 1. 接收外网客户端请求（Form 表单格式）
 * 2. 生成唯一 request_id
 * 3. 将请求写入【内网】数据库的请求表
 * 4. 轮询 Redis 等待结果
 * 5. 返回结果给客户端
 */
@SpringBootApplication
public class Scp0005Application {

    public static void main(String[] args) {
        SpringApplication.run(Scp0005Application.class, args);
    }
}
