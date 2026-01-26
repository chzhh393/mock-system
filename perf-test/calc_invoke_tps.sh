#!/bin/bash
# 计算 scp0006 HTTP 请求发送 TPS 的脚本

echo "=========================================="
echo "  scp0006 HTTP 请求发送 TPS 计算工具"
echo "=========================================="

# 获取 scp0006 统计信息
get_stats() {
    curl -s http://192.168.123.114:8082/api/stats 2>/dev/null
}

# 从 JSON 中提取 targetInvokeSuccess
get_invoke_success() {
    echo "$1" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('metrics', {}).get('targetInvokeSuccess', 0))"
}

# 从 JSON 中提取 targetInvokeFail
get_invoke_fail() {
    echo "$1" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('metrics', {}).get('targetInvokeFail', 0))"
}

echo ""
echo "正在采集第一次统计数据..."
STATS_1=$(get_stats)
SUCCESS_1=$(get_invoke_success "$STATS_1")
FAIL_1=$(get_invoke_fail "$STATS_1")
echo "第一次 targetInvokeSuccess: $SUCCESS_1"
echo "第一次 targetInvokeFail: $FAIL_1"

INTERVAL=10
echo ""
echo "等待 ${INTERVAL} 秒..."
sleep $INTERVAL

echo ""
echo "正在采集第二次统计数据..."
STATS_2=$(get_stats)
SUCCESS_2=$(get_invoke_success "$STATS_2")
FAIL_2=$(get_invoke_fail "$STATS_2")
echo "第二次 targetInvokeSuccess: $SUCCESS_2"
echo "第二次 targetInvokeFail: $FAIL_2"

# 计算增量
SUCCESS_DELTA=$((SUCCESS_2 - SUCCESS_1))
FAIL_DELTA=$((FAIL_2 - FAIL_1))

# 计算 TPS
if command -v bc &> /dev/null; then
    TPS=$(echo "scale=2; $SUCCESS_DELTA / $INTERVAL" | bc)
else
    TPS=$((SUCCESS_DELTA / INTERVAL))
fi

# 计算错误率
TOTAL_DELTA=$((SUCCESS_DELTA + FAIL_DELTA))
if [ $TOTAL_DELTA -gt 0 ]; then
    if command -v bc &> /dev/null; then
        ERROR_RATE=$(echo "scale=4; $FAIL_DELTA * 100 / $TOTAL_DELTA" | bc)
    else
        ERROR_RATE=$((FAIL_DELTA * 100 / TOTAL_DELTA))
    fi
else
    ERROR_RATE=0
fi

echo ""
echo "=========================================="
echo "【结果】"
echo "  成功请求增量: $SUCCESS_DELTA"
echo "  失败请求增量: $FAIL_DELTA"
echo "  采样间隔: ${INTERVAL}s"
echo "  HTTP 请求发送 TPS: $TPS"
echo "  错误率: ${ERROR_RATE}%"
echo "=========================================="

echo ""
echo "完整统计信息:"
echo "$STATS_2" | python3 -m json.tool 2>/dev/null || echo "$STATS_2"
