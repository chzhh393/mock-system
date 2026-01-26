#!/bin/bash
# 计算 scp0006 消费 TPS 的脚本

export DOCKER_API_VERSION=1.44

echo "=========================================="
echo "  scp0006 消费 TPS 计算工具"
echo "=========================================="

# 定义获取 Kafka 消费者组 offset 的函数
get_total_offset() {
    docker -H tcp://192.168.123.114:2375 exec kafka-inner \
      kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group scp0006-consumer-group 2>/dev/null | \
      awk '!/PARTITION/ && !/GROUP/ && !/^$/ && $4 ~ /^[0-9]+$/ { sum += $4 } END { print sum+0 }'
}

# 获取 scp0006 统计信息
get_stats() {
    curl -s http://192.168.123.114:8082/api/stats 2>/dev/null
}

echo ""
echo "正在采集第一次 Offset..."
OFFSET_1=$(get_total_offset)
STATS_1=$(get_stats)
echo "第一次 Offset 总和: $OFFSET_1"

INTERVAL=10
echo ""
echo "等待 ${INTERVAL} 秒..."
sleep $INTERVAL

echo ""
echo "正在采集第二次 Offset..."
OFFSET_2=$(get_total_offset)
STATS_2=$(get_stats)
echo "第二次 Offset 总和: $OFFSET_2"

# 计算 TPS
if command -v bc &> /dev/null; then
    TPS=$(echo "scale=2; ($OFFSET_2 - $OFFSET_1) / $INTERVAL" | bc)
else
    TPS=$(( ($OFFSET_2 - $OFFSET_1) / $INTERVAL ))
fi

echo ""
echo "=========================================="
echo "【结果】"
echo "  Offset 增量: $(($OFFSET_2 - $OFFSET_1))"
echo "  采样间隔: ${INTERVAL}s"
echo "  平均消费 TPS: $TPS"
echo "=========================================="

echo ""
echo "scp0006 统计信息:"
echo "$STATS_2" | python3 -m json.tool 2>/dev/null || echo "$STATS_2"
