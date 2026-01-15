wrk.method = "POST"
wrk.headers["Content-Type"] = "application/x-www-form-urlencoded"

request = function()
    local id = math.random(100000, 999999)
    local body = 'code=yhzx&paramData={"test":"perf' .. id .. '"}'
    return wrk.format(nil, nil, nil, body)
end
