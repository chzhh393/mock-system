# 穿透网关抗慢接口优化任务

参考 README.md、OBJECTIVES.md 理解系统架构。

## 目标

下游接口慢（30s）时，系统不雪崩，能持续接入请求。

## 工具与环境

- 代码目录：`/home/ubuntu/mock-system/`
- 部署命令：`./deploy-registry.sh all`（自动构建、部署、验证）
- 状态查看：`./deploy-registry.sh status`
- 端到端测试：`./deploy-registry.sh test`
- 压测工具：`cd perf-test && ./run-test.sh`
- 查看日志：`./deploy-registry.sh logs <服务名>`
- 测试入口：`curl -X POST "http://192.168.123.66:8080/inner/c1/yhzx" -H "Content-Type: application/x-www-form-urlencoded" -d "code=yhzx&paramData={\"test\":\"hello\"}"`

## 【状态文件】/home/ubuntu/mock-system/state.json

```json
{
  "phase": 1,
  "baseline": {"tps": 0, "p99": 0, "error_rate": 0},
  "bottleneck": {"tps": 0, "p99": 0, "error_rate": 0},
  "current_round": 0,
  "retry": 0,
  "history": []
}
```

**每步操作前必须 cat 读取，操作后必须更新。**

## 【达标标准】

| 场景 | TPS | 平均延迟 | 最大延迟 | 错误率 |
|------|-----|----------|----------|--------|
| 基线（正常50ms，20并发） | > 10 | < 2s | < 3s | < 5% |
| 优化后（慢接口30s，20并发） | > 基线×50% | - | < 35s | < 90% |

> 基线参考：当前环境 20 并发 TPS=11，延迟=1.67s（详见 perf-test/test-result-2026-01-16.md）

## 【流程规则】

### phase=1: 环境就绪

- 执行 `./setup-base-env.sh verify` 验证基础环境
- 执行 `./deploy-registry.sh status` 检查服务状态（应有 4 个应用服务 + 基础服务运行中）
- 执行 `./deploy-registry.sh test` 验证端到端请求
- 【退出条件】测试返回 `code: 200` → phase=2
- 【失败处理】查看日志 `./deploy-registry.sh logs <服务名>` 排查问题

### phase=2: 基线测量

- 确保 target-service 延迟 = 50ms（默认值，正常场景）
- 执行压测：`cd perf-test && THREADS=2 CONNECTIONS=20 DURATION=60s ./run-test.sh`
- 记录 baseline: {tps, avg_latency, max_latency, error_rate}
- 【退出条件】TPS > 10 且 平均延迟 < 2s 且 错误率 < 5% → phase=3
- 【失败处理】系统本身有问题，排查后重试

### phase=3: 瓶颈复现

- 修改 target-service 延迟 = 30000ms（慢接口）：
  ```bash
  # 推荐：动态 API 修改（无需重新部署）
  curl -X POST "http://192.168.123.81:8083/api/stats/config?delayMs=30000"

  # 验证配置
  curl "http://192.168.123.81:8083/api/stats/config"

  # 恢复正常延迟
  curl -X POST "http://192.168.123.81:8083/api/stats/config?delayMs=50"
  ```
- 执行压测：`cd perf-test && THREADS=2 CONNECTIONS=20 DURATION=120s ./run-test.sh`
- 记录 bottleneck: {tps, avg_latency, max_latency, error_rate}
- 【退出条件】满足任一：TPS < 基线×20% 或 错误率 > 50% 或 最大延迟 > 60s → phase=4
- 【无需优化】系统本身抗压能力足够 → phase=5，输出报告

### phase=4: 优化循环 (PDCA)

**每轮操作流程**：

1. **Plan**: 分析当前瓶颈，选择优化方向
   - 方向选择：超时控制 / Semaphore限流 / 连接池隔离 / 背压控制
   - 【约束】禁止重复使用已失败的方案

2. **Do**: 修改代码 → 部署 `./deploy-registry.sh all`

3. **Check**: 压测验证（慢接口30s场景）
   - 记录 result: {tps, p99, error_rate, optimization_type}
   - 追加到 history[]

4. **Act**: 判定结果
   ```
   if TPS > baseline.tps × 50% AND 最大延迟 < 35s:
       达标 → phase=5
   else if retry < 3:
       retry++, 换方案回到 Plan
       【禁止进入 phase=5，必须继续优化或标记人工介入】
   else:
       标记"需人工介入"，输出当前最优结果 → phase=5
   ```

   > 示例：若基线 TPS=11，则优化后需 TPS > 5.5 且 最大延迟 < 35s

**【禁止把"性能提升"当达标，必须满足硬指标】**

### phase=5: 输出报告

- 生成 `reports/final-report.md`
- 包含：基线数据、瓶颈数据、每轮优化详情、最终对比
- 任务结束

## 【报告模板】

```markdown
# 穿透网关优化报告

## 1. 基线性能（正常场景）
- TPS: {baseline.tps}
- P99: {baseline.p99}
- 错误率: {baseline.error_rate}

## 2. 瓶颈场景（优化前）
- TPS: {bottleneck.tps}
- P99: {bottleneck.p99}
- 错误率: {bottleneck.error_rate}

## 3. 优化过程
| 轮次 | 方案 | TPS | P99 | 错误率 | 是否达标 |
|------|------|-----|-----|--------|----------|
| 1    | xxx  | xxx | xxx | xxx    | ❌/✅    |

## 4. 最终结果
- 达标状态: ✅达标 / ⚠️需人工介入
- TPS 提升: {计算}
- P99 改善: {计算}
```

## 【注意事项】

1. **部署方式**：`./deploy-registry.sh all` 会自动构建、推送、部署、连接网络、运行测试
2. **前提条件**（环境已预配置）：基础服务（MySQL、Kafka、Canal、Redis）已运行
3. **部署耗时**：首次构建约 2-3 分钟，后续增量构建更快
4. **严格按 state.json 的 phase 执行，禁止跳过阶段**
5. **可用服务名**（用于 logs 命令）：scp0005, outer-consumer, scp0006, target-service, canal-outer, canal-inner
