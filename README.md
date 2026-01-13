# 内外网穿透网关模拟系统

## 项目说明

这是一个模拟内外网穿透网关的系统，用于性能优化验证。

## 架构图

```
┌─────────────────────────────────────┐     ┌─────────────────────────────────────┐
│         机器 A（外网）               │     │          机器 B（内网）              │
│         192.168.123.66              │     │          192.168.123.81             │
├─────────────────────────────────────┤     ├─────────────────────────────────────┤
│                                     │     │                                     │
│  应用服务:                           │     │  应用服务:                           │
│  ├─ scp0005 (外网网关)      :8080   │     │  ├─ scp0006 (内网穿透)      :8082   │
│  └─ outer-consumer          :8081   │     │  └─ target-service          :8017   │
│                                     │     │                                     │
│  数据库:                             │     │  数据库:                             │
│  └─ MySQL (响应表)          :3306   │     │  └─ MySQL (请求表)          :3306   │
│                                     │     │                                     │
│  中间件:                             │     │  中间件:                             │
│  ├─ Redis                   :6379   │     │  ├─ Kafka                   :9092   │
│  ├─ Kafka                   :9092   │     │  └─ Kafka Connect (Debezium):8083   │
│  ├─ Kafka Connect (Debezium):8083   │     │                                     │
│  └─ Registry (私有镜像仓库) :5000   │     │                                     │
│                                     │     │                                     │
└─────────────────────────────────────┘     └─────────────────────────────────────┘
```

## 数据流

```
1. 客户端 → scp0005 (机器A)
2. scp0005 → INSERT → 机器B的MySQL(请求表)
3. 机器B的 Debezium 监听 Binlog → Kafka (inner_request_binlog)
4. scp0006 消费 Kafka → 调用 target-service
5. scp0006 → INSERT → 机器A的MySQL(响应表)
6. 机器A的 Debezium 监听 Binlog → Kafka (outer_response_binlog)
7. outer-consumer 消费 → 写入 Redis
8. scp0005 从 Redis 获取结果 → 返回客户端
```

---

## 快速开始

详细部署步骤请参考 **[DEPLOYMENT.md](./DEPLOYMENT.md)**

### 部署方式

| 方式 | 说明 | 适用场景 |
|------|------|----------|
| 私有 Registry + Docker TCP | 一键部署，无需 SSH | 日常更新（推荐） |
| SSH 手动部署 | 完整控制 | 首次部署、问题排查 |
| 本地 E2E 测试 | 单机模拟双环境 | 本地开发验证 |

### 快速部署命令

```bash
# 查看服务状态
./deploy-registry.sh status

# 部署所有服务
./deploy-registry.sh all

# 端到端测试
curl -X POST "http://192.168.123.66:8080/inner/c1/yhzx" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "code=yhzx&paramData={\"test\":\"hello\"}"
```

---

## 目录结构

```
mock-system/
├── README.md                          # 本文件
├── DEPLOYMENT.md                      # 详细部署指南
├── deploy-registry.sh                 # 私有 Registry 部署脚本
├── deploy-remote.sh                   # SSH 远程部署脚本
│
├── outer-server/                      # 机器 A（外网）部署文件
│   ├── docker-compose.yml            # Docker Compose 配置
│   ├── init-debezium-connector.sh    # Debezium 连接器初始化
│   ├── scp0005/                      # 外网网关服务
│   └── outer-consumer/               # 响应消费服务
│
├── inner-server/                      # 机器 B（内网）部署文件
│   ├── docker-compose.yml            # Docker Compose 配置
│   ├── init-debezium-connector.sh    # Debezium 连接器初始化
│   ├── scp0006/                      # 内网穿透服务
│   └── target-service/               # 模拟目标服务
│
└── local-e2e/                         # 本地端到端测试环境
    ├── start-lite.sh                 # 启动精简测试环境
    ├── test-lite.sh                  # 运行测试
    └── stop-lite.sh                  # 停止测试环境
```

---

## 技术栈

- **CDC**: Debezium (Kafka Connect)
- **消息队列**: Apache Kafka
- **数据库**: MySQL 8.0
- **缓存**: Redis
- **应用**: Spring Boot
- **容器**: Docker

---

*详细部署步骤、故障排查请参考 [DEPLOYMENT.md](./DEPLOYMENT.md)*
