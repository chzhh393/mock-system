## ⚠️ 重要约束

**这是硬性目标，必须达到 TPS ≥ 10,000 才能结束任务，需要修改代码并进行实际压测。**

---

## 1. 背景

scp0006 作为网关服务，需要向下游 target-service 发送 HTTP 请求。
本阶段**绕过 Canal/Kafka**，直接测试和优化 scp0006 发出 HTTP 请求的能力。

**当前环境配置**：
- target-service 延迟：50ms（模拟真实下游服务的响应时间）
- 压测 API 已内置于 scp0006，可直接调用

**当前基线**：
- 100 并发：~1,800 TPS
- 200 并发：~3,600 TPS
- 500 并发：~3,500 TPS（遇到瓶颈）

---

## 2. 核心目标与验收标准

| 指标 | 目标值 | 说明 |
|------|--------|------|
| **HTTP 请求发送 TPS** | **≥ 10,000** | scp0006 向 target-service 发出请求的速率 |
| 错误率 | < 1% | `failCount / totalRequests` |

---

## 3. 压测方法

### A. 压测 API

scp0006 内置了压测接口，**绕过 Canal/Kafka**，直接测试 HTTP 请求发送能力：

```bash
# 快速测试（10秒）
curl -X POST "http://192.168.123.114:8082/api/stress/quick?concurrency=100"

# 完整测试（自定义并发数和持续时间）
curl -X POST "http://192.168.123.114:8082/api/stress/start?concurrency=200&duration=30"
```

**返回示例**：
```json
{
  "concurrency": 200,
  "durationMs": 10052,
  "totalRequests": 36404,
  "successCount": 36404,
  "failCount": 0,
  "tps": "3621.57",
  "errorRate": "0.00%"
}
```

### B. 测试不同并发数

```bash
# 测试多个并发级别，找出最佳配置
for c in 100 200 300 500; do
  echo "=== 并发数: $c ==="
  curl -s -X POST "http://192.168.123.114:8082/api/stress/start?concurrency=$c&duration=10"
  echo ""
  sleep 2
done
```

---

## 4. 重新部署

修改代码后，使用以下命令重新部署 scp0006：

```bash
# 只部署 scp0006（推荐，快速迭代）
./deploy-cd.sh scp0006

# 或部署所有内网服务
./deploy-cd.sh inner
```

**注意**：部署脚本通过远程 Docker Daemon 工作，无需 SSH 和 Maven。

---

## 5. 日志排查

```bash
# scp0006 日志
DOCKER_API_VERSION=1.44 docker -H tcp://192.168.123.114:2375 logs scp0006 --tail 200

# target-service 日志
DOCKER_API_VERSION=1.44 docker -H tcp://192.168.123.114:2375 logs target-service --tail 100
```

---

## 6. 约束

- **不能修改 target-service，不能绕过target-service**（包括延迟配置）
- **target-service 保持 50ms 延迟**（模拟真实场景）
- 结果记录到 `perf-test/binlog-optimization-iterations.md`
- **必须达到 TPS ≥ 10,000 才能结束任务**



