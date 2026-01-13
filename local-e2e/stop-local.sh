#!/bin/bash
# 本地端到端测试环境停止脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "停止本地端到端测试环境"
echo "=========================================="
echo ""

# 停止所有服务
echo "停止所有服务..."
docker-compose -f docker-compose.local.yml down

# 可选参数：--clean 同时删除数据卷
if [ "$1" == "--clean" ]; then
    echo ""
    echo "删除数据卷..."
    docker volume rm local-e2e_mysql_inner_data local-e2e_mysql_outer_data \
        local-e2e_kafka_inner_data local-e2e_kafka_outer_data \
        local-e2e_redis_data 2>/dev/null || true
    echo "数据卷已删除！"
fi

echo ""
echo "=========================================="
echo "环境已停止！"
echo "=========================================="
echo ""
echo "如需完全重置环境，请使用: ./stop-local.sh --clean"
echo ""
