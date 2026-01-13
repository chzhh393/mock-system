-- wrk POST 请求脚本
-- 用法: wrk -t2 -c10 -d30s -s post.lua http://192.168.123.66:8080/inner/c1/yhzx

wrk.method = "POST"
wrk.headers["Content-Type"] = "application/x-www-form-urlencoded"

-- 每个请求使用唯一的 requestId
local counter = 0
function request()
    counter = counter + 1
    local body = string.format(
        'code=yhzx&paramData={"test":"perf","seq":%d}',
        counter
    )
    return wrk.format(nil, nil, nil, body)
end

-- 响应处理（可选）
function response(status, headers, body)
    if status ~= 200 then
        -- 记录非 200 响应
    end
end
