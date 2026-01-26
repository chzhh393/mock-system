# 任务阶段 3：端到端高并发性能优化

## 1. 背景
在完成第一阶段（外网网关写入优化）和第二阶段（内网网关发送优化）的基础上，我们现在的目标是将这些优化集成到完整的端到端流程中。

**前期成果：**
- **第一阶段 (scp0005)**：通过异步批量写入（Async Batching）实现了约 11,000 TPS 的数据库写入性能。
- **第二阶段 (scp0006)**：通过 WebClient/异步发送实现了约 35,000 TPS 的 HTTP 发送性能。

## 2. 目标
**目标指标：**
- **端到端 TPS ≥ 10,000**
- 测量范围：从 `scp0005` 接收请求 -> `scp0006` 将请求发送至 `target-service`。

**约束条件：**
- `target-service` 的延迟保持在 **50ms**。
- 必须使用完整链路：`scp0005` -> `MySQL` -> `Canal` -> `Kafka` -> `scp0006` -> `target-service`。

## 3. 实施计划

### 3.1 优化 scp0005 (外网网关)
- **模式**：火后即忘（Fire-and-Forget）+ 异步批量插入。
- **行动项**：
  - 实现 `BatchDbService`，在内存队列中缓冲请求。
  - 使用后台线程池将请求批量插入到 MySQL 的 `inner_request` 表中。
  - 修改 `GatewayService`，将请求推送到队列并立即返回成功（HTTP 200）。
  - 在本次测试中移除同步的 Redis 轮询（因为我们的重点是前向吞吐量）。

### 3.2 优化 scp0006 (内网网关)
- **模式**：异步非阻塞 HTTP 客户端。
- **行动项**：
  - 使用 `WebClient` (Reactor Netty) 替换 `RestTemplate`。
  - 配置高性能连接 pool（5000+ 连接）。
  - 更新 `RequestBinlogConsumer` 以异步处理 Kafka 消息。
  - 确保消费速度匹配发送能力。

## 4. 验证与测试
### 4.1 部署
```bash
./deploy-cd.sh inner  # 部署 scp0006, target-service
./deploy-cd.sh outer  # 部署 scp0005, outer-consumer
```
**注意**：部署脚本通过远程 Docker Daemon 工作，无需 SSH 和 Maven。

### 4.2 压测
由于沙箱环境可能没有 `wrk` 工具，请根据以下接口信息编写自定义脚本（如 Python, Go 或其他压测工具）进行测试。

**接口信息：**
- **URL**: `http://192.168.123.113:8080/inner/c1/yhzx`
- **Method**: `POST`
- **Content-Type**: `application/x-www-form-urlencoded`
- **Payload 示例**: `code=yhzx&paramData={"test":"e2e-test"}`


### 4.3 验收标准
- 客户端 (wrk)：TPS > 10,000（表明 scp0005 接收速度足够快）。
- 内网端 (日志/指标)：`scp0006` 的日志输出显示发送速率 > 10,000 TPS。
- **说明**：由于 `target-service` 是一个 Mock 服务，我们依靠 `scp0006` 的日志或 `target-service` 的点击数来验证流量到达情况。

## 5. 执行步骤
1. 在 `scp0005` 中实现 `BatchDbService`。
2. 重构 `scp0005` 中的 `GatewayService`。
3. 在 `scp0006` 中配置 `WebClient`。
4. 重构 `scp0006` 中的 `TargetServiceClient` 和 `RequestBinlogConsumer`。
5. 部署所有服务。
6. 运行压力测试并分析日志。
