#!/bin/bash
# 初始化 Debezium Connectors（精简版）
# 在共享 Kafka Connect 上创建两个 MySQL connectors

set -e

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"

echo "=========================================="
echo "初始化 Debezium Connectors（精简版）"
echo "=========================================="

echo ""
echo "等待 Kafka Connect 就绪 ($CONNECT_URL)..."
until curl -s "$CONNECT_URL/" > /dev/null 2>&1; do
    echo "  等待中..."
    sleep 5
done
echo "Kafka Connect 已就绪！"

# ==================== Inner Connector ====================
INNER_CONNECTOR_NAME="inner-mysql-connector"
echo ""
echo "[Inner] 检查 connector: $INNER_CONNECTOR_NAME"

EXISTING_INNER=$(curl -s "$CONNECT_URL/connectors" | grep -o "$INNER_CONNECTOR_NAME" || true)
if [ -n "$EXISTING_INNER" ]; then
    echo "[Inner] Connector 已存在，跳过创建"
else
    echo "[Inner] 创建 connector..."
    curl -X POST "$CONNECT_URL/connectors" \
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
          "schema.history.internal.kafka.bootstrap.servers": "kafka:9092",
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

EXISTING_OUTER=$(curl -s "$CONNECT_URL/connectors" | grep -o "$OUTER_CONNECTOR_NAME" || true)
if [ -n "$EXISTING_OUTER" ]; then
    echo "[Outer] Connector 已存在，跳过创建"
else
    echo "[Outer] 创建 connector..."
    curl -X POST "$CONNECT_URL/connectors" \
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
          "schema.history.internal.kafka.bootstrap.servers": "kafka:9092",
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
curl -s "$CONNECT_URL/connectors/$INNER_CONNECTOR_NAME/status" | python3 -m json.tool 2>/dev/null || \
curl -s "$CONNECT_URL/connectors/$INNER_CONNECTOR_NAME/status"

echo ""
echo "[Outer] $OUTER_CONNECTOR_NAME:"
curl -s "$CONNECT_URL/connectors/$OUTER_CONNECTOR_NAME/status" | python3 -m json.tool 2>/dev/null || \
curl -s "$CONNECT_URL/connectors/$OUTER_CONNECTOR_NAME/status"

echo ""
echo "=========================================="
echo "Debezium Connectors 初始化完成！"
echo "=========================================="
