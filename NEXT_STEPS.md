# 下一步执行指令

> 🔴 **当前任务：构建并启动应用服务**

---

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
