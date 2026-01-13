#!/bin/bash
# 本地端到端测试脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "端到端测试"
echo "=========================================="
echo ""

PASSED=0
FAILED=0

# 测试函数
test_service() {
    local name=$1
    local url=$2
    local expected=$3

    echo -n "  检查 $name... "
    if curl -s "$url" | grep -q "$expected" 2>/dev/null; then
        echo "通过"
        ((PASSED++))
    else
        echo "失败"
        ((FAILED++))
    fi
}

test_http() {
    local name=$1
    local url=$2

    echo -n "  检查 $name... "
    if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200\|204" 2>/dev/null; then
        echo "通过"
        ((PASSED++))
    else
        echo "失败"
        ((FAILED++))
    fi
}

# ==================== 服务健康检查 ====================
echo "[1/4] 服务健康检查"

test_http "Inner Kafka Connect" "http://localhost:8084/"
test_http "Outer Kafka Connect" "http://localhost:8083/"

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
INNER_STATE=$(curl -s http://localhost:8084/connectors/inner-mysql-connector/status | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ "$INNER_STATE" == "RUNNING" ]; then
    echo "通过 (RUNNING)"
    ((PASSED++))
else
    echo "失败 ($INNER_STATE)"
    ((FAILED++))
fi

echo -n "  检查 outer-mysql-connector... "
OUTER_STATE=$(curl -s http://localhost:8083/connectors/outer-mysql-connector/status | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
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
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/actuator/health" 2>/dev/null | grep -qE "200|404"; then
    echo "通过"
    ((PASSED++))
else
    # 尝试其他端点
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/" 2>/dev/null | grep -qE "200|404|405"; then
        echo "通过"
        ((PASSED++))
    else
        echo "失败"
        ((FAILED++))
    fi
fi

echo -n "  检查 scp0006 (port 8082)... "
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8082/actuator/health" 2>/dev/null | grep -qE "200|404"; then
    echo "通过"
    ((PASSED++))
else
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8082/" 2>/dev/null | grep -qE "200|404|405"; then
        echo "通过"
        ((PASSED++))
    else
        echo "失败"
        ((FAILED++))
    fi
fi

echo -n "  检查 target-service (port 8017)... "
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8017/actuator/health" 2>/dev/null | grep -qE "200|404"; then
    echo "通过"
    ((PASSED++))
else
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8017/" 2>/dev/null | grep -qE "200|404|405"; then
        echo "通过"
        ((PASSED++))
    else
        echo "失败"
        ((FAILED++))
    fi
fi

echo -n "  检查 outer-consumer (port 8081)... "
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8081/actuator/health" 2>/dev/null | grep -qE "200|404"; then
    echo "通过"
    ((PASSED++))
else
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8081/" 2>/dev/null | grep -qE "200|404|405"; then
        echo "通过"
        ((PASSED++))
    else
        echo "失败"
        ((FAILED++))
    fi
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
    echo "失败（可能应用未完全启动，请稍后重试）"
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
    echo "  docker-compose -f docker-compose.local.yml logs [服务名]"
    exit 1
fi
