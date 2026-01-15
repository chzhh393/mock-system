# 内外网穿透网关性能优化方案

> 基于 2026-01-14 压测报告分析，制定 5 个优化方向，目标提升 5 倍性能

## 一、当前性能状况

### 1.1 性能指标

| 指标 | 当前值 | 目标值 |
|------|--------|--------|
| 最大 TPS | ~12 req/s | 60+ req/s |
| 低负载延迟 | 400-500ms | <200ms |
| 高负载延迟 | 1.6s+ | <500ms |
| 错误率(50并发) | 95% | <5% |

### 1.2 关键发现

- **TPS 天花板现象**：无论并发数从 10 增加到 200，TPS 始终被限制在 ~12
- **延迟线性增长**：5并发 434ms → 10并发 859ms → 20并发 1620ms
- **高并发崩溃**：并发超过 50 后错误率急剧上升

### 1.3 瓶颈定位

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           数据流转全链路                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  客户端 ──→ scp0005 ──→ MySQL(B) ──→ Canal ──→ Kafka ──→ scp0006           │
│                           │                              │                  │
│                           │        【瓶颈1】              │   【瓶颈2】       │
│                           │   Canal 批处理配置过小        │  消费并发=3      │
│                           │   Kafka 生产者配置保守        │  同步阻塞处理    │
│                           │                              ↓                  │
│                                                    target-service           │
│                                                          │                  │
│                                                          │   【瓶颈3】       │
│                                                          │  HTTP 无连接池   │
│                                                          ↓                  │
│  客户端 ←── scp0005 ←── Redis ←── outer-consumer ←── Kafka ←── Canal       │
│                 │                      │                                    │
│           【瓶颈4】               【瓶颈5】                                   │
│         轮询间隔100ms           数据库连接池=20                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 二、优化方向总览

| 优先级 | 优化方向 | 预期提升 | 复杂度 | 风险 |
|--------|----------|----------|--------|------|
| 1 | Kafka 消费者并发度 | **3-4倍** | 低（配置） | 低 |
| 2 | Canal/Kafka 生产者配置 | 30-50% | 低（配置） | 低 |
| 3 | 数据库 I/O 性能优化 | 20-40% | 中（配置+代码） | 低 |
| 4 | HTTP 连接池 + Redis Pub/Sub 异步响应 | **30-50%** | 中（代码） | 中 |
| 5 | Redis 集群性能优化 | 15-25% | 中（代码） | 低 |

---

## 三、优化方向 1：提升 Kafka 消费者并发度

### 3.1 问题分析

**根本原因**：消费者并发数 `concurrency=3` 严重限制了系统吞吐量

```
当前配置：
- scp0006: concurrency = 3
- outer-consumer: concurrency = 3

计算分析：
- 每条消息处理耗时 ≈ 250ms（目标服务 60ms + 数据库写入 100ms + 网络延迟 90ms）
- 理论最大 TPS = 3 线程 × (1000ms / 250ms) = 12 TPS
- 与实际观测值完全吻合！
```

### 3.2 优化方案

**目标**：将 TPS 从 ~12 提升到 ~48（4倍）

#### 修改文件 1：scp0006 Kafka 消费者配置
`/inner-server/scp0006/src/main/resources/application.yml`

**当前配置**：
```yaml
spring:
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP:192.168.123.66:9092}
    consumer:
      group-id: scp0006-consumer-group
      auto-offset-reset: earliest
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      enable-auto-commit: false
    listener:
      ack-mode: manual_immediate
      concurrency: 3    # ← 当前值：3
```

**修改后配置**：
```yaml
spring:
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP:192.168.123.66:9092}
    consumer:
      group-id: scp0006-consumer-group
      auto-offset-reset: earliest
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      enable-auto-commit: false
      max-poll-records: 50      # ← 新增：每次拉取更多记录
      fetch-min-size: 1024      # ← 新增：1KB，减少网络往返
      fetch-max-wait: 500       # ← 新增：最多等待500ms
    listener:
      ack-mode: manual_immediate
      concurrency: 15           # ← 修改：从 3 提升到 15
```

#### 修改文件 2：outer-consumer Kafka 消费者配置
`/outer-server/outer-consumer/src/main/resources/application.yml`

**当前配置**：
```yaml
spring:
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP:kafka:9092}
    consumer:
      group-id: outer-consumer-group
      auto-offset-reset: earliest
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      enable-auto-commit: false
    listener:
      ack-mode: manual_immediate
      concurrency: 3    # ← 当前值：3
```

**修改后配置**：
```yaml
spring:
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP:kafka:9092}
    consumer:
      group-id: outer-consumer-group
      auto-offset-reset: earliest
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      enable-auto-commit: false
      max-poll-records: 50      # ← 新增
      fetch-min-size: 1024      # ← 新增
      fetch-max-wait: 500       # ← 新增
    listener:
      ack-mode: manual_immediate
      concurrency: 15           # ← 修改：从 3 提升到 15
```

#### 变更摘要

| 配置项 | 当前值 | 修改后 | 说明 |
|--------|--------|--------|------|
| `listener.concurrency` | 3 | **15** | 消费者线程数，直接影响 TPS 上限 |
| `consumer.max-poll-records` | (默认500) | 50 | 每次 poll 拉取的最大记录数 |
| `consumer.fetch-min-size` | (默认1B) | 1024 | 最小拉取字节数，减少网络往返 |
| `consumer.fetch-max-wait` | (默认500ms) | 500 | 等待 fetch-min-size 的最大时间 |

### 3.3 前置条件

**重要**：Kafka 消费者线程数不能超过 Topic 分区数，需要先增加分区：

```bash
# 检查当前分区数
docker exec kafka-inner kafka-topics.sh --describe --topic inner_request_binlog --bootstrap-server localhost:9092
docker exec kafka-outer kafka-topics.sh --describe --topic outer_response_binlog --bootstrap-server localhost:9092

# 增加分区到 15
docker exec kafka-inner kafka-topics.sh --alter --topic inner_request_binlog --partitions 15 --bootstrap-server localhost:9092
docker exec kafka-outer kafka-topics.sh --alter --topic outer_response_binlog --partitions 15 --bootstrap-server localhost:9092
```

### 3.4 验证方法

```bash
# 压测验证
wrk -t4 -c50 -d30s -s post.lua http://192.168.123.66:8080/inner/c1/yhzx

# 期望结果：
# - TPS 从 ~12 提升到 ~48
# - 错误率从 95% 下降到 <20%
```

---

## 四、优化方向 2：优化 Canal/Kafka 生产者配置

### 4.1 问题分析

**根本原因**：Canal 配置过于保守，导致 CDC 延迟高

```
当前配置问题：
├── kafka.linger.ms = 1           → 消息无法积累批次，每条单独发送
├── kafka.batch.size = 16384      → 16KB 太小，网络利用率低
├── kafka.acks = all              → 等待所有副本确认，延迟高
├── kafka.max.in.flight... = 1    → 串行发送，吞吐量受限
└── canal.mq.canalBatchSize = 50  → 批次太小，频繁提交
```

### 4.2 优化方案

**目标**：将 CDC 延迟从 100-200ms 降低到 20-50ms

#### 修改文件 1：内网 Canal 配置
`/inner-server/config/canal/canal.properties`

**当前配置（MQ 部分）**：
```properties
canal.mq.flatMessage = true
canal.mq.canalBatchSize = 50       # ← 当前值：50
canal.mq.canalGetTimeout = 100     # ← 当前值：100ms
canal.mq.send.thread.size = 30
canal.mq.build.thread.size = 8
```

**当前配置（Kafka 部分）**：
```properties
kafka.bootstrap.servers = kafka:9092
kafka.acks = all                   # ← 当前值：all（最严格）
kafka.compression.type = none      # ← 当前值：无压缩
kafka.batch.size = 16384           # ← 当前值：16KB
kafka.linger.ms = 1                # ← 当前值：1ms（几乎无批处理）
kafka.max.request.size = 1048576
kafka.buffer.memory = 33554432     # ← 当前值：32MB
kafka.max.in.flight.requests.per.connection = 1  # ← 当前值：1（串行）
kafka.retries = 0                  # ← 当前值：0（不重试）
```

**修改后配置（MQ 部分）**：
```properties
canal.mq.flatMessage = true
canal.mq.canalBatchSize = 200      # ← 修改：从 50 提升到 200
canal.mq.canalGetTimeout = 50      # ← 修改：从 100 降低到 50ms
canal.mq.send.thread.size = 30
canal.mq.build.thread.size = 8
```

**修改后配置（Kafka 部分）**：
```properties
kafka.bootstrap.servers = kafka:9092
kafka.acks = 1                     # ← 修改：从 all 改为 1（只等待 leader）
kafka.compression.type = lz4       # ← 修改：启用 LZ4 压缩
kafka.batch.size = 65536           # ← 修改：从 16KB 提升到 64KB
kafka.linger.ms = 10               # ← 修改：从 1ms 提升到 10ms
kafka.max.request.size = 1048576
kafka.buffer.memory = 67108864     # ← 修改：从 32MB 提升到 64MB
kafka.max.in.flight.requests.per.connection = 5  # ← 修改：从 1 提升到 5
kafka.retries = 3                  # ← 修改：从 0 提升到 3
```

#### 修改文件 2：外网 Canal 配置
`/outer-server/config/canal/canal.properties`

应用与 inner-server 相同的修改。

#### 变更摘要

| 配置项 | 当前值 | 修改后 | 说明 |
|--------|--------|--------|------|
| `canal.mq.canalBatchSize` | 50 | **200** | 增大批处理大小，减少提交次数 |
| `canal.mq.canalGetTimeout` | 100ms | **50ms** | 减少等待时间，提高响应速度 |
| `kafka.acks` | all | **1** | 只等待 leader 确认，延迟降低 50%+ |
| `kafka.batch.size` | 16KB | **64KB** | 更大批次，更高网络效率 |
| `kafka.linger.ms` | 1ms | **10ms** | 等待更多消息积累成批次 |
| `kafka.compression.type` | none | **lz4** | 压缩减少 40-60% 网络流量 |
| `kafka.max.in.flight...` | 1 | **5** | 允许多个请求并发发送 |
| `kafka.retries` | 0 | **3** | 失败自动重试，提高可靠性 |

### 4.3 配置说明

| 配置项 | 原值 | 新值 | 说明 |
|--------|------|------|------|
| `kafka.acks` | all | 1 | 牺牲少量可靠性换取延迟降低 |
| `kafka.batch.size` | 16KB | 64KB | 更大的批次，更少的网络往返 |
| `kafka.linger.ms` | 1ms | 10ms | 等待更多消息积累成批次 |
| `kafka.max.in.flight...` | 1 | 5 | 允许多个请求并发发送 |
| `kafka.compression.type` | none | lz4 | 压缩减少 40-60% 网络流量 |

### 4.4 验证方法

观察日志中的 CDC 延迟指标：
```
CDC延迟(内网): 之前 100-200ms → 之后 20-50ms
CDC延迟(外网): 之前 100-200ms → 之后 20-50ms
```

---

## 五、优化方向 3：数据库 I/O 性能优化

### 5.1 问题分析

**根本原因**：
- 两次跨网络数据库操作（内网请求表、外网响应表）增加延迟
- 数据库连接池配置不合理（max=20 在高并发下不足）
- MySQL binlog 配置过于保守

### 5.2 优化方案

**目标**：数据库 I/O 延迟减少 40-50%

#### 5.2.1 MySQL 服务端优化

修改 `/inner-server/docker-compose.yml` 和 `/outer-server/docker-compose.yml`：

```yaml
mysql:
  command: >
    --server-id=1
    --log-bin=mysql-bin
    --binlog-format=ROW
    --binlog-row-image=MINIMAL          # 减少 binlog 大小
    --innodb_flush_log_at_trx_commit=2  # 平衡性能和一致性
    --sync_binlog=0                     # 提升 binlog 性能
    --max_connections=500               # 增加最大连接数
    --innodb_buffer_pool_size=512M      # 优化缓冲池
```

#### 5.2.2 应用层连接池优化

**修改文件 1：scp0005 R2DBC 连接池**
`/outer-server/scp0005/src/main/resources/application.yml`

**当前配置**：
```yaml
spring:
  r2dbc:
    url: r2dbc:mysql://${INNER_DB_HOST:192.168.123.65}:${INNER_DB_PORT:3306}/${INNER_DB_NAME:inner_gateway}?sslMode=DISABLED
    username: ${INNER_DB_USER:root}
    password: ${INNER_DB_PASSWORD:root123}
    pool:
      initial-size: 5        # ← 当前值：5
      max-size: 20           # ← 当前值：20
      max-idle-time: 30m
```

**修改后配置**：
```yaml
spring:
  r2dbc:
    url: r2dbc:mysql://${INNER_DB_HOST:192.168.123.65}:${INNER_DB_PORT:3306}/${INNER_DB_NAME:inner_gateway}?sslMode=DISABLED
    username: ${INNER_DB_USER:root}
    password: ${INNER_DB_PASSWORD:root123}
    pool:
      initial-size: 10         # ← 修改：从 5 提升到 10
      max-size: 50             # ← 修改：从 20 提升到 50
      max-idle-time: 30m
      max-acquire-time: 10s    # ← 新增：获取连接超时
      validation-query: SELECT 1  # ← 新增：连接验证
```

**修改文件 2：scp0006 HikariCP 连接池**
`/inner-server/scp0006/src/main/resources/application.yml`

**当前配置**：
```yaml
spring:
  datasource:
    url: jdbc:mysql://${OUTER_DB_HOST:192.168.123.66}:${OUTER_DB_PORT:3306}/${OUTER_DB_NAME:outer_gateway}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai
    username: ${OUTER_DB_USER:root}
    password: ${OUTER_DB_PASSWORD:root123}
    driver-class-name: com.mysql.cj.jdbc.Driver
    hikari:
      maximum-pool-size: 20    # ← 当前值：20
      minimum-idle: 5          # ← 当前值：5
      connection-timeout: 30000  # ← 当前值：30秒
      idle-timeout: 600000     # ← 当前值：10分钟
      max-lifetime: 1800000    # ← 当前值：30分钟
```

**修改后配置**：
```yaml
spring:
  datasource:
    url: jdbc:mysql://${OUTER_DB_HOST:192.168.123.66}:${OUTER_DB_PORT:3306}/${OUTER_DB_NAME:outer_gateway}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai
    username: ${OUTER_DB_USER:root}
    password: ${OUTER_DB_PASSWORD:root123}
    driver-class-name: com.mysql.cj.jdbc.Driver
    hikari:
      maximum-pool-size: 50    # ← 修改：从 20 提升到 50
      minimum-idle: 10         # ← 修改：从 5 提升到 10
      connection-timeout: 10000  # ← 修改：从 30秒 降低到 10秒
      idle-timeout: 300000     # ← 修改：从 10分钟 降低到 5分钟
      max-lifetime: 1200000    # ← 修改：从 30分钟 降低到 20分钟
      leak-detection-threshold: 60000  # ← 新增：连接泄漏检测
      validation-timeout: 5000         # ← 新增：连接验证超时
```

#### 变更摘要（数据库连接池）

| 服务 | 配置项 | 当前值 | 修改后 | 说明 |
|------|--------|--------|--------|------|
| scp0005 | `pool.initial-size` | 5 | **10** | 初始连接数翻倍 |
| scp0005 | `pool.max-size` | 20 | **50** | 最大连接数提升 2.5 倍 |
| scp0006 | `maximum-pool-size` | 20 | **50** | 最大连接数提升 2.5 倍 |
| scp0006 | `minimum-idle` | 5 | **10** | 最小空闲连接翻倍 |
| scp0006 | `connection-timeout` | 30s | **10s** | 快速失败 |
| scp0006 | `idle-timeout` | 10min | **5min** | 更快释放空闲连接 |

#### 5.2.3 数据库索引优化

确保关键字段有索引（已在 init.sql 中配置）：

```sql
-- 为关键字段添加索引
CREATE INDEX idx_request_id ON inner_request(request_id);
CREATE INDEX idx_status ON inner_request(status);
CREATE INDEX idx_create_time ON inner_request(create_time);

CREATE INDEX idx_request_id ON outer_response(request_id);
CREATE INDEX idx_create_time ON outer_response(create_time);
```

### 5.3 连接池参数说明

| 参数 | 原值 | 新值 | 说明 |
|------|------|------|------|
| max-size / maximum-pool-size | 20 | 50 | 支持更高并发 |
| minimum-idle | 5 | 10 | 保持更多空闲连接 |
| connection-timeout | 30s | 10s | 快速失败 |
| idle-timeout | 10min | 5min | 更快释放空闲连接 |

### 5.4 验证方法

```bash
# HikariCP 监控（通过 Actuator）
curl http://localhost:8082/actuator/metrics/hikaricp.connections.active
curl http://localhost:8082/actuator/metrics/hikaricp.connections.pending

# 期望：
# - active connections < 50
# - pending connections = 0
```

---

## 六、优化方向 4：HTTP 连接池 + Redis Pub/Sub 异步响应

### 6.1 HTTP 连接池优化

#### 6.1.1 问题分析

**根本原因**：scp0006 调用 target-service 使用 SimpleClientHttpRequestFactory，无连接池

```java
// 当前实现 - 每次请求创建新连接
SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
factory.setConnectTimeout(30000);
factory.setReadTimeout(30000);
```

**问题**：
- 每次 HTTP 请求都进行 TCP 三次握手
- 请求完成后连接立即关闭
- 高并发下连接建立开销占总延迟 20-30%

#### 6.1.2 优化方案

**目标**：减少 HTTP 调用延迟 20-30%

修改 `/inner-server/scp0006/pom.xml`：

```xml
<dependencies>
    <!-- 现有依赖... -->

    <!-- 新增：Apache HttpClient 连接池 -->
    <dependency>
        <groupId>org.apache.httpcomponents.client5</groupId>
        <artifactId>httpclient5</artifactId>
        <version>5.2.1</version>
    </dependency>
</dependencies>
```

修改 `/inner-server/scp0006/src/main/java/com/mock/scp0006/config/RestTemplateConfig.java`：

```java
package com.mock.scp0006.config;

import org.apache.hc.client5.http.classic.HttpClient;
import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager;
import org.apache.hc.core5.util.TimeValue;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

@Configuration
public class RestTemplateConfig {

    @Bean
    public RestTemplate restTemplate(GatewayConfig gatewayConfig) {
        // 创建连接池管理器
        PoolingHttpClientConnectionManager connectionManager =
            new PoolingHttpClientConnectionManager();
        connectionManager.setMaxTotal(100);           // 最大连接数
        connectionManager.setDefaultMaxPerRoute(50);  // 每个路由最大连接数

        // 创建 HttpClient
        HttpClient httpClient = HttpClients.custom()
                .setConnectionManager(connectionManager)
                .evictIdleConnections(TimeValue.ofSeconds(30))  // 清理空闲连接
                .build();

        // 创建请求工厂
        HttpComponentsClientHttpRequestFactory factory =
            new HttpComponentsClientHttpRequestFactory(httpClient);
        factory.setConnectTimeout((int) gatewayConfig.getRequestTimeoutMs());
        factory.setConnectionRequestTimeout(5000);  // 从池获取连接超时

        return new RestTemplate(factory);
    }
}
```

### 6.2 WebFlux Sinks + HTTP 回调（替代轮询）

#### 6.2.1 问题分析

**根本原因**：轮询模式本身就是低效的

```
当前流程（轮询模式）：
scp0005 发起请求 → 写入数据库 → 开始轮询 Redis → 每 100ms 查询一次 → 获取结果

问题：
├── 轮询产生大量无效请求（结果未就绪时的查询都是浪费）
├── 100 TPS 时产生 ~30,000 次/秒 Redis GET 请求
├── 响应延迟受轮询间隔限制（最少等待一个间隔周期）
└── 高并发时 Redis 成为瓶颈
```

#### 6.2.2 优化方案

**目标**：使用 Reactor Sinks + HTTP 回调实现事件驱动的异步响应，彻底消除轮询

```
优化后流程（Sinks + HTTP 回调模式）：

┌─────────────────────────────────────────────────────────────────────────┐
│  scp0005 (WebFlux)                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ 1. 创建 Sinks.One<String>                                        │   │
│  │ 2. 存入 ConcurrentHashMap<requestId, Sink>                       │   │
│  │ 3. 写入数据库                                                     │   │
│  │ 4. return sink.asMono().timeout(30s)  ← 非阻塞等待               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              ↑                                          │
│                              │ HTTP POST /internal/callback/{requestId} │
│                              │ body: responseData                       │
└──────────────────────────────┼──────────────────────────────────────────┘
                               │
┌──────────────────────────────┼──────────────────────────────────────────┐
│  outer-consumer              │                                          │
│  ┌───────────────────────────┴─────────────────────────────────────┐   │
│  │ 处理完成后 → HTTP 调用 scp0005 的回调接口                         │   │
│  │ POST http://scp0005:8080/internal/callback/{requestId}           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘

优势：
├── 零轮询：完全事件驱动
├── 零 Redis 中间层：直接 HTTP 回调
├── 纯内存操作：延迟 <5ms
├── 完美契合现有 WebFlux 架构
└── 实现简单，改动最小
```

#### 6.2.3 具体实现

**步骤 1：创建请求等待管理器**

创建 `/outer-server/scp0005/src/main/java/com/mock/scp0005/service/PendingRequestManager.java`：

```java
package com.mock.scp0005.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;

import java.time.Duration;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 待处理请求管理器
 * 使用 Reactor Sinks 实现非阻塞等待
 */
@Slf4j
@Component
public class PendingRequestManager {

    // 存储待处理请求的 Sink
    private final ConcurrentHashMap<String, Sinks.One<String>> pendingSinks = new ConcurrentHashMap<>();

    /**
     * 创建等待器 - 返回一个 Mono，当回调到达时自动完成
     *
     * @param requestId 请求ID
     * @param timeoutMs 超时时间（毫秒）
     * @return 响应结果的 Mono
     */
    public Mono<String> waitForResult(String requestId, long timeoutMs) {
        // 创建一个 Sinks.One，用于接收单个结果
        Sinks.One<String> sink = Sinks.one();
        pendingSinks.put(requestId, sink);

        log.debug("请求 {} 已注册等待", requestId);

        return sink.asMono()
                .timeout(Duration.ofMillis(timeoutMs))
                .doOnSuccess(result -> {
                    pendingSinks.remove(requestId);
                    log.debug("请求 {} 获取到结果", requestId);
                })
                .doOnError(e -> {
                    pendingSinks.remove(requestId);
                    log.warn("请求 {} 等待超时或失败: {}", requestId, e.getMessage());
                })
                .doOnCancel(() -> {
                    pendingSinks.remove(requestId);
                    log.debug("请求 {} 已取消", requestId);
                });
    }

    /**
     * 完成请求 - 当收到回调时调用
     *
     * @param requestId    请求ID
     * @param responseData 响应数据
     * @return true 如果成功触发，false 如果请求不存在或已超时
     */
    public boolean completeRequest(String requestId, String responseData) {
        Sinks.One<String> sink = pendingSinks.remove(requestId);
        if (sink != null) {
            Sinks.EmitResult result = sink.tryEmitValue(responseData);
            if (result.isSuccess()) {
                log.debug("请求 {} 已成功完成", requestId);
                return true;
            } else {
                log.warn("请求 {} 完成失败: {}", requestId, result);
                return false;
            }
        }
        log.warn("请求 {} 不存在或已超时", requestId);
        return false;
    }

    /**
     * 获取当前等待中的请求数（用于监控）
     */
    public int getPendingCount() {
        return pendingSinks.size();
    }
}
```

**步骤 2：创建回调接口**

创建 `/outer-server/scp0005/src/main/java/com/mock/scp0005/controller/CallbackController.java`：

```java
package com.mock.scp0005.controller;

import com.mock.scp0005.service.PendingRequestManager;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

/**
 * 回调接口 - 供 outer-consumer 调用
 */
@Slf4j
@RestController
@RequestMapping("/internal/callback")
@RequiredArgsConstructor
public class CallbackController {

    private final PendingRequestManager pendingRequestManager;

    /**
     * 接收响应回调
     *
     * @param requestId    请求ID
     * @param responseData 响应数据（JSON字符串）
     */
    @PostMapping("/{requestId}")
    public Mono<ResponseEntity<String>> receiveCallback(
            @PathVariable String requestId,
            @RequestBody String responseData) {

        log.debug("收到请求 {} 的回调", requestId);

        boolean success = pendingRequestManager.completeRequest(requestId, responseData);

        if (success) {
            return Mono.just(ResponseEntity.ok("{\"status\":\"success\"}"));
        } else {
            // 请求可能已超时或不存在，但仍返回 200（幂等性）
            return Mono.just(ResponseEntity.ok("{\"status\":\"ignored\",\"reason\":\"request_not_found_or_timeout\"}"));
        }
    }

    /**
     * 健康检查 / 监控端点
     */
    @GetMapping("/status")
    public Mono<ResponseEntity<String>> getStatus() {
        int pendingCount = pendingRequestManager.getPendingCount();
        return Mono.just(ResponseEntity.ok(
            String.format("{\"pending_requests\":%d}", pendingCount)
        ));
    }
}
```

**步骤 3：修改 GatewayService 使用 PendingRequestManager**

修改 `/outer-server/scp0005/src/main/java/com/mock/scp0005/service/GatewayService.java`：

```java
@Slf4j
@Service
@RequiredArgsConstructor
public class GatewayService {

    private final DatabaseClient databaseClient;
    private final PendingRequestManager pendingRequestManager;  // 新增
    private final GatewayConfig gatewayConfig;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public Mono<String> requestInvoke(String channel, String code, String paramData) {
        String requestId = generateRequestId();
        long startTime = System.currentTimeMillis();

        log.info("流水号:{}, 开始处理请求, channel={}, code={}", requestId, channel, code);

        String enrichedParamData = addTraceTimestamp(paramData, startTime);
        // ... 其他字段提取 ...

        // 3. 写入内网数据库请求表
        return insertInnerRequest(requestId, code, enrichedParamData, channelType, finalSerialNo, source, target)
                .doOnSuccess(v -> log.info("流水号:{}, 请求已写入内网数据库", requestId))
                .doOnError(e -> log.error("流水号:{}, 写入内网数据库失败: {}", requestId, e.getMessage()))
                // 4. 使用 Sinks 等待回调（替代轮询）
                .then(pendingRequestManager.waitForResult(requestId, gatewayConfig.getPollTimeoutMs()))
                .doOnSuccess(result -> {
                    long elapsed = System.currentTimeMillis() - startTime;
                    log.info("流水号:{}, 请求处理完成, 耗时={}ms", requestId, elapsed);
                })
                .doOnError(e -> {
                    long elapsed = System.currentTimeMillis() - startTime;
                    log.error("流水号:{}, 请求处理失败, 耗时={}ms, error={}", requestId, elapsed, e.getMessage());
                });
    }

    // ... 其他方法保持不变 ...
}
```

**步骤 4：修改 outer-consumer 添加 HTTP 回调**

修改 `/outer-server/outer-consumer/src/main/java/com/mock/outerconsumer/consumer/BinlogConsumer.java`：

```java
@Slf4j
@Component
@RequiredArgsConstructor
public class BinlogConsumer {

    private final StringRedisTemplate redisTemplate;
    private final RestTemplate restTemplate;  // 新增
    private final GatewayConfig gatewayConfig;

    @KafkaListener(topics = "${gateway.kafka.response-topic}", groupId = "${spring.kafka.consumer.group-id}")
    public void consumeResponseBinlog(String message, Acknowledgment ack) {
        try {
            JsonNode root = objectMapper.readTree(message);
            String requestId = extractRequestId(root);
            String responseData = extractResponseData(root);

            // 1. 仍然写入 Redis（作为备份/降级方案）
            String redisKey = "gateway:result:" + requestId;
            redisTemplate.opsForValue().set(redisKey, responseData, Duration.ofMinutes(5));

            // 2. HTTP 回调 scp0005（新增 - 主要通知方式）
            callbackToGateway(requestId, responseData);

            log.debug("请求 {} 结果已写入 Redis 并回调通知", requestId);
            ack.acknowledge();
        } catch (Exception e) {
            log.error("处理响应消息失败", e);
        }
    }

    /**
     * 回调 scp0005 通知结果就绪
     */
    private void callbackToGateway(String requestId, String responseData) {
        String callbackUrl = gatewayConfig.getCallbackUrl() + "/internal/callback/" + requestId;
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<String> entity = new HttpEntity<>(responseData, headers);

            ResponseEntity<String> response = restTemplate.postForEntity(callbackUrl, entity, String.class);

            if (response.getStatusCode().is2xxSuccessful()) {
                log.debug("请求 {} 回调成功", requestId);
            } else {
                log.warn("请求 {} 回调返回非 2xx: {}", requestId, response.getStatusCode());
            }
        } catch (Exception e) {
            // 回调失败不影响主流程，scp0005 会超时后从 Redis 降级获取
            log.warn("请求 {} 回调失败，将依赖 Redis 降级: {}", requestId, e.getMessage());
        }
    }
}
```

**步骤 5：配置 outer-consumer 的回调地址**

修改 `/outer-server/outer-consumer/src/main/resources/application.yml`：

```yaml
gateway:
  kafka:
    response-topic: outer_response_binlog
  result-key-prefix: "gateway:result:"
  result-expire-seconds: 300
  callback-url: http://scp0005:8080  # 新增：回调地址
```

### 6.3 方案对比

| 指标 | 轮询模式 | Sinks + HTTP 回调 |
|------|----------|-------------------|
| Redis 请求数(100TPS) | ~30,000/秒 | ~100/秒（仅备份写入） |
| 响应延迟 | 50-100ms（轮询间隔） | **<5ms**（近乎实时） |
| CPU 开销 | 高（持续轮询） | 极低（事件驱动） |
| 网络开销 | Redis 密集访问 | 单次 HTTP 回调 |
| 代码复杂度 | 低 | 中 |
| 可靠性 | 高 | 高（有 Redis 降级） |

### 6.4 降级策略

**问题**：如果 HTTP 回调失败怎么办？

**解决方案**（已在代码中实现）：
1. outer-consumer 仍然将结果写入 Redis（作为备份）
2. 回调失败时记录日志，不影响主流程
3. scp0005 超时后可从 Redis 降级获取（可选实现）

```
降级流程：
┌─────────────────────────────────────────┐
│ outer-consumer                          │
│  ├── 写入 Redis ✓                       │
│  └── HTTP 回调 ✗ (失败)                 │
└─────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────┐
│ scp0005                                 │
│  ├── Sinks 等待超时                      │
│  └── 降级从 Redis 获取（可选）           │
└─────────────────────────────────────────┘
```

### 6.5 验证方法

```bash
# 监控回调接口调用
curl http://scp0005:8080/internal/callback/status

# 查看等待中的请求数
# 期望：高并发时 pending_requests 数量稳定，不持续增长

# 对比延迟
# 优化前：P50 ~100ms（轮询间隔）
# 优化后：P50 <10ms（HTTP 回调延迟）
```

---

## 七、优化方向 5：Redis 集群性能优化

### 7.1 问题分析

**现状**：
- Redis 连接池配置可能不当
- 缺乏批量操作，网络往返次数多
- 缺乏缓存预热和智能过期策略

### 7.2 优化方案

**目标**：充分利用 Redis 集群能力，减少网络延迟

#### 7.2.1 Redis 连接池优化

**当前配置**（scp0005 application.yml）：
```yaml
spring:
  redis:
    host: ${REDIS_HOST:redis}
    port: ${REDIS_PORT:6379}
    timeout: 10s
    lettuce:
      pool:
        max-active: 20      # ← 当前值：20
        max-idle: 10        # ← 当前值：10
        min-idle: 5         # ← 当前值：5
```

**当前配置**（outer-consumer application.yml）：
```yaml
spring:
  data:
    redis:
      host: ${REDIS_HOST:redis}
      port: ${REDIS_PORT:6379}
      timeout: 5000ms
      lettuce:
        pool:
          max-active: 20    # ← 当前值：20
          max-idle: 10      # ← 当前值：10
          min-idle: 5       # ← 当前值：5
```

**方案 A：配置文件优化**（简单方案）

修改 `/outer-server/scp0005/src/main/resources/application.yml`：
```yaml
spring:
  redis:
    host: ${REDIS_HOST:redis}
    port: ${REDIS_PORT:6379}
    timeout: 2s                # ← 修改：从 10s 降低到 2s
    lettuce:
      pool:
        max-active: 100        # ← 修改：从 20 提升到 100
        max-idle: 30           # ← 修改：从 10 提升到 30
        min-idle: 10           # ← 修改：从 5 提升到 10
        max-wait: 2s           # ← 新增：最大等待时间
```

修改 `/outer-server/outer-consumer/src/main/resources/application.yml`：
```yaml
spring:
  data:
    redis:
      host: ${REDIS_HOST:redis}
      port: ${REDIS_PORT:6379}
      timeout: 2000ms          # ← 修改：从 5000ms 降低到 2000ms
      lettuce:
        pool:
          max-active: 100      # ← 修改：从 20 提升到 100
          max-idle: 30         # ← 修改：从 10 提升到 30
          min-idle: 10         # ← 修改：从 5 提升到 10
          max-wait: 2000ms     # ← 新增：最大等待时间
```

**方案 B：Java 配置类优化**（高级方案，可选）

创建 `/outer-server/scp0005/src/main/java/com/mock/scp0005/config/RedisConfig.java`：

```java
@Configuration
public class RedisConfig {

    @Bean
    public LettuceConnectionFactory redisConnectionFactory() {
        // Redis 配置
        RedisStandaloneConfiguration redisConfig = new RedisStandaloneConfiguration();
        redisConfig.setHostName("redis");
        redisConfig.setPort(6379);

        // Lettuce 客户端配置 - 连接池优化
        GenericObjectPoolConfig<?> poolConfig = new GenericObjectPoolConfig<>();
        poolConfig.setMaxTotal(200);          // 最大连接数
        poolConfig.setMaxIdle(50);            // 最大空闲连接数
        poolConfig.setMinIdle(20);            // 最小空闲连接数
        poolConfig.setMaxWaitMillis(2000);    // 最大等待时间
        poolConfig.setTestOnBorrow(true);     // 借出时测试
        poolConfig.setTestWhileIdle(true);    // 空闲时测试
        poolConfig.setTimeBetweenEvictionRuns(Duration.ofSeconds(30));

        LettucePoolingClientConfiguration clientConfig = LettucePoolingClientConfiguration.builder()
            .commandTimeout(Duration.ofMillis(500))
            .poolConfig(poolConfig)
            .build();

        return new LettuceConnectionFactory(redisConfig, clientConfig);
    }

    @Bean
    public ReactiveStringRedisTemplate reactiveStringRedisTemplate(
            ReactiveRedisConnectionFactory connectionFactory) {
        return new ReactiveStringRedisTemplate(connectionFactory);
    }
}
```

#### 变更摘要（Redis 连接池）

| 配置项 | 当前值 | 修改后 | 说明 |
|--------|--------|--------|------|
| `max-active` | 20 | **100** | 最大连接数提升 5 倍 |
| `max-idle` | 10 | **30** | 最大空闲连接提升 3 倍 |
| `min-idle` | 5 | **10** | 最小空闲连接翻倍 |
| `timeout` | 5-10s | **2s** | 命令超时减少，快速失败 |
| `max-wait` | (默认) | **2s** | 新增获取连接最大等待时间 |

#### 7.2.2 批量操作优化

创建 `/outer-server/outer-consumer/src/main/java/com/mock/outerconsumer/service/OptimizedRedisService.java`：

```java
@Service
@RequiredArgsConstructor
public class OptimizedRedisService {

    private final StringRedisTemplate redisTemplate;

    /**
     * 使用管道进行批量操作，减少网络往返
     */
    public Map<String, String> batchGetResults(List<String> requestIds) {
        List<Object> results = redisTemplate.executePipelined(
            (RedisCallback<String>) connection -> {
                for (String requestId : requestIds) {
                    connection.get(("gateway:result:" + requestId).getBytes());
                }
                return null;
            }
        );

        Map<String, String> resultMap = new HashMap<>();
        for (int i = 0; i < requestIds.size() && i < results.size(); i++) {
            String result = (String) results.get(i);
            if (result != null) {
                resultMap.put(requestIds.get(i), result);
            }
        }
        return resultMap;
    }

    /**
     * 批量设置结果
     */
    public void batchSetResults(Map<String, String> results, long expireSeconds) {
        redisTemplate.executePipelined(
            (RedisCallback<String>) connection -> {
                for (Map.Entry<String, String> entry : results.entrySet()) {
                    String key = "gateway:result:" + entry.getKey();
                    connection.setEx(
                        key.getBytes(),
                        expireSeconds,
                        entry.getValue().getBytes()
                    );
                }
                return null;
            }
        );
    }

    /**
     * 使用 Lua 脚本优化原子操作
     */
    public boolean setResultIfNotExists(String requestId, String result) {
        String key = "gateway:result:" + requestId;
        String script =
            "if redis.call('GET', KEYS[1]) == false then " +
            "redis.call('SET', KEYS[1], ARGV[1]); " +
            "redis.call('EXPIRE', KEYS[1], 300); " +
            "return 1; " +
            "else return 0; end";

        DefaultRedisScript<Long> redisScript = new DefaultRedisScript<>();
        redisScript.setScriptText(script);
        redisScript.setResultType(Long.class);

        Long resultVal = redisTemplate.execute(
            redisScript,
            Collections.singletonList(key),
            result
        );

        return resultVal != null && resultVal == 1;
    }
}
```

### 7.3 连接池参数说明

| 参数 | 值 | 说明 |
|------|-----|------|
| maxTotal | 200 | 连接池最大连接数 |
| maxIdle | 50 | 最大空闲连接数 |
| minIdle | 20 | 最小空闲连接数 |
| maxWaitMillis | 2000 | 获取连接最大等待时间 |
| commandTimeout | 500ms | 命令执行超时 |

### 7.4 预期效果

- **连接复用效率提升**：减少连接建立开销
- **网络延迟降低**：通过管道操作减少网络往返次数
- **系统稳定性增强**：更好的错误处理和超时控制

---

## 八、实施计划

### 8.1 实施阶段

```
第一阶段（1-2周）：基础配置优化
├── Day 1: 增加 Kafka 分区数
├── Day 2: 修改 Kafka 消费者并发配置（优化1）
├── Day 3: 修改 Canal/Kafka 生产者配置（优化2）
├── Day 4: 优化 MySQL 配置和数据库连接池（优化3）
└── Day 5-7: 压测验证，记录性能提升

第二阶段（2-3周）：代码优化
├── Day 1-2: 引入 HTTP 连接池（优化4.1）
├── Day 3-4: 实现 Redis 指数退避轮询（优化4.2）
├── Day 5-6: 优化 Redis 连接池和批量操作（优化5）
└── Day 7: 压测验证

第三阶段（1周）：测试与调优
├── Day 1-3: 全面压力测试
├── Day 4: 监控系统稳定性
└── Day 5: 参数微调
```

### 8.2 回滚方案

每个优化都支持独立回滚：
1. **配置回滚**：恢复原配置文件，重启服务
2. **代码回滚**：Git revert 对应 commit

### 8.3 监控指标

实施过程中需要关注的关键指标：
- **TPS**：目标从 12 提升到 60+
- **P99 延迟**：目标从 1.5s 降低到 <500ms
- **错误率**：目标从 95%(50并发) 降低到 <5%
- **CPU/内存**：确保资源充足
- **Kafka Consumer Lag**：目标接近 0
- **Redis 连接池使用率**：保持在 80% 以下

---

## 九、风险评估

### 9.1 技术风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| Kafka 分区增加后数据分布不均 | 中 | 使用一致性哈希或 Round-Robin |
| Canal 配置过激导致数据丢失 | 高 | 保留 kafka.acks=1，启用重试 |
| 连接池配置过大导致资源耗尽 | 中 | 监控连接使用率，动态调整 |
| Redis 批量操作事务边界问题 | 低 | 明确操作原子性要求 |

### 9.2 业务风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 数据一致性问题 | 高 | 保留日志追踪，支持数据校验 |
| 缓存过期策略不当 | 中 | 设置合理 TTL，监控命中率 |

### 9.3 风险缓解总体措施

1. 每个优化单独实施，逐步验证
2. 建立完善的监控和告警机制
3. 准备快速回滚方案
4. 在低峰期进行变更

---

## 十、预期效果总结

### 10.1 单项优化效果预估

| 优化方向 | TPS 提升 | 延迟改善 | 累计效果 |
|----------|----------|----------|----------|
| 基线 | 12 | 500ms | - |
| +优化1 (Kafka并发) | 36-48 | -30% | 3-4x |
| +优化2 (Canal配置) | +15% | -20% | 4-5x |
| +优化3 (数据库优化) | +10% | -15% | 4.5-5.5x |
| +优化4 (HTTP+Pub/Sub) | +15% | **-40%** | 5.5-6.5x |
| +优化5 (Redis集群优化) | +5% | -10% | 6-7x |

### 10.2 最终目标

| 指标 | 优化前 | 优化后目标 | 提升幅度 |
|------|--------|-----------|----------|
| 最大 TPS | ~12 | 70-90 | **6-7倍** |
| P50 延迟 | 500ms | <150ms | **70%+** |
| P99 延迟 | 1.5s | <400ms | **73%+** |
| 错误率(50并发) | 95% | <5% | **显著改善** |

---

## 十一、附录：配置文件汇总

### 需要修改的配置文件

```
/inner-server/
├── scp0006/src/main/resources/application.yml     # Kafka消费并发、数据库连接池
├── scp0006/pom.xml                                # HttpClient依赖
├── scp0006/src/main/java/.../RestTemplateConfig.java  # HTTP连接池
├── config/canal/canal.properties                  # Canal/Kafka生产者
├── config/canal/instance.properties               # Canal 实例配置
└── docker-compose.yml                             # MySQL 参数优化

/outer-server/
├── scp0005/src/main/resources/application.yml     # Pub/Sub配置、R2DBC连接池
├── scp0005/src/main/java/.../GatewayConfig.java   # 网关配置类
├── scp0005/src/main/java/.../GatewayService.java  # Pub/Sub订阅逻辑（替代轮询）
├── scp0005/src/main/java/.../RedisPubSubConfig.java  # Redis Pub/Sub配置（新增）
├── scp0005/src/main/java/.../RedisConfig.java     # Redis连接池配置
├── outer-consumer/src/main/resources/application.yml  # Kafka消费并发
├── outer-consumer/src/main/java/.../BinlogConsumer.java  # 添加Pub/Sub发布逻辑
├── outer-consumer/src/main/java/.../OptimizedRedisService.java  # Redis批量操作
├── config/canal/canal.properties                  # Canal/Kafka生产者
└── docker-compose.yml                             # MySQL 参数优化
```

### 压测命令

```bash
cd /Users/shulie/Desktop/SynologyDrive/个人/cursor/IncidentReview/guowang/innergateway/mock-system/perf-test

# 轻载测试
wrk -t2 -c10 -d30s -s post.lua http://192.168.123.66:8080/inner/c1/yhzx

# 中载测试
wrk -t4 -c50 -d30s -s post.lua http://192.168.123.66:8080/inner/c1/yhzx

# 重载测试
wrk -t8 -c100 -d30s -s post.lua http://192.168.123.66:8080/inner/c1/yhzx
```

---

## 十二、变更记录

| 版本 | 日期 | 变更内容 |
|------|------|----------|
| v1.0 | 2026-01-14 | 初始版本，5个优化方向 |
| v1.1 | 2026-01-14 | 合并补充文档，完善数据库和Redis优化细节 |
| v1.2 | 2026-01-14 | 优化方向4：将Redis轮询改为WebFlux Sinks + HTTP回调，利用现有响应式架构，延迟降至<5ms |
| v1.3 | 2026-01-14 | 补充所有优化方向的"当前配置"与"修改后配置"详细对比，便于审核和实施 |
