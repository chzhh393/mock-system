#!/bin/bash
# 本地端到端测试环境启动脚本（精简版）
# 使用单 Kafka 集群，适合资源受限的本地环境

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "本地端到端测试环境启动（精简版）"
echo "=========================================="
echo ""
echo "注意：精简版使用单 Kafka 集群减少内存占用"
echo ""

# 可选参数：--clean 完全重置环境
CLEAN_START=false
if [ "$1" == "--clean" ]; then
    CLEAN_START=true
fi

# ==================== 步骤 1: 清理旧环境 ====================
echo "[步骤 1/5] 清理旧环境..."

# 停止完整版（如有）
docker-compose -f docker-compose.local.yml down 2>/dev/null || true
# 停止精简版
docker-compose -f docker-compose.lite.yml down 2>/dev/null || true

if [ "$CLEAN_START" = true ]; then
    echo "  删除所有 volumes（完全重置）..."
    docker volume rm local-e2e_mysql_inner_data local-e2e_mysql_outer_data \
        local-e2e_kafka_inner_data local-e2e_kafka_outer_data \
        local-e2e_kafka_data local-e2e_redis_data 2>/dev/null || true
fi

echo "  清理完成！"
echo ""

# ==================== 步骤 2: 启动基础设施 ====================
echo "[步骤 2/5] 启动基础设施 (MySQL x2, Kafka, Redis)..."
docker-compose -f docker-compose.lite.yml up -d mysql-inner mysql-outer kafka redis

echo "  等待基础服务启动（60秒）..."
sleep 60

# 检查健康状态
echo "  检查服务健康状态..."
docker-compose -f docker-compose.lite.yml ps

echo ""

# ==================== 步骤 3: 启动 Kafka Connect ====================
echo "[步骤 3/5] 启动 Kafka Connect..."
docker-compose -f docker-compose.lite.yml up -d kafka-connect

echo "  等待 Kafka Connect 启动..."
until curl -s http://localhost:8083/ > /dev/null 2>&1; do
    echo "    等待中..."
    sleep 5
done
echo "  Kafka Connect 就绪！"

echo ""

# ==================== 步骤 4: 初始化 Debezium Connectors ====================
echo "[步骤 4/5] 初始化 Debezium Connectors..."
./init-connectors-lite.sh

echo ""

# ==================== 步骤 5: 构建并启动应用服务 ====================
echo "[步骤 5/5] 构建并启动应用服务..."
docker-compose -f docker-compose.lite.yml up -d --build \
    target-service scp0006 scp0005 outer-consumer

echo "  等待应用启动（30秒）..."
sleep 30

echo ""
echo "=========================================="
echo "启动完成！"
echo "=========================================="
echo ""
echo "服务端口分配："
echo "  Inner MySQL:     localhost:3307"
echo "  Outer MySQL:     localhost:3306"
echo "  Kafka:           localhost:9092"
echo "  Kafka Connect:   localhost:8083"
echo "  Redis:           localhost:6379"
echo "  target-service:  localhost:8017"
echo "  scp0006:         localhost:8082"
echo "  scp0005:         localhost:8080"
echo "  outer-consumer:  localhost:8081"
echo ""
echo "测试命令："
echo "  ./test-lite.sh"
echo ""
echo "查看日志："
echo "  docker-compose -f docker-compose.lite.yml logs -f scp0005"
echo "  docker-compose -f docker-compose.lite.yml logs -f scp0006"
echo ""
