package com.mock.scp0005.model;

import lombok.Data;

import java.io.Serializable;

/**
 * 请求对象 - 对应原系统的 RequestDo
 *
 * 客户端通过 Form 表单提交以下字段：
 * - code: 服务编码/穿透码，用于查找内网服务路径
 * - paramData: 请求参数 JSON 字符串
 */
@Data
public class RequestDo implements Serializable {

    private static final long serialVersionUID = 1L;

    /**
     * 穿透码 - 用于查找内网服务路径
     * 例如：0000, yhzx, zdzx
     */
    private String code;

    /**
     * 请求参数 - JSON 字符串
     * 包含完整的业务请求数据
     */
    private String paramData;
}
