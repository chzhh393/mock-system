# 内网关下游调用 RPS 优化任务

参考 README.md 理解系统架构。

## 目标

提升内网关（scp0006）的**下游调用 RPS**，从当前基线提升至 **1500+ RPS**。

---

## 一、当前基线 (2026-01-20)

| 测试场景 | 服务延迟 | 下游 RPS | 说明 |
|----------|---------|----------|------|
| 混合服务 | 平均 ~100ms | **~390** | 真实场景基线 |
| 纯 fast 服务 | 10-30ms | **~678** | 单一快速服务 |

**测试条件**: wrk -t4 -c500 -d60s

**瓶颈**: 增加并发数（500→5000）无法提升 RPS，瓶颈在 scp0006 内部。

---

## 二、指标定义

### 2.1 什么是下游调用 RPS

```
下游调用 RPS = 内网关 scp0006 每秒向 target-service 发出的请求数量
```

### 2.2 在数据流中的位置

```
客户端请求
    ↓
[SCP0005] ── 写入 ──→ [内网MySQL] ── CDC ──→ [Kafka]
                                              ↓
                                         [SCP0006]
                                              ↓
                                    ┌─────────────────┐
                                    │  下游调用 RPS   │ ← 本任务优化目标
                                    │  每秒发出多少   │
                                    │  请求到 target  │
                                    └────────┬────────┘
                                              ↓
                                       [target-service]
                                              ↓
                                        响应写回...
```

### 2.3 指标意义

| 作用 | 说明 |
|------|------|
| **衡量穿透能力** | 请求从外网真正到达内网并执行的效率 |
| **衡量内网关处理能力** | scp0006 消费 Kafka 后能多快调用下游 |
| **瓶颈定位** | 如果下游 RPS < 外网关接收 RPS，说明穿透链路有瓶颈 |
| **与端到端 TPS 的关系** | 理论上：下游 RPS ≥ 端到端 TPS |

### 2.4 如何测量

**方法1：在 target-service 统计**
```bash
# 查看 target-service 统计接口
curl http://192.168.123.81:8083/api/stats

# 实际返回格式：
{
  "code": "200",
  "data": {
    "totalRequests": 36000,
    "successRequests": 35000,
    "errorRequests": 1000,
    "successRate": "97.22%",
    "codeStats": { "fast": 10000, "slow": 5000, ... }
  }
}
# 注：需要自行计算 RPS = totalRequests / 测试时长
```

**方法2：查看 scp0006 日志**
```bash
./deploy-registry.sh logs scp0006 | grep "Invoking target"
```

**方法3：通过端到端 TPS 推算**
- 在稳定状态下，下游调用 RPS ≈ 端到端 TPS
- 如果有请求积压，下游调用 RPS > 端到端 TPS

---

## 三、验证方法

```bash
# 安装依赖
pip3 install aiohttp

# 运行压测（并发500，持续60秒）
cd perf-test && python3 load_test.py 500 60 http://192.168.123.66:8080
```

脚本会自动：重置统计 → 运行压测 → 输出下游调用 RPS

---

## 四、达标标准

| 指标 | 目标值 | 验证方法 |
|------|--------|----------|
| 下游调用 RPS | ≥ 1500 | target-service 统计接口 |
| 端到端 TPS | ≥ 1000 | wrk 压测 |
| 错误率 | < 1% | wrk 统计 |
| 系统稳定性 | 无 OOM/崩溃 | 2分钟持续压测 |

---

## 五、工具与环境

- 代码目录：`/home/ubuntu/mock-system/`
- 部署命令：`./deploy-registry.sh all`
- 状态查看：`./deploy-registry.sh status`
- 压测工具：`cd perf-test && ./run-test.sh`
- 查看日志：`./deploy-registry.sh logs scp0006`
- target 统计：`curl http://192.168.123.81:8083/api/stats`



---

## 六、优化循环 (PDCA)

### 1. Plan - 分析瓶颈
- 查看当前下游 RPS：`curl http://192.168.123.81:8083/api/stats`
- 分析 scp0006 配置和代码

### 2. Do - 修改并部署
```bash
./deploy-registry.sh all
```

### 3. Check - 验证效果
```bash
# 先清空统计
curl -X POST "http://192.168.123.81:8083/api/stats/reset"

# 运行压测
cd perf-test && THREADS=4 CONNECTIONS=100 DURATION=60s ./run-test.sh

# 查看下游 RPS
curl http://192.168.123.81:8083/api/stats
```

### 4. Act - 判定结果
- ✅ 下游 RPS ≥ 1500 → 任务完成
- ❌ 未达标 → 分析原因，换方案

### 5. 记录迭代结果

**重要**: 每轮优化后，将结果追加到 `perf-test/optimization-iterations.md`：

```markdown
## 迭代 N: [优化标题]

**日期**: YYYY-MM-DD

**优化内容**:
- 修改了什么配置/代码
- 修改的文件和具体改动

**测试结果**:
| 指标 | 优化前 | 优化后 | 提升 |
|------|--------|--------|------|
| 混合服务 RPS | xxx | xxx | +xx% |
| 纯 fast RPS | xxx | xxx | +xx% |
| 错误率 | x% | x% | - |

**结论**: 是否达标，下一步方向
```

---

## 七、关键文件

| 文件 | 说明 |
|------|------|
| `inner-server/scp0006/src/main/resources/application.yml` | 配置文件 |
| `inner-server/scp0006/src/main/java/com/mock/scp0006/service/TargetServiceClient.java` | 调用下游服务 |
| `inner-server/scp0006/src/main/java/com/mock/scp0006/consumer/RequestBinlogConsumer.java` | Kafka 消费者 |
| `inner-server/scp0006/src/main/java/com/mock/scp0006/config/ThreadPoolConfig.java` | 线程池配置 |
| `perf-test/load_test.py` | Python 压测脚本（asyncio + aiohttp） |
| `perf-test/optimization-iterations.md` | 优化迭代记录 |

---

## 八、注意事项

1. 增加并发度时注意资源限制（CPU、内存、连接池）
2. 异步化改造需要同时修改调用方和错误处理逻辑
3. target-service 也有处理能力上限，需同步关注
4. 下游 RPS 提升后，需确保响应回传链路不成为新瓶颈
