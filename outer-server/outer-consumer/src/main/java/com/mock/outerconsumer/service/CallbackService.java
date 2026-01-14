package com.mock.outerconsumer.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/**
 * 回调服务
 *
 * 负责向 scp0005 发送 HTTP 回调通知
 * 使用异步方式发送，不阻塞 Kafka 消费线程
 */
@Slf4j
@Service
public class CallbackService {

    @Value("${callback.url:http://scp0005:8080}")
    private String callbackUrl;

    @Value("${callback.enabled:true}")
    private boolean callbackEnabled;

    @Value("${callback.thread-pool-size:10}")
    private int threadPoolSize;

    private final RestTemplate restTemplate = new RestTemplate();
    private ExecutorService executor;

    @PostConstruct
    public void init() {
        executor = Executors.newFixedThreadPool(threadPoolSize);
        log.info("回调服务初始化, callbackUrl={}, enabled={}, threadPoolSize={}",
                callbackUrl, callbackEnabled, threadPoolSize);
    }

    @PreDestroy
    public void destroy() {
        if (executor != null) {
            executor.shutdown();
            try {
                if (!executor.awaitTermination(5, TimeUnit.SECONDS)) {
                    executor.shutdownNow();
                }
            } catch (InterruptedException e) {
                executor.shutdownNow();
                Thread.currentThread().interrupt();
            }
        }
    }

    /**
     * 异步发送回调通知
     *
     * @param requestId    请求ID
     * @param responseData 响应数据
     */
    public void sendCallback(String requestId, String responseData) {
        if (!callbackEnabled) {
            log.debug("流水号:{}, 回调已禁用，跳过", requestId);
            return;
        }

        // 异步执行回调，不阻塞 Kafka 消费线程
        executor.submit(() -> doSendCallback(requestId, responseData));
    }

    /**
     * 实际发送回调的方法
     */
    private void doSendCallback(String requestId, String responseData) {
        String url = callbackUrl + "/internal/callback/" + requestId;

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);

            HttpEntity<String> request = new HttpEntity<>(responseData, headers);

            long startTime = System.currentTimeMillis();
            String response = restTemplate.postForObject(url, request, String.class);
            long elapsed = System.currentTimeMillis() - startTime;

            log.info("流水号:{}, 回调发送成功, 耗时={}ms, response={}", requestId, elapsed, response);
        } catch (Exception e) {
            log.warn("流水号:{}, 回调发送失败: {}", requestId, e.getMessage());
        }
    }
}
