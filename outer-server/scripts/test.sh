#!/bin/bash
# 端到端测试脚本

set -e

echo "=========================================="
echo "  内外网穿透网关 - 端到端测试"
echo "=========================================="

# 需要用户提供机器B的IP
MACHINE_B_IP="${1:-}"

if [ -z "$MACHINE_B_IP" ]; then
    echo "用法: ./test.sh <机器B_IP>"
    echo "示例: ./test.sh 192.168.1.101"
    exit 1
fi

echo ""
echo "测试 1: 检查本机服务状态"
echo "----------------------------------------"
docker-compose ps

echo ""
echo "测试 2: 检查本机 MySQL 连接"
echo "----------------------------------------"
docker exec mysql-outer mysql -uroot -proot123 -e "SELECT 'MySQL OK' AS status;"

echo ""
echo "测试 3: 检查本机 Redis 连接"
echo "----------------------------------------"
docker exec redis redis-cli ping

echo ""
echo "测试 4: 检查本机 Kafka Topic"
echo "----------------------------------------"
docker exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --list

echo ""
echo "测试 5: 检查跨机器 MySQL 连接（机器B）"
echo "----------------------------------------"
mysql -h "$MACHINE_B_IP" -P 3306 -uroot -proot123 -e "SELECT 'Cross-machine MySQL OK' AS status;" 2>/dev/null \
    || echo "无法连接机器B的MySQL，请检查网络和机器B是否已启动"

echo ""
echo "测试 6: 模拟写入内网请求表"
echo "----------------------------------------"
REQUEST_ID="test_$(date +%s)"
mysql -h "$MACHINE_B_IP" -P 3306 -uroot -proot123 -e "
USE inner_gateway;
INSERT INTO inner_request (request_id, code, param_data, channel_type, serial_no)
VALUES ('$REQUEST_ID', '0000', '{\"test\": true}', 'TEST', '$REQUEST_ID');
SELECT * FROM inner_request WHERE request_id='$REQUEST_ID';
"

echo ""
echo "测试 7: 检查 Kafka 是否收到消息"
echo "----------------------------------------"
echo "消费 inner_request_binlog topic（等待5秒）..."
timeout 5 docker exec kafka kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic inner_request_binlog \
    --from-beginning \
    --max-messages 1 2>/dev/null || echo "暂无消息或超时"

echo ""
echo "=========================================="
echo "  测试完成"
echo "=========================================="
