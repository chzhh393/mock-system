# 下一步执行指令

> 🔴 **当前任务：排查联调测试失败问题**
>
> **问题**：机器A发起请求后，机器B未收到请求

---

## 🔍 排查步骤（按顺序执行）

### 步骤1：机器 A 检查 scp0005 是否能连接机器B的MySQL

```bash
# 1. 进入 scp0005 容器
docker exec -it scp0005 bash

# 2. 测试到机器B MySQL的网络连通性
nc -zv 192.168.123.65 3306

# 3. 退出容器
exit
```

**预期结果**：显示 `Connection to 192.168.123.65 3306 port [tcp/mysql] succeeded!`

**如果失败**：检查机器B的防火墙或MySQL是否允许远程连接

---

### 步骤2：机器 A 发送测试请求并查看日志

```bash
# 1. 打开一个终端，实时查看 scp0005 日志
docker-compose logs -f scp0005

# 2. 在另一个终端发送测试请求
curl -X POST http://localhost:8080/inner/c1/yhzx \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "code=yhzx&paramData={\"userId\":\"test001\",\"action\":\"query\"}"
```

**查看日志中是否有**：
- `写入内网数据库成功` 或类似成功信息
- 如有报错，记录错误信息

---

### 步骤3：机器 B 检查请求是否写入MySQL

```bash
# 查看 inner_request 表是否有数据
docker exec -it mysql-inner mysql -uroot -proot123 -e \
  "SELECT * FROM inner_gateway.inner_request ORDER BY id DESC LIMIT 5;"
```

**预期结果**：显示最近的请求记录

**如果没有数据**：说明 scp0005 没有成功写入，问题在机器A

---

### 步骤4：机器 B 检查 Canal 是否监听到变化

```bash
# 查看 Canal 日志
docker-compose logs --tail=50 canal
```

**查看是否有**：
- Binlog 解析相关日志
- Kafka 发送相关日志
- 任何错误信息

---

### 步骤5：机器 B 检查 scp0006 是否收到消息

```bash
# 查看 scp0006 日志
docker-compose logs --tail=50 scp0006
```

**查看是否有**：
- `收到 Binlog 消息` 相关日志
- Kafka 消费相关日志

---

### 步骤6：机器 A 检查 Kafka 中是否有消息

```bash
# 查看 inner_request_binlog topic 中的消息
docker exec -it kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic inner_request_binlog \
  --from-beginning \
  --max-messages 5
```

**预期结果**：显示 JSON 格式的 Binlog 消息

---

## 📝 排查结果记录

请在下方记录每个步骤的结果：

| 步骤 | 检查项 | 结果 | 备注 |
|------|--------|------|------|
| 1 | scp0005→机器B MySQL连通性 | ⏳ | - |
| 2 | scp0005 写入日志 | ⏳ | - |
| 3 | 机器B MySQL有请求数据 | ⏳ | - |
| 4 | 机器B Canal监听日志 | ⏳ | - |
| 5 | scp0006 收到消息 | ⏳ | - |
| 6 | Kafka有消息 | ⏳ | - |

---

## 原始部署指令（已完成可跳过）

## 机器 A（外网 192.168.123.66）

### 执行以下命令：

```bash
# 1. 进入项目目录
cd /path/to/mock-system/outer-server

# 2. 拉取最新代码
git pull origin main

# 3. 构建并启动应用服务
docker-compose up -d --build scp0005 outer-consumer

# 4. 查看服务状态
docker-compose ps

# 5. 查看 scp0005 日志（确认启动成功）
docker-compose logs -f scp0005

# 6. 查看 outer-consumer 日志
docker-compose logs -f outer-consumer
```

### 预期结果：
- scp0005 启动在 8080 端口
- outer-consumer 启动在 8081 端口
- 日志无报错

### 完成后：
在下方签到区记录完成状态

---

## 机器 B（内网 192.168.123.65）

### 执行以下命令：

```bash
# 1. 进入项目目录
cd /path/to/mock-system/inner-server

# 2. 拉取最新代码
git pull origin main

# 3. 构建并启动应用服务
docker-compose up -d --build target-service scp0006

# 4. 查看服务状态
docker-compose ps

# 5. 查看 target-service 日志（确认启动成功）
docker-compose logs -f target-service

# 6. 查看 scp0006 日志
docker-compose logs -f scp0006
```

### 预期结果：
- target-service 启动在 8083 端口
- scp0006 启动在 8082 端口
- scp0006 日志显示已连接到 Kafka
- 日志无报错

### 完成后：
在下方签到区记录完成状态

---

## 联调测试（两台机器都启动后执行）

在机器 A 上执行测试请求：

```bash
# 发送测试请求到 scp0005
curl -X POST http://localhost:8080/inner/c1/yhzx \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "code=yhzx&paramData={\"userId\":\"test001\",\"action\":\"query\"}"
```

### 预期结果：
返回 JSON 响应，包含 `code: 200`

---

## 签到区

| 时间 | 机器 | 任务 | 状态 | 备注 |
|------|------|------|------|------|
| - | 机器 A | 应用服务启动 | ⏳ 待执行 | - |
| 2026-01-12 | 机器 B | 应用服务启动 | ✅ 已完成 | 所有服务正常启动，Kafka连接成功 |
| 2026-01-12 | 机器 A | 联调测试 | ❌ 失败 | 机器A发起请求后，机器B未收到请求 |

---

## 故障排查

### 如果构建失败：
```bash
# 查看构建日志
docker-compose logs [服务名]

# 清理并重新构建
docker-compose down
docker-compose build --no-cache [服务名]
docker-compose up -d [服务名]
```

### 如果服务无法连接：
1. 检查防火墙设置
2. 检查 IP 地址配置
3. 检查端口是否被占用

---

*最后更新：2026-01-12*
