package com.mock.scp0006.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

import java.util.List;
import java.util.Map;

/**
 * Canal Binlog 消息模型
 *
 * Canal 推送到 Kafka 的消息格式
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class CanalMessage {

    /**
     * 变更后的数据列表
     */
    private List<Map<String, String>> data;

    /**
     * 数据库名
     */
    private String database;

    /**
     * 事件时间戳（毫秒）
     */
    private Long es;

    /**
     * 消息ID
     */
    private Long id;

    /**
     * 是否为DDL语句
     */
    private Boolean isDdl;

    /**
     * 表名
     */
    private String table;

    /**
     * Canal处理时间戳（毫秒）
     */
    private Long ts;

    /**
     * 操作类型：INSERT/UPDATE/DELETE
     */
    private String type;

    /**
     * 变更前的数据（UPDATE时有值）
     */
    private List<Map<String, String>> old;

    /**
     * 主键字段名列表
     */
    private List<String> pkNames;
}
