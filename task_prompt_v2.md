# 穿透网关高吞吐量优化任务

参考 README.md 理解系统架构。

## 目标

将穿透网关吞吐量从 **60 TPS** 提升至 **600+ TPS**（至少 10 倍提升）

## 【核心约束 (CRITICAL)】

1. **数据完整性**：HTTP 200 响应必须包含下游的真实业务数据，禁止硬编码或返回空结果。
2. **允许快速失败**：允许通过熔断、限流、超时等手段快速拒绝过载请求（返回非200）。
3. **禁止修改业务流程**：仅限技术调优，不改变数据流向。

## 工具与环境

- 代码目录：`/home/ubuntu/mock-system/`
- 部署命令：`./deploy-registry.sh all`（自动构建、部署、验证）
- 状态查看：`./deploy-registry.sh status`
- 压测工具：`cd perf-test && ./run-test.sh`
- 查看日志：`./deploy-registry.sh logs <服务名>`
- 可用服务名：scp0005, outer-consumer, scp0006, target-service

---

## 一、当前性能基线

| 场景 | TPS | 平均延迟 | 错误率 |
|------|-----|----------|--------|
| 50ms延迟，20并发 | 60 | 315ms | 0% |

设置基线延迟：
```bash
curl -X POST "http://192.168.123.81:8083/api/stats/config?delayMs=50"
```

---

## 二、系统架构

### 2.1 数据流

```
客户端请求
    ↓
[SCP0005] ── 写入 ──→ [内网MySQL] ── CDC ──→ [Kafka] ── 消费 ──→ [SCP0006]
    ↑                                                              ↓
    │                                                         调用目标服务
    │                                                              ↓
[轮询等待] ←── Redis ←── [outer-consumer] ←── CDC ←── [外网MySQL] ←─┘
```

### 2.2 各组件技术栈

| 组件 | 框架 | 当前模式 |
|------|------|----------|
| scp0005 | Spring WebFlux (Netty) | 轮询等待 Redis 结果 |
| scp0006 | Spring MVC | 异步线程池处理 |
| outer-consumer | Spring MVC | 同步处理 Kafka 消息 |

### 2.3 关键配置

**scp0005 (外网网关)**：
- R2DBC pool.max-size: 20
- Redis pool.max-active: 20
- poll-timeout-ms: 30000（轮询超时30秒）
- poll-interval-ms: 100（轮询间隔100ms）

**scp0006 (内网穿透服务)**：
- Kafka concurrency: 10
- HikariCP max-pool-size: 20
- 线程池: 20核心/50最大/200队列
- request-timeout-ms: 5000

**outer-consumer (响应消费服务)**：
- Kafka concurrency: 10
- Redis pool.max-active: 20

---

## 三、性能瓶颈分析

### 3.1 核心瓶颈：scp0005 的轮询等待模式

```java
// 当前 scp0005 的轮询逻辑 (GatewayService.java)
private Mono<String> pollRedisResult(String requestId) {
    return Mono.defer(() -> redisTemplate.opsForValue().get(redisKey))
            .repeatWhenEmpty(repeat -> repeat
                    .delayElements(Duration.ofMillis(100))  // 每100ms轮询一次
                    .take(300))                              // 最多轮询300次
            .timeout(Duration.ofMillis(30000));
}
```

**问题**：
- 虽然使用了 WebFlux，但每个请求仍需**持续占用连接等待结果**
- 轮询期间无法释放资源处理新请求
- 连接利用率极低（响应时间 300ms，但连接被占用整个等待期）

### 3.2 理论分析

| 当前模式 | 连接占用时间 | 单连接 QPS | 20连接 QPS |
|----------|-------------|-----------|------------|
| 轮询等待 | ~300ms | 3.3 | ~66 |
| 理想异步 | ~1ms | 1000 | ~20000 |

### 3.3 优化方向提示

参考 **Spring Cloud Gateway (Netty + WebFlux)** 的设计理念：
- 完全抛弃同步等待模式
- 利用 Mono/Flux 响应式编程模型，实现全链路异步
- 请求进来后，Netty EventLoop 线程处理路由，不等待响应，直接处理下一个事件

**可能的技术方案**（仅供参考，需自行探索验证）：
- Redis Pub/Sub 订阅推送
- Redis Keyspace Notifications
- WebSocket/SSE 长连接
- 其他异步通知机制

---

## 四、达标标准

| 指标 | 目标值 | 验证方法 |
|------|--------|----------|
| TPS (100并发) | ≥ 600 | wrk 压测 |
| 平均延迟 | ≤ 500ms | wrk 统计 |
| 错误率 | < 1% | wrk 统计 |
| 系统稳定性 | 无 OOM/崩溃 | 2分钟持续压测 |

---

## 五、优化循环 (PDCA)

**每轮操作流程**：

### 1. Plan - 分析瓶颈，制定方案

分析当前系统瓶颈，自行设计优化方案。

**约束**：禁止重复使用已失败的方案。

### 2. Do - 修改代码并部署

```bash
# 修改代码后，一键部署
./deploy-registry.sh all
```

### 3. Check - 压测验证

```bash
# 基础压测
cd perf-test && THREADS=2 CONNECTIONS=20 DURATION=60s ./run-test.sh

# 高并发压测（达标验证）
cd perf-test && THREADS=4 CONNECTIONS=100 DURATION=60s ./run-test.sh
```

记录结果：TPS、平均延迟、最大延迟、错误率

### 4. Act - 判定结果

判定：
- ✅ TPS ≥ 600 且错误率 < 1% → 生成报告，任务结束
- ❌ 未达标 → 分析原因，换方案，回到 Plan
- ⚠️ 5轮仍未达标 → 标记"需人工介入"，输出当前最优结果

---

## 六、输出报告

任务完成后，生成 `reports/high-throughput-report.md`：

```markdown
# 穿透网关高吞吐量优化报告

## 基线性能
- TPS: 60 | 延迟: 315ms | 错误率: 0%

## 优化过程
| 轮次 | 方案 | TPS | 延迟 | 错误率 | 达标 |
|------|------|-----|------|--------|------|
| 1    | xxx  | xxx | xxx  | xxx    | ❌/✅ |

## 最终结果
- 达标状态: ✅达标 / ⚠️需人工介入
- 关键改进: xxx
- TPS 提升: 60 → xxx (Nx)
```

---

## 注意事项

1. `./deploy-registry.sh all` 会自动构建、推送、部署、验证
2. 基础服务（MySQL、Kafka、Canal、Redis）已预先运行
3. 首次构建约 2-3 分钟，增量构建更快
4. 高并发压测时注意观察系统资源使用情况
5. 修改代码前先理解现有架构（参考 README.md）
