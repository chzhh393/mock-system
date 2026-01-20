-- wrk POST 请求脚本 - 只测试 slow 服务
wrk.method = "POST"
wrk.headers["Content-Type"] = "application/x-www-form-urlencoded"

local counter = 0

function request()
    counter = counter + 1
    local path = "/inner/c1/slow"
    local body = string.format('code=slow&paramData={"test":"perf","seq":%d}', counter)
    return wrk.format("POST", path, nil, body)
end
