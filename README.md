# 内外网穿透网关模拟系统

## 项目说明

这是一个模拟内外网穿透网关的系统，用于性能优化验证。

## 架构图

```
┌─────────────────────────────────────┐     ┌─────────────────────────────────────┐
│         机器 A（外网）               │     │          机器 B（内网）              │
├─────────────────────────────────────┤     ├─────────────────────────────────────┤
│                                     │     │                                     │
│  应用服务:                           │     │  应用服务:                           │
│  ├─ scp0005 (外网网关)      :8005   │     │  ├─ scp0006 (内网穿透)      :8006   │
│  └─ outer-consumer          :8010   │     │  └─ target-service          :8017   │
│                                     │     │                                     │
│  数据库:                             │     │  数据库:                             │
│  └─ MySQL (响应表)          :3306   │     │  └─ MySQL (请求表)          :3306   │
│                                     │     │                                     │
│  中间件:                             │     │  中间件:                             │
│  ├─ Redis                   :6379   │     │  └─ Canal (监听请求表)      :11111  │
│  ├─ Kafka                   :9092   │     │                                     │
│  └─ Canal (监听响应表)      :11111  │     │                                     │
│                                     │     │                                     │
└─────────────────────────────────────┘     └─────────────────────────────────────┘
```

## 数据流

```
1. 客户端 → scp0005 (机器A)
2. scp0005 → INSERT → 机器B的MySQL(请求表)
3. 机器B的Canal 监听到 Binlog → Kafka (机器A)
4. scp0006 消费 Kafka → 调用 target-service
5. scp0006 → INSERT → 机器A的MySQL(响应表)
6. 机器A的Canal 监听到 Binlog → Kafka
7. outer-consumer 消费 → 写入 Redis
8. scp0005 从 Redis 获取结果 → 返回客户端
```

---

## 部署指南

### 前置要求

- 两台 Mac 笔记本（或任意支持 Docker 的机器）
- 两台机器在同一局域网
- 已安装 Docker Desktop

### 部署步骤

**重要**：请按照以下顺序部署

| 步骤 | 机器 | 操作 |
|------|------|------|
| 1 | 机器 A | 执行 `outer-server/SETUP_MACHINE_A.md` |
| 2 | 机器 B | 执行 `inner-server/SETUP_MACHINE_B.md` |
| 3 | 机器 A | 启动应用服务 |
| 4 | 机器 B | 启动应用服务 |
| 5 | 任意 | 执行测试验证 |

---

## 目录结构

```
mock-system/
├── README.md                          # 本文件
├── outer-server/                      # 机器 A（外网）部署文件
│   ├── SETUP_MACHINE_A.md            # 【AI 执行指令】机器 A 部署步骤
│   ├── docker-compose.yml            # Docker Compose 配置
│   ├── config/
│   │   ├── mysql/init.sql            # 数据库初始化（响应表）
│   │   └── canal/instance.properties # Canal 配置
│   └── scripts/
│       ├── start.sh                  # 启动脚本
│       └── test.sh                   # 测试脚本
│
└── inner-server/                      # 机器 B（内网）部署文件
    ├── SETUP_MACHINE_B.md            # 【AI 执行指令】机器 B 部署步骤
    ├── docker-compose.yml            # Docker Compose 配置
    ├── config/
    │   ├── mysql/init.sql            # 数据库初始化（请求表）
    │   └── canal/instance.properties # Canal 配置
    └── scripts/
        └── start.sh                  # 启动脚本
```

---

## 给 AI 助手的说明

如果你是 AI 助手（Claude Code / Cursor / Gemini 等），请按以下方式操作：

### 机器 A（外网）
请阅读并执行 `outer-server/SETUP_MACHINE_A.md` 中的所有步骤。

### 机器 B（内网）
请阅读并执行 `inner-server/SETUP_MACHINE_B.md` 中的所有步骤。

**注意**：
- 执行前请先确认本机 IP 地址
- 需要知道对方机器的 IP 地址
- 按步骤顺序执行，不要跳步
