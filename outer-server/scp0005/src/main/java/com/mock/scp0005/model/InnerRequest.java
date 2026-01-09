package com.mock.scp0005.model;

import lombok.Data;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.LocalDateTime;

/**
 * 内网请求表实体 - 对应 inner_gateway.inner_request
 */
@Data
@Table("inner_request")
public class InnerRequest {

    @Id
    private Long id;

    /**
     * 请求唯一ID
     */
    @Column("request_id")
    private String requestId;

    /**
     * 服务编码/穿透码
     */
    @Column("code")
    private String code;

    /**
     * 请求参数 JSON
     */
    @Column("param_data")
    private String paramData;

    /**
     * 通道类型
     */
    @Column("channel_type")
    private String channelType;

    /**
     * 流水号
     */
    @Column("serial_no")
    private String serialNo;

    /**
     * 来源
     */
    @Column("source")
    private String source;

    /**
     * 目标（省码）
     */
    @Column("target")
    private String target;

    /**
     * 状态：0-待处理 1-处理中 2-已完成 3-失败
     */
    @Column("status")
    private Integer status;

    /**
     * 创建时间
     */
    @Column("create_time")
    private LocalDateTime createTime;

    /**
     * 更新时间
     */
    @Column("update_time")
    private LocalDateTime updateTime;
}
