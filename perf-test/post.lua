-- wrk POST 请求脚本
-- 用法: wrk -t2 -c10 -d30s -s post.lua http://192.168.123.66:8080
--
-- 模拟真实场景：混合发送多种快慢不同的服务请求
-- 服务配置（在 target-service 中定义）：
--   fast:      10-30ms    (快速服务)
--   normal:    50-100ms   (普通服务)
--   slow:      200-500ms  (慢速服务)
--   very-slow: 1000-3000ms(超慢服务)
--   unstable:  50-200ms   (不稳定服务，10%错误率)
--   yhzx:      30-80ms    (用户中心)
--   zdzx:      100-300ms  (账单中心)
--
-- 可通过环境变量 SERVICE_CODE 指定单一服务测试

wrk.method = "POST"
wrk.headers["Content-Type"] = "application/x-www-form-urlencoded"

-- 服务分布配置（模拟真实流量比例）
-- 快服务占比大，慢服务占比小
local codes = {
    "fast", "fast", "fast",      -- 30% 快速服务
    "normal", "normal",          -- 20% 普通服务
    "yhzx", "yhzx",              -- 20% 用户中心
    "zdzx",                      -- 10% 账单中心
    "slow",                      -- 10% 慢速服务
    "unstable"                   -- 10% 不稳定服务
}

local counter = 0

function request()
    counter = counter + 1
    -- 轮询选择服务
    local code = codes[(counter % #codes) + 1]
    local path = "/inner/c1/" .. code
    local body = string.format('code=%s&paramData={"test":"perf","seq":%d,"service":"%s"}', code, counter, code)
    return wrk.format("POST", path, nil, body)
end

-- 响应处理（可选）
function response(status, headers, body)
    if status ~= 200 then
        -- 记录非 200 响应
    end
end
