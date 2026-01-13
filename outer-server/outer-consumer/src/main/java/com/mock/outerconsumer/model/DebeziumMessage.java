package com.mock.outerconsumer.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

import java.util.Map;

/**
 * Debezium Binlog 消息模型
 *
 * Debezium 推送到 Kafka 的消息格式
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class DebeziumMessage {

    /**
     * 消息载荷
     */
    private Payload payload;

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Payload {
        /**
         * 变更前的数据（UPDATE/DELETE时有值）
         */
        private Map<String, Object> before;

        /**
         * 变更后的数据（INSERT/UPDATE时有值）
         */
        private Map<String, Object> after;

        /**
         * 数据源信息
         */
        private Source source;

        /**
         * 操作类型：c=create, u=update, d=delete, r=read(snapshot)
         */
        private String op;

        /**
         * 事件时间戳（毫秒）
         */
        @JsonProperty("ts_ms")
        private Long tsMs;
    }

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Source {
        /**
         * Debezium 版本
         */
        private String version;

        /**
         * 连接器类型
         */
        private String connector;

        /**
         * 连接器名称
         */
        private String name;

        /**
         * 数据库名
         */
        private String db;

        /**
         * 表名
         */
        private String table;

        /**
         * 服务器ID
         */
        @JsonProperty("server_id")
        private Long serverId;

        /**
         * binlog 文件名
         */
        private String file;

        /**
         * binlog 位置
         */
        private Long pos;
    }

    /**
     * 判断是否为 INSERT 操作
     */
    public boolean isInsert() {
        return payload != null && "c".equals(payload.getOp());
    }

    /**
     * 判断是否为 UPDATE 操作
     */
    public boolean isUpdate() {
        return payload != null && "u".equals(payload.getOp());
    }

    /**
     * 判断是否为 DELETE 操作
     */
    public boolean isDelete() {
        return payload != null && "d".equals(payload.getOp());
    }

    /**
     * 获取变更后的数据
     */
    public Map<String, Object> getAfterData() {
        return payload != null ? payload.getAfter() : null;
    }
}
