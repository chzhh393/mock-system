package com.mock.outerconsumer.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

import java.util.List;
import java.util.Map;

/**
 * Canal Binlog 消息模型
 *
 * Canal 推送到 Kafka 的消息格式：
 * {
 *   "data": [...],           // 变更后的数据
 *   "database": "xxx",       // 数据库名
 *   "es": 1234567890,        // 事件时间戳
 *   "id": 1,                 // 消息ID
 *   "isDdl": false,          // 是否为DDL语句
 *   "mysqlType": {...},      // MySQL字段类型
 *   "old": [...],            // 变更前的数据（UPDATE时有值）
 *   "pkNames": [...],        // 主键字段名
 *   "sql": "",               // SQL语句
 *   "sqlType": {...},        // SQL类型
 *   "table": "xxx",          // 表名
 *   "ts": 1234567890,        // Canal处理时间戳
 *   "type": "INSERT"         // 操作类型：INSERT/UPDATE/DELETE
 * }
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class CanalMessage {

    /**
     * 变更后的数据列表
     * 每条数据是一个 Map，key 为字段名，value 为字段值
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

    /**
     * MySQL字段类型映射
     */
    private Map<String, String> mysqlType;

    /**
     * SQL类型映射
     */
    private Map<String, Integer> sqlType;

    /**
     * SQL语句（DDL时有值）
     */
    private String sql;
}
