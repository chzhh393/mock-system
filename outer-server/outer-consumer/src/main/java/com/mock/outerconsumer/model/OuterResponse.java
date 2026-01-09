package com.mock.outerconsumer.model;

import lombok.Data;

/**
 * 外网响应表数据模型 - 对应 outer_gateway.outer_response
 *
 * 字段与数据库表结构对应
 */
@Data
public class OuterResponse {

    /**
     * 自增ID
     */
    private Long id;

    /**
     * 请求唯一ID - 关联 inner_request
     */
    private String requestId;

    /**
     * 响应数据 JSON
     */
    private String responseData;

    /**
     * 响应状态码
     */
    private String code;

    /**
     * 响应消息
     */
    private String message;

    /**
     * 创建时间
     */
    private String createTime;
}
