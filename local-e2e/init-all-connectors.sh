#!/bin/bash
# 初始化所有 Debezium Connectors
# 用于本地 E2E 测试环境

set -e

INNER_CONNECT_URL="${INNER_CONNECT_URL:-http://localhost:8084}"
OUTER_CONNECT_URL="${OUTER_CONNECT_URL:-http://localhost:8083}"

echo "=========================================="
echo "初始化 Debezium Connectors"
echo "=========================================="

# 等待 Inner Kafka Connect 就绪
echo ""
echo "[Inner] 等待 Kafka Connect 就绪 ($INNER_CONNECT_URL)..."
until curl -s "$INNER_CONNECT_URL/" > /dev/null 2>&1; do
    echo "  等待中..."
    sleep 5
done
echo "[Inner] Kafka Connect 已就绪！"

# 等待 Outer Kafka Connect 就绪
echo ""
echo "[Outer] 等待 Kafka Connect 就绪 ($OUTER_CONNECT_URL)..."
until curl -s "$OUTER_CONNECT_URL/" > /dev/null 2>&1; do
    echo "  等待中..."
    sleep 5
done
echo "[Outer] Kafka Connect 已就绪！"

# ==================== Inner Connector ====================
INNER_CONNECTOR_NAME="inner-mysql-connector"
echo ""
echo "[Inner] 检查 connector: $INNER_CONNECTOR_NAME"

EXISTING_INNER=$(curl -s "$INNER_CONNECT_URL/connectors" | grep -o "$INNER_CONNECTOR_NAME" || true)
if [ -n "$EXISTING_INNER" ]; then
    echo "[Inner] Connector 已存在，跳过创建"
else
    echo "[Inner] 创建 connector..."
    curl -X POST "$INNER_CONNECT_URL/connectors" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "'"$INNER_CONNECTOR_NAME"'",
        "config": {
          "connector.class": "io.debezium.connector.mysql.MySqlConnector",
          "tasks.max": "1",
          "database.hostname": "mysql-inner",
          "database.port": "3306",
          "database.user": "root",
          "database.password": "root123",
          "database.server.id": "184054",
          "topic.prefix": "inner",
          "database.include.list": "inner_gateway",
          "table.include.list": "inner_gateway.inner_request",
          "schema.history.internal.kafka.bootstrap.servers": "kafka-inner:9092",
          "schema.history.internal.kafka.topic": "schema-changes.inner_gateway",
          "include.schema.changes": "false",
          "transforms": "route",
          "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
          "transforms.route.regex": "inner\\.inner_gateway\\.inner_request",
          "transforms.route.replacement": "inner_request_binlog"
        }
      }'
    echo ""
fi

# ==================== Outer Connector ====================
OUTER_CONNECTOR_NAME="outer-mysql-connector"
echo ""
echo "[Outer] 检查 connector: $OUTER_CONNECTOR_NAME"

EXISTING_OUTER=$(curl -s "$OUTER_CONNECT_URL/connectors" | grep -o "$OUTER_CONNECTOR_NAME" || true)
if [ -n "$EXISTING_OUTER" ]; then
    echo "[Outer] Connector 已存在，跳过创建"
else
    echo "[Outer] 创建 connector..."
    curl -X POST "$OUTER_CONNECT_URL/connectors" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "'"$OUTER_CONNECTOR_NAME"'",
        "config": {
          "connector.class": "io.debezium.connector.mysql.MySqlConnector",
          "tasks.max": "1",
          "database.hostname": "mysql-outer",
          "database.port": "3306",
          "database.user": "root",
          "database.password": "root123",
          "database.server.id": "184055",
          "topic.prefix": "outer",
          "database.include.list": "outer_gateway",
          "table.include.list": "outer_gateway.outer_response",
          "schema.history.internal.kafka.bootstrap.servers": "kafka-outer:9092",
          "schema.history.internal.kafka.topic": "schema-changes.outer_gateway",
          "include.schema.changes": "false",
          "transforms": "route",
          "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
          "transforms.route.regex": "outer\\.outer_gateway\\.outer_response",
          "transforms.route.replacement": "outer_response_binlog"
        }
      }'
    echo ""
fi

# 等待 connectors 启动
echo ""
echo "等待 connectors 启动..."
sleep 5

# 检查状态
echo ""
echo "=========================================="
echo "Connector 状态"
echo "=========================================="

echo ""
echo "[Inner] $INNER_CONNECTOR_NAME:"
curl -s "$INNER_CONNECT_URL/connectors/$INNER_CONNECTOR_NAME/status" | python3 -m json.tool 2>/dev/null || \
curl -s "$INNER_CONNECT_URL/connectors/$INNER_CONNECTOR_NAME/status"

echo ""
echo "[Outer] $OUTER_CONNECTOR_NAME:"
curl -s "$OUTER_CONNECT_URL/connectors/$OUTER_CONNECTOR_NAME/status" | python3 -m json.tool 2>/dev/null || \
curl -s "$OUTER_CONNECT_URL/connectors/$OUTER_CONNECTOR_NAME/status"

echo ""
echo "=========================================="
echo "Debezium Connectors 初始化完成！"
echo "=========================================="
