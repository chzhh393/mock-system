package com.mock.scp0006.model;

import lombok.Data;

/**
 * 内网请求表数据模型 - 对应 inner_gateway.inner_request
 */
@Data
public class InnerRequest {

    /**
     * 自增ID
     */
    private Long id;

    /**
     * 请求唯一ID
     */
    private String requestId;

    /**
     * 服务编码/穿透码
     */
    private String code;

    /**
     * 请求参数 JSON
     */
    private String paramData;

    /**
     * 通道类型
     */
    private String channelType;

    /**
     * 流水号
     */
    private String serialNo;

    /**
     * 来源
     */
    private String source;

    /**
     * 目标（省码）
     */
    private String target;

    /**
     * 状态：0-待处理 1-处理中 2-已完成 3-失败
     */
    private Integer status;

    /**
     * 创建时间
     */
    private String createTime;
}
