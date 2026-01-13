#!/bin/bash
# Canal 验证脚本
# 用法: ./verify-canal.sh [inner|outer]

set -e

MODE=${1:-inner}
echo "=========================================="
echo "Canal 验证脚本 - 模式: $MODE"
echo "=========================================="

if [ "$MODE" == "inner" ]; then
    MYSQL_CONTAINER="mysql-inner"
    CANAL_CONTAINER="canal-inner"
    KAFKA_CONTAINER="kafka-inner"
    DB_NAME="inner_gateway"
    TABLE_NAME="inner_request"
    KAFKA_TOPIC="inner_request_binlog"
elif [ "$MODE" == "outer" ]; then
    MYSQL_CONTAINER="mysql-outer"
    CANAL_CONTAINER="canal-outer"
    KAFKA_CONTAINER="kafka-outer"
    DB_NAME="outer_gateway"
    TABLE_NAME="outer_response"
    KAFKA_TOPIC="outer_response_binlog"
else
    echo "错误: 未知模式 '$MODE'，请使用 'inner' 或 'outer'"
    exit 1
fi

echo ""
echo "【步骤 1】检查容器状态"
echo "-------------------------------------------"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(NAME|$MYSQL_CONTAINER|$CANAL_CONTAINER|$KAFKA_CONTAINER)" || true

echo ""
echo "【步骤 2】检查 MySQL canal 用户"
echo "-------------------------------------------"
docker exec $MYSQL_CONTAINER mysql -uroot -proot123 -e "SELECT user, host FROM mysql.user WHERE user='canal';" 2>/dev/null || echo "警告: 无法连接 MySQL"

echo ""
echo "【步骤 3】检查 MySQL Binlog 配置"
echo "-------------------------------------------"
docker exec $MYSQL_CONTAINER mysql -uroot -proot123 -e "SHOW VARIABLES LIKE '%binlog%';" 2>/dev/null | grep -E "(log_bin|binlog_format|binlog_row_image)" || echo "警告: 无法获取 binlog 配置"

echo ""
echo "【步骤 4】检查 Canal 日志（最近 20 行）"
echo "-------------------------------------------"
docker logs --tail 20 $CANAL_CONTAINER 2>&1 || echo "警告: 无法获取 Canal 日志"

echo ""
echo "【步骤 5】检查 Canal 连接状态"
echo "-------------------------------------------"
# 查找关键日志
echo "查找 'find start position' 或 'successfully'..."
docker logs $CANAL_CONTAINER 2>&1 | grep -i -E "(find start position|successfully|binlog|error|exception)" | tail -10 || echo "未找到关键日志"

echo ""
echo "【步骤 6】检查 Kafka Topic"
echo "-------------------------------------------"
docker exec $KAFKA_CONTAINER kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null | grep -E "($KAFKA_TOPIC|inner_request|outer_response)" || echo "Topic 可能尚未创建（首次写入时自动创建）"

echo ""
echo "【步骤 7】测试数据捕获"
echo "-------------------------------------------"
TEST_ID="test-canal-$(date +%s)"
echo "插入测试数据: request_id=$TEST_ID"

if [ "$MODE" == "inner" ]; then
    docker exec $MYSQL_CONTAINER mysql -uroot -proot123 $DB_NAME -e \
        "INSERT INTO $TABLE_NAME (request_id, code, param_data, channel_type) VALUES ('$TEST_ID', 'test', '{\"verify\":\"canal\"}', 'verify');" 2>/dev/null
else
    docker exec $MYSQL_CONTAINER mysql -uroot -proot123 $DB_NAME -e \
        "INSERT INTO $TABLE_NAME (request_id, response_data, response_code) VALUES ('$TEST_ID', '{\"verify\":\"canal\"}', '0000');" 2>/dev/null
fi

echo "等待 3 秒让 Canal 捕获变更..."
sleep 3

echo ""
echo "【步骤 8】从 Kafka 消费验证消息"
echo "-------------------------------------------"
echo "尝试从 $KAFKA_TOPIC 消费消息（超时 5 秒）..."
docker exec $KAFKA_CONTAINER timeout 5 kafka-console-consumer \
    --bootstrap-server localhost:9092 \
    --topic $KAFKA_TOPIC \
    --from-beginning \
    --max-messages 1 2>/dev/null || echo "未能消费到消息（可能是 Canal 未正确配置或消息格式问题）"

echo ""
echo "=========================================="
echo "验证完成！"
echo ""
echo "如果步骤 4-5 显示 'find start position' 且步骤 8 能消费到消息，"
echo "说明 Canal 工作正常。"
echo "=========================================="
