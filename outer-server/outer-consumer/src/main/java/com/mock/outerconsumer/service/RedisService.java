package com.mock.outerconsumer.service;

import com.mock.outerconsumer.config.ConsumerConfig;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;

/**
 * Redis 服务
 *
 * 将响应结果写入 Redis，供 scp0005 轮询获取
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class RedisService {

    private final StringRedisTemplate redisTemplate;
    private final ConsumerConfig consumerConfig;

    /**
     * 写入响应结果到 Redis
     *
     * @param requestId    请求ID
     * @param responseData 响应数据 JSON
     */
    public void writeResult(String requestId, String responseData) {
        String key = consumerConfig.getResultKeyPrefix() + requestId;
        long expireSeconds = consumerConfig.getResultExpireSeconds();

        try {
            redisTemplate.opsForValue().set(key, responseData, Duration.ofSeconds(expireSeconds));
            log.info("流水号:{}, 响应结果已写入 Redis, key={}", requestId, key);
        } catch (Exception e) {
            log.error("流水号:{}, 写入 Redis 失败: {}", requestId, e.getMessage(), e);
            throw e;
        }
    }

    /**
     * 检查 Redis 中是否存在结果
     *
     * @param requestId 请求ID
     * @return 是否存在
     */
    public boolean existsResult(String requestId) {
        String key = consumerConfig.getResultKeyPrefix() + requestId;
        return Boolean.TRUE.equals(redisTemplate.hasKey(key));
    }
}
