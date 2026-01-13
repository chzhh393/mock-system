#!/bin/bash
# 本地端到端测试脚本（精简版）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "端到端测试（精简版）"
echo "=========================================="
echo ""

PASSED=0
FAILED=0

# ==================== 服务健康检查 ====================
echo "[1/4] 服务健康检查"

echo -n "  检查 Kafka Connect... "
if curl -s http://localhost:8083/ > /dev/null 2>&1; then
    echo "通过"
    ((PASSED++))
else
    echo "失败"
    ((FAILED++))
fi

echo -n "  检查 Redis... "
if docker exec redis redis-cli ping | grep -q "PONG"; then
    echo "通过"
    ((PASSED++))
else
    echo "失败"
    ((FAILED++))
fi

echo -n "  检查 MySQL Inner... "
if docker exec mysql-inner mysqladmin ping -uroot -proot123 2>/dev/null | grep -q "alive"; then
    echo "通过"
    ((PASSED++))
else
    echo "失败"
    ((FAILED++))
fi

echo -n "  检查 MySQL Outer... "
if docker exec mysql-outer mysqladmin ping -uroot -proot123 2>/dev/null | grep -q "alive"; then
    echo "通过"
    ((PASSED++))
else
    echo "失败"
    ((FAILED++))
fi

echo ""

# ==================== Connector 状态检查 ====================
echo "[2/4] Connector 状态检查"

echo -n "  检查 inner-mysql-connector... "
INNER_STATE=$(curl -s http://localhost:8083/connectors/inner-mysql-connector/status 2>/dev/null | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ "$INNER_STATE" == "RUNNING" ]; then
    echo "通过 (RUNNING)"
    ((PASSED++))
else
    echo "失败 ($INNER_STATE)"
    ((FAILED++))
fi

echo -n "  检查 outer-mysql-connector... "
OUTER_STATE=$(curl -s http://localhost:8083/connectors/outer-mysql-connector/status 2>/dev/null | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ "$OUTER_STATE" == "RUNNING" ]; then
    echo "通过 (RUNNING)"
    ((PASSED++))
else
    echo "失败 ($OUTER_STATE)"
    ((FAILED++))
fi

echo ""

# ==================== 应用服务检查 ====================
echo "[3/4] 应用服务检查"

echo -n "  检查 scp0005 (port 8080)... "
SCP0005_OK=false
for endpoint in "/actuator/health" "/"; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080$endpoint" 2>/dev/null || echo "000")
    if [ "$STATUS" == "200" ] || [ "$STATUS" == "404" ] || [ "$STATUS" == "405" ]; then
        SCP0005_OK=true
        break
    fi
done
if [ "$SCP0005_OK" = true ]; then
    echo "通过"
    ((PASSED++))
else
    echo "失败"
    ((FAILED++))
fi

echo -n "  检查 scp0006 (port 8082)... "
SCP0006_OK=false
for endpoint in "/actuator/health" "/"; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8082$endpoint" 2>/dev/null || echo "000")
    if [ "$STATUS" == "200" ] || [ "$STATUS" == "404" ] || [ "$STATUS" == "405" ]; then
        SCP0006_OK=true
        break
    fi
done
if [ "$SCP0006_OK" = true ]; then
    echo "通过"
    ((PASSED++))
else
    echo "失败"
    ((FAILED++))
fi

echo -n "  检查 target-service (port 8017)... "
TARGET_OK=false
for endpoint in "/actuator/health" "/"; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8017$endpoint" 2>/dev/null || echo "000")
    if [ "$STATUS" == "200" ] || [ "$STATUS" == "404" ] || [ "$STATUS" == "405" ]; then
        TARGET_OK=true
        break
    fi
done
if [ "$TARGET_OK" = true ]; then
    echo "通过"
    ((PASSED++))
else
    echo "失败"
    ((FAILED++))
fi

echo -n "  检查 outer-consumer (port 8081)... "
CONSUMER_OK=false
for endpoint in "/actuator/health" "/"; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8081$endpoint" 2>/dev/null || echo "000")
    if [ "$STATUS" == "200" ] || [ "$STATUS" == "404" ] || [ "$STATUS" == "405" ]; then
        CONSUMER_OK=true
        break
    fi
done
if [ "$CONSUMER_OK" = true ]; then
    echo "通过"
    ((PASSED++))
else
    echo "失败"
    ((FAILED++))
fi

echo ""

# ==================== 端到端请求测试 ====================
echo "[4/4] 端到端请求测试"

REQUEST_ID="test-$(date +%s)"
echo "  生成测试请求ID: $REQUEST_ID"

echo -n "  发送请求到 scp0005... "
RESPONSE=$(curl -s -X POST http://localhost:8080/invoke \
    -H "Content-Type: application/json" \
    -d "{\"channel\":\"yhzx\",\"code\":\"yhzx\",\"paramData\":{\"test\":\"data\",\"requestId\":\"$REQUEST_ID\"}}" 2>/dev/null || echo "FAILED")

if [ "$RESPONSE" != "FAILED" ] && [ -n "$RESPONSE" ]; then
    echo "通过"
    echo "  响应: $RESPONSE"
    ((PASSED++))
else
    echo "失败（应用可能未完全启动，请稍后重试）"
    ((FAILED++))
fi

echo ""

# ==================== 数据流检查 ====================
echo "[额外] 数据流检查（手动验证用）"

echo "  Inner MySQL 请求记录:"
docker exec mysql-inner mysql -uroot -proot123 -e "SELECT id, request_id, code, created_at FROM inner_gateway.inner_request ORDER BY id DESC LIMIT 3;" 2>/dev/null || echo "    (无数据或查询失败)"

echo ""
echo "  Outer MySQL 响应记录:"
docker exec mysql-outer mysql -uroot -proot123 -e "SELECT id, request_id, code, created_at FROM outer_gateway.outer_response ORDER BY id DESC LIMIT 3;" 2>/dev/null || echo "    (无数据或查询失败)"

echo ""
echo "  Redis 缓存键:"
docker exec redis redis-cli KEYS "gateway:result:*" 2>/dev/null || echo "    (无数据或查询失败)"

echo ""
echo "=========================================="
echo "测试结果: 通过 $PASSED / 失败 $FAILED"
echo "=========================================="

if [ $FAILED -gt 0 ]; then
    echo ""
    echo "提示：如果有服务失败，请检查日志："
    echo "  docker-compose -f docker-compose.lite.yml logs [服务名]"
    exit 1
fi
