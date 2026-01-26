# 第二阶段：消费链路性能优化 (Binlog → Consumer)

## 1. 核心目标与验收标准 (Goal & Success Criteria)

**核心目标**: 将 `scp0006` 服务的 **消费吞吐量提升至 10,000+ TPS**。

| 关键指标 | 目标值 | 备注 |
|---|---|---|
| ✅ **消费 TPS** | **≥ 10,000** | **唯一的核心验收指标** |
| 消费延迟 (LAG) | < 1s | 在压测中 `LAG` 不应持续增长 |
| 错误率 | < 1% | `scp0006` 日志无持续性错误 |

> ⚠️ **验收警告**：压测工具的“写入TPS”仅代表上游压力，绝不能作为本次任务的达标依据。**必须以消费端的TPS为准。**

---

## 2. 测试与验证流程 (Test & Verification)

### A. 生成负载 (Generate Load)

**目的**: 为消费端提供 > 10,000 TPS 的上游数据压力。

```bash
# 确保已在 perf-test/venv 环境
python3 perf-test/mysql_baseline_test.py --host 192.168.123.114 --concurrency 50 --batch-size 100 --duration 60
```

### B. 计算消费 TPS (Calculate Consumer TPS)

**目的**: 在A步骤压测期间，精确计算 `scp0006` 的实际处理速度。

```bash
# 脚本化自动计算消费TPS

# 1. 定义一个函数，用于自动提取并加总所有分区的 CURRENT-OFFSET
#    此函数会连接到 Kafka 容器，执行 consumer-groups 命令，
#    并通过 awk 过滤表头和非数字行，累加第四列（CURRENT-OFFSET）的值。
get_total_offset() {
    docker -H tcp://192.168.123.114:2375 exec kafka-inner \
      kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group scp0006-group | \
      awk '!/PARTITION/ && $4 ~ /^[0-9]+$/ { sum += $4 } END { print sum }'
}

# 2. 执行计算流程：两次采集 Offset，中间间隔 10 秒
echo "正在采集第一次 Offset..."
OFFSET_1=$(get_total_offset)
echo "第一次 Offset 总和: $OFFSET_1"

echo "等待 10 秒..."
sleep 10

echo "正在采集第二次 Offset..."
OFFSET_2=$(get_total_offset)
echo "第二次 Offset 总和: $OFFSET_2"

# 3. 使用 bc 计算器进行浮点数运算，得出平均 TPS
#    'scale=2' 表示保留两位小数
TPS=$(echo "scale=2; ($OFFSET_2 - $OFFSET_1) / 10" | bc)

echo "------------------------------------"
echo "【结果】平均消费 TPS 约为: $TPS"
echo "------------------------------------"
```
---

## 3. 约束与参考 (Constraints & Reference)

- **优化范围**: `Canal` 配置、`Kafka` 配置、`scp0006` 消费逻辑。
- **构建方式**: **禁止 `mvn`**，必须使用 `./deploy-registryCD.sh all`。
- **结果记录**: 优化内容和消费 TPS 结果必须追加到 `perf-test/binlog-optimization-iterations.md`。
- **日志排查**:
  - `docker -H tcp://192.168.123.114:2375 logs scp0006 --tail 200`
  - `docker -H tcp://192.168.123.114:2375 logs canal-inner --tail 100`

