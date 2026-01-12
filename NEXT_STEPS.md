# 下一步执行指令

> 🔴 **当前任务：修复 MySQL Binlog 不记录 INSERT 事件问题**
>
> **问题现象**：MySQL log_bin=ON，但 INSERT 操作没有被写入 Binlog 文件

---

## 🔧 问题根因分析

MySQL 8.0 在 Docker 环境下可能存在以下问题：
1. **binlog 缓冲未刷新** - `sync_binlog` 默认可能导致延迟写入
2. **旧 volume 数据冲突** - 之前的 MySQL 数据可能导致 binlog 状态不一致
3. **gtid_mode 未配置** - MySQL 8.0 可能需要显式配置 GTID

**解决方案**：增强 MySQL 配置 + 完全清理旧数据重新初始化

---

## 🚀 机器 B 完全重置步骤

### 步骤1：完全停止并清理（关键！）

```bash
cd /path/to/mock-system/inner-server

# 停止所有服务
docker-compose down

# 删除所有 volume（重要！必须清理旧的MySQL数据）
docker volume rm inner-server_mysql_data inner-server_kafka_data inner-server_canal_logs 2>/dev/null || true

# 确认 volume 已删除
docker volume ls | grep inner-server
```

### 步骤2：拉取最新配置

```bash
git pull origin main
```

### 步骤3：启动 MySQL 和 Kafka

```bash
# 启动 MySQL 和 Kafka
docker-compose up -d mysql kafka

# 等待 MySQL 完全初始化（约60秒）
sleep 60

# 检查状态
docker-compose ps
```

### 步骤4：验证 MySQL Binlog 配置

```bash
# 检查 Binlog 配置
docker exec -it mysql-inner mysql -uroot -proot123 -e "
SHOW VARIABLES LIKE 'log_bin';
SHOW VARIABLES LIKE 'binlog_format';
SHOW VARIABLES LIKE 'sync_binlog';
SHOW VARIABLES LIKE 'gtid_mode';
SHOW VARIABLES LIKE 'enforce_gtid_consistency';
"
```

**预期输出**：
```
log_bin                      = ON
binlog_format                = ROW
sync_binlog                  = 1
gtid_mode                    = ON
enforce_gtid_consistency     = ON
```

### 步骤5：测试 Binlog 是否正常工作

```bash
# 1. 手动插入测试数据
docker exec -it mysql-inner mysql -uroot -proot123 -e \
  "INSERT INTO inner_gateway.inner_request (request_id, code, param_data) VALUES ('binlog-test-$(date +%s)', 'yhzx', '{\"test\":true}');"

# 2. 检查 Binlog 事件（关键验证！）
docker exec -it mysql-inner mysql -uroot -proot123 -e \
  "SHOW BINLOG EVENTS IN 'mysql-bin.000001' LIMIT 30;"
```

**预期结果**：应该看到包含 `inner_request` 表的 INSERT 事件

### 步骤6：启动 Canal

```bash
# 启动 Canal
docker-compose up -d canal

# 等待 Canal 连接
sleep 10

# 查看 Canal 日志
docker-compose logs --tail=50 canal
```

**预期日志**：应该看到成功连接 MySQL 和 Kafka

### 步骤7：验证端到端

```bash
# 1. 再次插入测试数据
docker exec -it mysql-inner mysql -uroot -proot123 -e \
  "INSERT INTO inner_gateway.inner_request (request_id, code, param_data) VALUES ('e2e-test-$(date +%s)', 'yhzx', '{\"test\":true}');"

# 2. 检查 Kafka 是否收到消息
docker exec -it kafka-inner kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic inner_request_binlog \
  --from-beginning \
  --max-messages 5 \
  --timeout-ms 10000
```

**预期结果**：应该看到 JSON 格式的 Binlog 消息

### 步骤8：启动应用服务

```bash
# 构建并启动应用
docker-compose up -d --build target-service scp0006

# 查看 scp0006 日志
docker-compose logs -f scp0006
```

---

## ✅ 验证检查清单

| 检查项 | 命令 | 预期结果 |
|--------|------|----------|
| log_bin | `SHOW VARIABLES LIKE 'log_bin';` | ON |
| gtid_mode | `SHOW VARIABLES LIKE 'gtid_mode';` | ON |
| sync_binlog | `SHOW VARIABLES LIKE 'sync_binlog';` | 1 |
| Binlog 有事件 | `SHOW BINLOG EVENTS...` | 能看到 INSERT 事件 |
| Kafka 收到消息 | `kafka-console-consumer...` | 有 JSON 消息 |

---

## 📝 部署结果记录

| 步骤 | 检查项 | 结果 | 备注 |
|------|--------|------|------|
| 1 | 停止并清理所有 volume | ⏳ | - |
| 2 | 拉取最新配置 | ⏳ | - |
| 3 | MySQL + Kafka 启动 | ⏳ | - |
| 4 | MySQL Binlog 配置验证 | ⏳ | - |
| 5 | Binlog 事件测试 | ⏳ | - |
| 6 | Canal 启动 | ⏳ | - |
| 7 | Kafka 收到消息 | ⏳ | - |
| 8 | 应用服务启动 | ⏳ | - |

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
