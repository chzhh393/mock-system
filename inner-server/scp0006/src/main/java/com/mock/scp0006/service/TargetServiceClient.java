package com.mock.scp0006.service;

import com.mock.scp0006.config.GatewayConfig;
import com.mock.scp0006.model.InnerRequest;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

/**
 * 目标服务调用客户端
 *
 * 根据请求中的 code 调用对应的目标服务
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class TargetServiceClient {

    private final RestTemplate restTemplate;
    private final GatewayConfig gatewayConfig;

    /**
     * 调用目标服务
     *
     * @param request 请求信息
     * @return 响应结果 JSON
     */
    public String invoke(InnerRequest request) {
        String requestId = request.getRequestId();
        String code = request.getCode();
        String paramData = request.getParamData();

        // 构建目标服务 URL
        String targetUrl = buildTargetUrl(code);

        log.info("流水号:{}, 调用目标服务, url={}", requestId, targetUrl);

        try {
            // 构建请求
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("X-Request-Id", requestId);
            headers.set("X-Service-Code", code);

            HttpEntity<String> entity = new HttpEntity<>(paramData, headers);

            // 发起调用
            long startTime = System.currentTimeMillis();
            ResponseEntity<String> response = restTemplate.exchange(
                    targetUrl,
                    HttpMethod.POST,
                    entity,
                    String.class
            );
            long elapsed = System.currentTimeMillis() - startTime;

            String responseBody = response.getBody();
            log.info("流水号:{}, 目标服务响应成功, status={}, 耗时={}ms",
                    requestId, response.getStatusCode(), elapsed);

            return responseBody != null ? responseBody : buildSuccessResponse();

        } catch (RestClientException e) {
            log.error("流水号:{}, 调用目标服务失败: {}", requestId, e.getMessage());
            return buildErrorResponse(e.getMessage());
        }
    }

    /**
     * 构建目标服务 URL
     *
     * @param code 服务编码
     * @return 完整 URL
     */
    private String buildTargetUrl(String code) {
        String baseUrl = gatewayConfig.getTargetServiceUrl();
        // 根据 code 路由到不同的目标服务接口
        return baseUrl + "/api/invoke/" + code;
    }

    /**
     * 构建成功响应
     */
    private String buildSuccessResponse() {
        return "{\"code\":\"200\",\"message\":\"success\",\"data\":null}";
    }

    /**
     * 构建错误响应
     */
    private String buildErrorResponse(String errorMessage) {
        return String.format("{\"code\":\"500\",\"message\":\"%s\",\"data\":null}",
                errorMessage.replace("\"", "\\\""));
    }
}
