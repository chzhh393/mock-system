#!/bin/bash
# 机器 B（内网）启动脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=========================================="
echo "  机器 B（内网）启动脚本"
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
echo "步骤 1/3: 启动 MySQL..."
docker-compose up -d mysql

echo ""
echo "步骤 2/3: 等待 MySQL 启动（30秒）..."
sleep 30

echo ""
echo "步骤 3/3: 启动 Canal..."
docker-compose up -d canal

echo ""
echo "=========================================="
echo "  启动完成！"
echo "=========================================="
echo ""
echo "服务状态："
docker-compose ps

echo ""
echo "验证命令："
echo "  MySQL:  docker exec -it mysql-inner mysql -uroot -proot123 -e 'SHOW DATABASES;'"
echo "  请求表: docker exec -it mysql-inner mysql -uroot -proot123 -e 'USE inner_gateway; SHOW TABLES;'"
