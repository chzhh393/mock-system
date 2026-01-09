#!/bin/bash
# 机器 A（外网）启动脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=========================================="
echo "  机器 A（外网）启动脚本"
echo "=========================================="

# 检查 IP 占位符是否已替换
if grep -q "__MACHINE_A_IP__\|__MACHINE_B_IP__" docker-compose.yml; then
    echo "错误：请先替换 docker-compose.yml 中的 IP 占位符"
    echo ""
    echo "示例命令："
    echo "  sed -i '' \"s/__MACHINE_A_IP__/你的机器A_IP/g\" docker-compose.yml"
    echo "  sed -i '' \"s/__MACHINE_B_IP__/你的机器B_IP/g\" docker-compose.yml"
    exit 1
fi

echo ""
echo "步骤 1/4: 启动基础设施..."
docker-compose up -d mysql redis kafka

echo ""
echo "步骤 2/4: 等待 MySQL 启动（30秒）..."
sleep 30

echo ""
echo "步骤 3/4: 启动 Canal..."
docker-compose up -d canal

echo ""
echo "步骤 4/4: 创建 Kafka Topic..."
sleep 10
docker exec -it kafka kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic inner_request_binlog --partitions 3 --replication-factor 1 --if-not-exists

docker exec -it kafka kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic outer_response_binlog --partitions 3 --replication-factor 1 --if-not-exists

echo ""
echo "=========================================="
echo "  启动完成！"
echo "=========================================="
echo ""
echo "服务状态："
docker-compose ps

echo ""
echo "验证命令："
echo "  MySQL:  docker exec -it mysql-outer mysql -uroot -proot123 -e 'SHOW DATABASES;'"
echo "  Redis:  docker exec -it redis redis-cli ping"
echo "  Kafka:  docker exec -it kafka kafka-topics.sh --bootstrap-server localhost:9092 --list"
