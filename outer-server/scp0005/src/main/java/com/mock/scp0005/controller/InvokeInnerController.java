package com.mock.scp0005.controller;

import com.mock.scp0005.model.RequestDo;
import com.mock.scp0005.service.GatewayService;
import com.mock.scp0005.service.StatsService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

/**
 * 外网穿透内网调用接口
 *
 * 对应原系统的 InovkeInnerC
 * 路径: /inner/c1/{channel}
 *
 * 请求格式: Form 表单 (application/x-www-form-urlencoded)
 * 参数:
 *   - code: 服务编码/穿透码
 *   - paramData: 请求参数 JSON 字符串
 */
@Slf4j
@RestController
@RequestMapping("/inner/c1")
@RequiredArgsConstructor
public class InvokeInnerController {

    private final GatewayService gatewayService;
    private final StatsService statsService;

    /**
     * 用户中心外穿内调用接口
     * POST /inner/c1/yhzx
     */
    @PostMapping(value = "/yhzx", consumes = MediaType.APPLICATION_FORM_URLENCODED_VALUE)
    public Mono<ResponseEntity<String>> callYhzxInnerService(@ModelAttribute RequestDo requestDo) {
        log.info("收到请求: /inner/c1/yhzx, code={}", requestDo.getCode());
        return invokeInner("yhzx", requestDo);
    }

    /**
     * 账单中心外穿内调用接口
     * POST /inner/c1/zdzx
     */
    @PostMapping(value = "/zdzx", consumes = MediaType.APPLICATION_FORM_URLENCODED_VALUE)
    public Mono<ResponseEntity<String>> callZdzxInnerService(@ModelAttribute RequestDo requestDo) {
        log.info("收到请求: /inner/c1/zdzx, code={}", requestDo.getCode());
        return invokeInner("zdzx", requestDo);
    }

    /**
     * 通用外穿内调用接口
     * POST /inner/c1/{channel}
     */
    @PostMapping(value = "/{channel}", consumes = MediaType.APPLICATION_FORM_URLENCODED_VALUE)
    public Mono<ResponseEntity<String>> callInnerService(
            @PathVariable String channel,
            @ModelAttribute RequestDo requestDo) {
        log.info("收到请求: /inner/c1/{}, code={}", channel, requestDo.getCode());
        return invokeInner(channel, requestDo);
    }

    /**
     * 统一处理逻辑
     */
    private Mono<ResponseEntity<String>> invokeInner(String channel, RequestDo requestDo) {
        // 记录请求接收
        statsService.recordRequestReceived();

        return gatewayService.requestInvoke(channel, requestDo.getCode(), requestDo.getParamData())
                .map(ResponseEntity::ok)
                .onErrorResume(e -> {
                    log.error("请求处理失败: {}", e.getMessage());
                    return Mono.just(ResponseEntity
                            .internalServerError()
                            .body("{\"code\":\"500\",\"message\":\"" + e.getMessage() + "\"}"));
                });
    }
}
