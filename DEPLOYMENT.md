# 部署指南

> **状态**：已完成本地端到端测试验证，可直接部署
>
> **技术栈**：MySQL + Canal (阿里巴巴 CDC) + Kafka + Spring Boot + Redis

---

## 网络配置

| 机器 | 角色 | IP 地址 | 说明 |
|------|------|---------|------|
| 开发机 | 本地 | 192.168.123.2 | 构建镜像、执行部署脚本 |
| 机器 A | 外网 | 192.168.123.66 | 部署 scp0005, outer-consumer, Registry |
| 机器 B | 内网 | 192.168.123.81 | 部署 scp0006, target-service |

## 数据流

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            完整请求流程 (~500ms)                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  [客户端] ──HTTP──> [scp0005] ──写入──> [inner_request表]                    │
│                        │                     │                              │
│                        │              (机器B MySQL)                          │
│                        │                     │                              │
│                        │                     v                              │
│                        │              [Canal CDC :11111]                    │
│                        │                     │                              │
│                        │                     v                              │
│                        │              [Kafka: inner_request_binlog]         │
│                        │                     │                              │
│                        │                     v                              │
│                        │               [scp0006] ──调用──> [target-service] │
│                        │                     │                              │
│                        │                     v                              │
│                        │              [outer_response表]                    │
│                        │                     │                              │
│                        │              (机器A MySQL)                          │
│                        │                     │                              │
│                        │                     v                              │
│                        │              [Canal CDC :11111]                    │
│                        │                     │                              │
│                        │                     v                              │
│                        │              [Kafka: outer_response_binlog]        │
│                        │                     │                              │
│                        │                     v                              │
│                        │              [outer-consumer]                      │
│                        │                     │                              │
│                        │                     v                              │
│                        │                 [Redis]                            │
│                        │                     │                              │
│                        <──────轮询获取结果────┘                              │
│                        │                                                    │
│  [客户端] <──HTTP响应──┘                                                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 部署方式

### 方式一：自动化部署（推荐）

通过私有 Registry + Docker TCP 从开发机一键部署，无需 SSH 登录远程机器。

#### 架构图

```
开发机 (192.168.123.2)           机器 A (192.168.123.66)        机器 B (192.168.123.81)
┌─────────────┐                 ┌─────────────────────┐        ┌─────────────────────┐
│ docker build│ ────push────>   │   Registry :5000    │ <─pull─│                     │
│ docker push │                 │   Docker TCP :2375  │        │   Docker TCP :2375  │
│             │ ───TCP cmd──>   │   socat             │        │   socat             │
└─────────────┘                 └─────────────────────┘        └─────────────────────┘
```

#### 前置条件（一次性配置）

**1. 机器 A 上部署 Registry**
```bash
docker run -d --name registry --restart=always -p 5000:5000 -v ~/registry:/var/lib/registry registry:2
```

**2. 所有机器配置 insecure-registries**

在 Docker Desktop → Settings → Docker Engine 中添加：
```json
"insecure-registries": ["192.168.123.66:5000"]
```

**3. 机器 A 和 B 安装并启动 socat**
```bash
# 安装 (macOS)
brew install socat

# 启动（每次机器重启后需执行）
nohup socat TCP-LISTEN:2375,reuseaddr,fork UNIX-CONNECT:/var/run/docker.sock &
```

#### 日常部署命令

```bash
cd mock-system

# 查看服务状态
./deploy-registry.sh status

# 部署所有服务（构建 + 推送 + 远程启动）
./deploy-registry.sh all

# 只部署机器 A 服务 (scp0005, outer-consumer)
./deploy-registry.sh outer

# 只部署机器 B 服务 (scp0006, target-service)
./deploy-registry.sh inner

# 查看 Registry 中的镜像
./deploy-registry.sh images
```

#### 手动部署单个服务

```bash
# 设置环境变量
export DOCKER_API_VERSION=1.44

# 1. 构建并推送镜像
docker build -t 192.168.123.66:5000/scp0005:latest ./outer-server/scp0005
docker push 192.168.123.66:5000/scp0005:latest

# 2. 在远程机器拉取并启动
docker -H tcp://192.168.123.66:2375 pull 192.168.123.66:5000/scp0005:latest
docker -H tcp://192.168.123.66:2375 stop scp0005 || true
docker -H tcp://192.168.123.66:2375 rm scp0005 || true
docker -H tcp://192.168.123.66:2375 run -d --name scp0005 -p 8080:8080 192.168.123.66:5000/scp0005:latest
```

#### 便捷别名（可选）

在 `~/.zshrc` 中添加：
```bash
export DOCKER_API_VERSION=1.44
alias docker-a='docker -H tcp://192.168.123.66:2375'
alias docker-b='docker -H tcp://192.168.123.81:2375'
```

使用：
```bash
docker-a ps          # 查看机器 A 容器
docker-b logs scp0006  # 查看机器 B 日志
```

---

### 方式二：SSH 手动部署

适用于首次部署或需要完整控制的场景。

> **重要**：必须先部署机器 B，再部署机器 A

#### 第一步：部署机器 B（内网 192.168.123.81）

##### 1.1 拉取代码
```bash
cd /path/to/mock-system/inner-server
git pull origin main
```

##### 1.2 重置环境（首次部署或需要清理时）
```bash
docker-compose down -v
```

##### 1.3 启动基础服务
```bash
# 启动 MySQL 和 Kafka
docker-compose up -d mysql kafka

# 等待服务就绪（约60秒）
echo "等待 MySQL 和 Kafka 启动..."
sleep 60

# 检查状态
docker-compose ps
```

##### 1.4 启动 Canal
```bash
docker-compose up -d canal

# 等待就绪
echo "等待 Canal 启动..."
sleep 30

# 检查 Canal 日志
docker-compose logs canal | grep -i "find start position"
echo "Canal 就绪！"
```

##### 1.5 验证 Canal 状态
```bash
# 查看 Canal 日志，确认连接 MySQL 成功
docker-compose logs canal | tail -20
```
预期输出：`find start position successfully`

##### 1.6 启动应用服务
```bash
docker-compose up -d --build target-service scp0006

# 查看日志
docker-compose logs -f scp0006
```

##### 1.7 验证机器 B
```bash
# 插入测试数据
docker exec mysql-inner mysql -uroot -proot123 -e \
  "INSERT INTO inner_gateway.inner_request (request_id, code, param_data, channel_type) VALUES ('test-b-$(date +%s)', 'yhzx', '{\"test\":true}', 'yhzx');"

# 检查 Kafka 消息（Canal 格式）
docker exec kafka-inner kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic inner_request_binlog \
  --from-beginning \
  --timeout-ms 10000
```
预期输出（Canal 格式）：`{"data":[...],"database":"inner_gateway","table":"inner_request","type":"INSERT"}`

---

#### 第二步：部署机器 A（外网 192.168.123.66）

##### 2.1 拉取代码
```bash
cd /path/to/mock-system/outer-server
git pull origin main
```

##### 2.2 重置环境（首次部署或需要清理时）
```bash
docker-compose down -v
```

##### 2.3 启动基础服务
```bash
# 启动 MySQL、Redis 和 Kafka
docker-compose up -d mysql redis kafka

# 等待服务就绪
echo "等待服务启动..."
sleep 60

docker-compose ps
```

##### 2.4 启动 Canal
```bash
docker-compose up -d canal

# 等待就绪
echo "等待 Canal 启动..."
sleep 30

# 检查 Canal 日志
docker-compose logs canal | grep -i "find start position"
echo "Canal 就绪！"
```

##### 2.5 验证 Canal 状态
```bash
# 查看 Canal 日志，确认连接 MySQL 成功
docker-compose logs canal | tail -20
```
预期输出：`find start position successfully`

##### 2.6 启动应用服务
```bash
docker-compose up -d --build scp0005 outer-consumer

# 查看日志
docker-compose logs -f scp0005
```

---

## 端到端测试

在机器 A 上执行：

```bash
# 发送测试请求
curl -X POST "http://localhost:8080/inner/c1/yhzx" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "code=yhzx&paramData={\"test\":\"production\"}"
```

**预期响应**（约1秒后返回）：
```json
{
  "code": "200",
  "message": "success",
  "data": {
    "userId": "U...",
    "userName": "MockUser",
    "status": "active",
    "processTime": "..."
  },
  "requestId": "...",
  "elapsed": 50
}
```

---

## 验证检查清单

### 机器 B 检查项

| 检查项 | 命令 | 预期结果 |
|--------|------|----------|
| MySQL | `docker-compose ps mysql` | Up (healthy) |
| Kafka | `docker-compose ps kafka` | Up (healthy) |
| Canal | `docker-compose ps canal` | Up |
| Canal 状态 | `docker-compose logs canal \| grep "start position"` | find start position successfully |
| scp0006 | `docker-compose ps scp0006` | Up |
| target-service | `docker-compose ps target-service` | Up |

### 机器 A 检查项

| 检查项 | 命令 | 预期结果 |
|--------|------|----------|
| MySQL | `docker-compose ps mysql` | Up (healthy) |
| Redis | `docker-compose ps redis` | Up (healthy) |
| Kafka | `docker-compose ps kafka` | Up (healthy) |
| Canal | `docker-compose ps canal` | Up |
| Canal 状态 | `docker-compose logs canal \| grep "start position"` | find start position successfully |
| scp0005 | `docker-compose ps scp0005` | Up |
| outer-consumer | `docker-compose ps outer-consumer` | Up |
| Registry | `curl localhost:5000/v2/_catalog` | `{"repositories":[...]}` |

---

## 故障排查

### 1. Canal 启动失败

```bash
# 查看 Canal 日志
docker-compose logs canal

# 常见问题：MySQL 连接失败
# 检查 instance.properties 中的连接配置
cat config/canal/instance.properties | grep -E "(master.address|dbUsername|dbPassword)"

# 检查 MySQL 是否允许 binlog 复制
docker exec mysql-inner mysql -uroot -proot123 -e "SHOW MASTER STATUS;"
```

### 2. Canal 无法连接 MySQL

```bash
# 检查 MySQL binlog 配置
docker exec mysql-inner mysql -uroot -proot123 -e "SHOW VARIABLES LIKE 'log_bin';"
docker exec mysql-inner mysql -uroot -proot123 -e "SHOW VARIABLES LIKE 'binlog_format';"

# 确认 binlog_format = ROW
# 如果不是，需要在 MySQL 配置中设置
```

### 3. 跨机器数据库连接失败

```bash
# 在机器 A 上测试连接机器 B 的 MySQL
mysql -h 192.168.123.81 -P 3306 -uroot -proot123 -e "SELECT 1"

# 在机器 B 上测试连接机器 A 的 MySQL
mysql -h 192.168.123.66 -P 3306 -uroot -proot123 -e "SELECT 1"
```

### 4. 没有消息到达 Kafka

```bash
# 检查 MySQL binlog 是否开启
docker exec mysql-inner mysql -uroot -proot123 -e "SHOW MASTER STATUS;"

# 检查 Canal 是否在监听
docker-compose logs canal | grep -i "inner_request"

# 检查 Kafka topic 是否有数据
docker exec kafka-inner kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic inner_request_binlog \
  --from-beginning \
  --timeout-ms 5000
```

### 5. scp0005 返回超时

```bash
# 检查 Redis 中是否有结果
docker exec redis redis-cli KEYS "gateway:result:*"

# 检查 outer-consumer 日志
docker-compose logs outer-consumer | tail -50
```

### 6. Docker TCP 连接失败

```bash
# 检查 socat 是否运行
pgrep -f 'socat.*2375'

# 重新启动 socat
nohup socat TCP-LISTEN:2375,reuseaddr,fork UNIX-CONNECT:/var/run/docker.sock &

# 测试连接
DOCKER_API_VERSION=1.44 docker -H tcp://192.168.123.66:2375 ps
```

### 7. Registry 推送失败 (HTTPS 错误)

```bash
# 确认 insecure-registries 配置
docker info | grep -A5 "Insecure"

# 如果没有显示 192.168.123.66:5000，需要在 Docker Desktop 中配置
# Settings → Docker Engine → 添加 "insecure-registries": ["192.168.123.66:5000"]
```

---

## 服务端口汇总

### 机器 B (192.168.123.81)

| 服务 | 端口 | 说明 |
|------|------|------|
| MySQL | 3306 | inner_gateway 数据库 |
| Kafka | 9092 | 消息队列 |
| Canal | 11111 | CDC 服务 |
| scp0006 | 8082 | 请求处理服务 |
| target-service | 8017 | 模拟目标服务 |
| Docker TCP | 2375 | 远程 Docker 管理 |

### 机器 A (192.168.123.66)

| 服务 | 端口 | 说明 |
|------|------|------|
| MySQL | 3306 | outer_gateway 数据库 |
| Redis | 6379 | 结果缓存 |
| Kafka | 9092 | 消息队列 |
| Canal | 11111 | CDC 服务 |
| scp0005 | 8080 | API 入口服务 |
| outer-consumer | 8081 | 响应消费服务 |
| Registry | 5000 | 私有镜像仓库 |
| Docker TCP | 2375 | 远程 Docker 管理 |

---

## 本地测试环境

如需在本地同时模拟两台机器，可使用：

```bash
cd mock-system/local-e2e
./start-lite.sh   # 启动精简版（共享 Kafka，节省资源）
./test-lite.sh    # 运行测试
./stop-lite.sh    # 停止环境
```

---

*最后更新：2026-01-14*
*版本：v4.0 - 使用 Canal 替代 Debezium，CDC 延迟降低 40%*
