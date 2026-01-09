package com.mock.targetservice.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 统一 API 响应模型
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonInclude(JsonInclude.Include.NON_NULL)
public class ApiResponse<T> {

    /**
     * 响应码
     */
    private String code;

    /**
     * 响应消息
     */
    private String message;

    /**
     * 响应数据
     */
    private T data;

    /**
     * 请求ID（用于追踪）
     */
    private String requestId;

    /**
     * 处理耗时（毫秒）
     */
    private Long elapsed;

    /**
     * 成功响应
     */
    public static <T> ApiResponse<T> success(T data) {
        return ApiResponse.<T>builder()
                .code("200")
                .message("success")
                .data(data)
                .build();
    }

    /**
     * 成功响应（带请求ID和耗时）
     */
    public static <T> ApiResponse<T> success(T data, String requestId, long elapsed) {
        return ApiResponse.<T>builder()
                .code("200")
                .message("success")
                .data(data)
                .requestId(requestId)
                .elapsed(elapsed)
                .build();
    }

    /**
     * 错误响应
     */
    public static <T> ApiResponse<T> error(String code, String message) {
        return ApiResponse.<T>builder()
                .code(code)
                .message(message)
                .build();
    }

    /**
     * 错误响应（带请求ID）
     */
    public static <T> ApiResponse<T> error(String code, String message, String requestId) {
        return ApiResponse.<T>builder()
                .code(code)
                .message(message)
                .requestId(requestId)
                .build();
    }
}
