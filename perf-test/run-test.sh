#!/bin/bash
#
# 性能基线测试脚本
#

set -e

# 配置
# 注意：post.lua 会动态生成路径 /inner/c1/yhzx 和 /inner/c1/fast
TARGET_URL="${TARGET_URL:-http://192.168.123.66:8080}"
THREADS="${THREADS:-2}"
CONNECTIONS="${CONNECTIONS:-10}"
DURATION="${DURATION:-30s}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "════════════════════════════════════════════"
echo "   内外网穿透网关 - 性能基线测试"
echo "════════════════════════════════════════════"
echo ""
echo "目标地址: $TARGET_URL"
echo "线程数:   $THREADS"
echo "并发数:   $CONNECTIONS"
echo "持续时间: $DURATION"
echo ""

# 检查 wrk 是否安装
if ! command -v wrk &> /dev/null; then
    echo "错误: wrk 未安装"
    echo "请执行: brew install wrk"
    exit 1
fi

# 先发送单个请求验证服务可用（使用快服务验证，避免等待30s）
echo "验证服务可用性..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$TARGET_URL/inner/c1/fast" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "code=fast&paramData={\"test\":\"warmup\"}" \
    --max-time 10 || echo "000")

if [ "$HTTP_CODE" != "200" ]; then
    echo "错误: 服务不可用 (HTTP $HTTP_CODE)"
    echo "请确保服务已启动: ./deploy-registry.sh status"
    exit 1
fi
echo "服务可用 ✓"
echo ""

# 执行压测
echo "开始压测..."
echo "────────────────────────────────────────────"
wrk -t$THREADS -c$CONNECTIONS -d$DURATION -s "$SCRIPT_DIR/post.lua" "$TARGET_URL"
echo "────────────────────────────────────────────"
echo ""
echo "测试完成！"
echo ""
echo "关键指标说明:"
echo "  - Requests/sec: TPS (每秒请求数)"
echo "  - Latency avg:  平均延迟"
echo "  - Latency 99%:  P99 延迟"
echo "  - Non-2xx:      错误请求数"
