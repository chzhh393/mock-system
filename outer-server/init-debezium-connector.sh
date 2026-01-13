#!/bin/bash
# Debezium MySQL Connector 初始化脚本 - 机器A（外网）
# 用于在 Kafka Connect 启动后创建 MySQL connector

set -e

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
CONNECTOR_NAME="outer-mysql-connector"

echo "等待 Kafka Connect 就绪..."
until curl -s "$CONNECT_URL/" > /dev/null 2>&1; do
    echo "Kafka Connect 尚未就绪，等待中..."
    sleep 5
done
echo "Kafka Connect 已就绪！"

# 检查 connector 是否已存在
EXISTING=$(curl -s "$CONNECT_URL/connectors" | grep -o "$CONNECTOR_NAME")
if [ -n "$EXISTING" ]; then
    echo "Connector '$CONNECTOR_NAME' 已存在"
    curl -s "$CONNECT_URL/connectors/$CONNECTOR_NAME/status" | python3 -m json.tool 2>/dev/null || \
    curl -s "$CONNECT_URL/connectors/$CONNECTOR_NAME/status"
    exit 0
fi

echo "创建 Debezium MySQL Connector..."
curl -X POST "$CONNECT_URL/connectors" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"$CONNECTOR_NAME"'",
    "config": {
      "connector.class": "io.debezium.connector.mysql.MySqlConnector",
      "tasks.max": "1",
      "database.hostname": "mysql",
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
echo "等待 connector 启动..."
sleep 5

# 检查状态
echo "Connector 状态:"
curl -s "$CONNECT_URL/connectors/$CONNECTOR_NAME/status" | python3 -m json.tool 2>/dev/null || \
curl -s "$CONNECT_URL/connectors/$CONNECTOR_NAME/status"

echo ""
echo "✅ Debezium MySQL Connector 创建完成！"
