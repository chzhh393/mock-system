# 环境预配置文档

> **说明**: 本文档包含沙箱任务执行前需要手动完成的环境配置步骤。
>
> **重要**: 必须先部署机器 B，再部署机器 A（因为机器 A 的 scp0005 需要连接机器 B 的 MySQL）

---

## 网络信息

| 机器 | 角色 | IP 地址 |
|------|------|---------|
| 机器 A | 外网 | 192.168.123.66 |
| 机器 B | 内网 | 192.168.123.81 |

---

## 零、关键配置说明

> **已修复**: Kafka 的 `advertised.listeners` 已配置为 IP 地址，支持跨机器通信。
>
> 如果使用 `docker-compose up` 启动服务，无需额外配置。
>
> **注意**: 如果通过远程 Docker API 单独启动容器（而非 docker-compose up），需要使用 IP 地址。

### 0.1 当前 Kafka 配置（已正确配置）

**机器 A** (`outer-server/docker-compose.yml`):
```yaml
KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://192.168.123.66:9092
```

**机器 B** (`inner-server/docker-compose.yml`):
```yaml
KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://192.168.123.81:9092
```

### 0.2 单独启动容器时的环境变量

如果通过远程 Docker API 单独启动容器，需要使用 IP 地址替代容器名：

**scp0005 / outer-consumer**（机器 A）：
```bash
-e REDIS_HOST=192.168.123.66 \
-e KAFKA_BOOTSTRAP=192.168.123.66:9092
```

**scp0006**（机器 B）：
```bash
-e KAFKA_BOOTSTRAP=192.168.123.81:9092
```

---

## 一、机器 B (192.168.123.81) 配置

### 1.1 启动基础服务

```bash
cd /home/ubuntu/mock-system/inner-server

# 1. 启动 MySQL 和 Kafka
docker-compose up -d mysql kafka

# 2. 等待服务就绪（约60秒）
sleep 60

# 3. 验证 MySQL
docker exec -it mysql-inner mysql -uroot -proot123 -e "SHOW DATABASES;"
# 预期输出: 包含 inner_gateway

# 4. 验证请求表
docker exec -it mysql-inner mysql -uroot -proot123 -e "USE inner_gateway; SHOW TABLES;"
# 预期输出: inner_request

# 5. 启动 Canal (CDC)
docker-compose up -d canal

# 6. 等待 Canal 就绪（约30秒）
sleep 30

# 7. 验证 Canal 状态
docker-compose logs canal | grep -i "find start position"
# 预期输出: find start position successfully
```

### 1.2 启动应用服务

```bash
cd /home/ubuntu/mock-system/inner-server

# 构建并启动应用服务
docker-compose up -d --build target-service scp0006

# 验证服务状态
docker-compose ps
# 预期: 所有服务状态为 Up
```

### 1.3 验证机器 B 完整性

```bash
# 检查所有服务状态
docker-compose ps

# 预期输出:
# NAME              STATUS    PORTS
# mysql-inner       Up        0.0.0.0:3306->3306/tcp
# kafka-inner       Up        0.0.0.0:9092->9092/tcp
# canal-inner       Up        0.0.0.0:11111->11111/tcp
# scp0006           Up        0.0.0.0:8082->8082/tcp
# target-service    Up        0.0.0.0:8083->8083/tcp
```

---

## 二、机器 A (192.168.123.66) 配置

### 2.1 启动基础服务

```bash
cd /home/ubuntu/mock-system/outer-server

# 1. 启动 MySQL、Redis 和 Kafka
docker-compose up -d mysql redis kafka

# 2. 等待服务就绪（约60秒）
sleep 60

# 3. 验证 MySQL
docker exec -it mysql-outer mysql -uroot -proot123 -e "SHOW DATABASES;"
# 预期输出: 包含 outer_gateway

# 4. 验证 Redis
docker exec -it redis redis-cli ping
# 预期输出: PONG

# 5. 启动 Canal (CDC)
docker-compose up -d canal

# 6. 等待 Canal 就绪（约30秒）
sleep 30

# 7. 验证 Canal 状态
docker-compose logs canal | grep -i "find start position"
# 预期输出: find start position successfully

# 8. 创建 Kafka Topic（如果不存在）
docker exec -it kafka kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic inner_request_binlog --partitions 3 --replication-factor 1 --if-not-exists

docker exec -it kafka kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic outer_response_binlog --partitions 3 --replication-factor 1 --if-not-exists

# 9. 验证 Topic
docker exec -it kafka kafka-topics.sh --bootstrap-server localhost:9092 --list
# 预期输出: inner_request_binlog, outer_response_binlog
```

### 2.2 启动应用服务

```bash
cd /home/ubuntu/mock-system/outer-server

# 构建并启动应用服务
docker-compose up -d --build scp0005 outer-consumer

# 验证服务状态
docker-compose ps
# 预期: 所有服务状态为 Up
```

### 2.3 验证机器 A 完整性

```bash
# 检查所有服务状态
docker-compose ps

# 预期输出:
# NAME              STATUS    PORTS
# mysql-outer       Up        0.0.0.0:3306->3306/tcp
# redis             Up        0.0.0.0:6379->6379/tcp
# kafka             Up        0.0.0.0:9092->9092/tcp
# canal-outer       Up        0.0.0.0:11111->11111/tcp
# scp0005           Up        0.0.0.0:8080->8080/tcp
# outer-consumer    Up        0.0.0.0:8081->8081/tcp
```

---

## 三、端到端验证

### 3.1 基础连通性验证

```bash
# 从机器 A 测试连接机器 B 的 MySQL
mysql -h 192.168.123.81 -P 3306 -uroot -proot123 -e "SELECT 1"

# 从机器 B 测试连接机器 A 的 MySQL
mysql -h 192.168.123.66 -P 3306 -uroot -proot123 -e "SELECT 1"
```

### 3.2 API 端到端测试

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

### 3.3 数据流验证

```bash
# 检查机器 B 的 Kafka 消息（Canal 格式）
docker exec kafka-inner kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic inner_request_binlog \
  --from-beginning \
  --timeout-ms 10000

# 检查机器 A 的 Redis 结果缓存
docker exec redis redis-cli KEYS "gateway:result:*"
```

---

## 四、压测工具和依赖安装

### 4.1 安装 wrk

**macOS:**
```bash
brew install wrk
```

**Ubuntu/Debian (沙箱环境):**
```bash
# 方式1: 使用 apt（如果有）
sudo apt-get update && sudo apt-get install -y wrk

# 方式2: 从源码编译
sudo apt-get install -y build-essential libssl-dev git
git clone https://github.com/wg/wrk.git
cd wrk && make && sudo cp wrk /usr/local/bin/
```

**验证安装:**
```bash
wrk --version
```

### 4.2 安装其他依赖工具（沙箱环境）

```bash
# jq - JSON 处理工具
sudo apt-get install -y jq || (wget -O /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && chmod +x /usr/local/bin/jq)

# unzip - 解压工具
sudo apt-get install -y unzip

# curl - HTTP 客户端（通常已预装）
sudo apt-get install -y curl

# nc (netcat) - 网络连通性测试
sudo apt-get install -y netcat-openbsd
```

### 4.3 运行压测

```bash
cd /home/ubuntu/mock-system/perf-test

# 默认压测（2线程，10并发，30秒）
./run-test.sh

# 自定义参数压测
THREADS=4 CONNECTIONS=20 DURATION=60s ./run-test.sh

# 指定目标地址
TARGET_URL=http://192.168.123.66:8080/inner/c1/yhzx ./run-test.sh
```

### 4.4 压测结果指标说明

| 指标 | 说明 |
|------|------|
| Requests/sec | TPS（每秒请求数） |
| Latency avg | 平均延迟 |
| Latency 99% | P99 延迟 |
| Non-2xx | 错误请求数 |

---

## 五、故障排查

### 5.1 服务无法启动

```bash
# 查看详细日志
docker-compose logs <service-name>

# 例如
docker-compose logs mysql
docker-compose logs canal
docker-compose logs scp0005
```

### 5.2 Canal 连接失败

```bash
# 检查 MySQL binlog 配置
docker exec mysql-inner mysql -uroot -proot123 -e "SHOW VARIABLES LIKE 'log_bin';"
docker exec mysql-inner mysql -uroot -proot123 -e "SHOW VARIABLES LIKE 'binlog_format';"
# binlog_format 应该是 ROW

# 检查 Master 状态
docker exec mysql-inner mysql -uroot -proot123 -e "SHOW MASTER STATUS;"
```

### 5.3 跨机器连接失败

```bash
# 测试网络连通性
nc -zv 192.168.123.81 3306  # 从机器 A 测试机器 B 的 MySQL
nc -zv 192.168.123.66 9092  # 从机器 B 测试机器 A 的 Kafka

# 检查防火墙设置
# 确保端口 3306, 6379, 9092, 11111, 8080, 8081, 8082, 8017 开放
```

### 5.4 请求超时

```bash
# 检查 Redis 中是否有结果
docker exec redis redis-cli KEYS "gateway:result:*"

# 检查 outer-consumer 日志
docker-compose logs outer-consumer | tail -50

# 检查数据是否写入成功
docker exec mysql-inner mysql -uroot -proot123 -e "SELECT COUNT(*) FROM inner_gateway.inner_request;"
```

### 5.5 Kafka 连接失败（常见问题）

**症状**: scp0006 日志显示 `Connection to kafka:9092 refused` 或类似错误

**原因**: Kafka 的 `advertised.listeners` 配置为容器名而非 IP 地址

**解决方案**:
```bash
# 1. 修改 docker-compose.yml 中的 Kafka 配置
# 将 KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
# 改为 KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://192.168.123.81:9092（机器B）
#    或 KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://192.168.123.66:9092（机器A）

# 2. 重启 Kafka
docker-compose restart kafka

# 3. 验证 Kafka 可达
nc -zv 192.168.123.81 9092
```

### 5.6 Redis 连接失败

**症状**: scp0005 日志显示 `Unable to connect to Redis; nested exception is ...`

**原因**: 容器使用 `redis` 作为主机名，但不在同一 Docker 网络中

**解决方案**:
```bash
# 方式1: 确保使用 docker-compose 启动（推荐）
docker-compose up -d

# 方式2: 单独启动时使用 IP 地址
docker run -d --name scp0005 \
  -e REDIS_HOST=192.168.123.66 \
  -e REDIS_PORT=6379 \
  ... 其他参数
```

### 5.7 应用服务无法解析容器名

**症状**: `UnknownHostException: kafka` 或 `Unknown host: redis`

**原因**: 通过远程 Docker API 单独启动的容器不在 docker-compose 创建的网络中

**解决方案**:
```bash
# 方式1: 使用 docker-compose 启动所有服务
cd /home/ubuntu/mock-system/outer-server
docker-compose up -d

# 方式2: 将单独启动的容器加入网络
docker network connect outer-server_outer_net scp0005

# 方式3: 启动时指定网络
docker run -d --name scp0005 --network outer-server_outer_net ...
```

---

## 六、服务端口汇总

### 机器 B (192.168.123.81)

| 服务 | 端口 | 说明 |
|------|------|------|
| MySQL | 3306 | inner_gateway 数据库 |
| Kafka | 9092 | 消息队列 |
| Canal | 11111 | CDC 服务 |
| scp0006 | 8082 | 请求处理服务 |
| target-service | 8083 | 模拟目标服务 |

### 机器 A (192.168.123.66)

| 服务 | 端口 | 说明 |
|------|------|------|
| MySQL | 3306 | outer_gateway 数据库 |
| Redis | 6379 | 结果缓存 |
| Kafka | 9092 | 消息队列 |
| Canal | 11111 | CDC 服务 |
| scp0005 | 8080 | API 入口服务 |
| outer-consumer | 8081 | 响应消费服务 |

---

## 七、deploy-registry.sh 部署后的必要配置

> **重要**: 使用 `deploy-registry.sh` 部署应用服务后，需要手动执行以下配置才能正常工作。

### 7.1 Docker 网络配置

通过 `deploy-registry.sh` 部署的容器默认在 `bridge` 网络，无法解析 docker-compose 创建的服务名。

**机器 A (192.168.123.66)**:
```bash
export DOCKER_API_VERSION=1.44

# 将应用服务加入 outer_net 网络
docker -H tcp://192.168.123.66:2375 network connect outer-server_outer_net scp0005
docker -H tcp://192.168.123.66:2375 network connect outer-server_outer_net outer-consumer
```

**机器 B (192.168.123.81)**:
```bash
export DOCKER_API_VERSION=1.44

# 将应用服务加入 inner_net 网络
docker -H tcp://192.168.123.81:2375 network connect inner-server_inner_net scp0006
docker -H tcp://192.168.123.81:2375 network connect inner-server_inner_net target-service
```

### 7.2 机器 A Canal 配置修复

Canal 默认配置需要多处修改：

```bash
export DOCKER_API_VERSION=1.44

# 1. 切换到 Kafka 模式（默认是 tcp）
docker -H tcp://192.168.123.66:2375 exec canal-outer sed -i 's|canal.serverMode = tcp|canal.serverMode = kafka|g' /home/admin/canal-server/conf/canal.properties

# 2. 配置 Kafka 地址
docker -H tcp://192.168.123.66:2375 exec canal-outer sed -i 's|kafka.bootstrap.servers = 127.0.0.1:9092|kafka.bootstrap.servers = 192.168.123.66:9092|g' /home/admin/canal-server/conf/canal.properties

# 3. 配置 MySQL 连接地址
docker -H tcp://192.168.123.66:2375 exec canal-outer sed -i 's|canal.instance.master.address=127.0.0.1:3306|canal.instance.master.address=192.168.123.66:3306|g' /home/admin/canal-server/conf/example/instance.properties

# 4. 配置监听表（只监听 outer_response）
docker -H tcp://192.168.123.66:2375 exec canal-outer sed -i 's|canal.instance.filter.regex=.*\\..*|canal.instance.filter.regex=outer_gateway\\.outer_response|g' /home/admin/canal-server/conf/example/instance.properties

# 5. 配置 Kafka Topic
docker -H tcp://192.168.123.66:2375 exec canal-outer sed -i 's|canal.mq.topic=example|canal.mq.topic=outer_response_binlog|g' /home/admin/canal-server/conf/example/instance.properties

# 6. 配置数据库密码
docker -H tcp://192.168.123.66:2375 exec canal-outer sed -i 's|canal.instance.dbPassword=canal$|canal.instance.dbPassword=canal123|g' /home/admin/canal-server/conf/example/instance.properties

# 7. 重启 Canal
docker -H tcp://192.168.123.66:2375 restart canal-outer
```

### 7.3 机器 A MySQL 配置

```bash
export DOCKER_API_VERSION=1.44

# 1. 创建 outer_response 表（如果不存在）
docker -H tcp://192.168.123.66:2375 exec mysql-outer mysql -uroot -proot123 -e "
USE outer_gateway;
CREATE TABLE IF NOT EXISTS outer_response (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    request_id VARCHAR(64) NOT NULL,
    response_data TEXT,
    response_code VARCHAR(10) DEFAULT '0000',
    error_msg VARCHAR(500),
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_request_id (request_id),
    INDEX idx_create_time (create_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
"

# 2. 创建 Canal 用户
docker -H tcp://192.168.123.66:2375 exec mysql-outer mysql -uroot -proot123 -e "
CREATE USER IF NOT EXISTS 'canal'@'%' IDENTIFIED BY 'canal123';
GRANT SELECT, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'canal'@'%';
FLUSH PRIVILEGES;
"
```

### 7.4 验证部署后配置

```bash
export DOCKER_API_VERSION=1.44

# 验证网络配置
echo "=== 机器 A 网络 ==="
docker -H tcp://192.168.123.66:2375 inspect scp0005 --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}'
docker -H tcp://192.168.123.66:2375 inspect outer-consumer --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}'

echo "=== 机器 B 网络 ==="
docker -H tcp://192.168.123.81:2375 inspect scp0006 --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}'
docker -H tcp://192.168.123.81:2375 inspect target-service --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}'

# 验证 Canal 配置
echo "=== Canal-outer 配置 ==="
docker -H tcp://192.168.123.66:2375 exec canal-outer grep -E "(serverMode|kafka.bootstrap|master.address|filter.regex|mq.topic)" /home/admin/canal-server/conf/canal.properties /home/admin/canal-server/conf/example/instance.properties 2>/dev/null

# 端到端测试
curl -s -X POST "http://192.168.123.66:8080/inner/c1/yhzx" -H "Content-Type: application/x-www-form-urlencoded" -d "code=yhzx&paramData={\"test\":\"verify\"}"
```

---

## 八、一键启动脚本（可选）

如果脚本已配置好 IP 地址，可以使用一键启动：

### 机器 B
```bash
cd /home/ubuntu/mock-system/inner-server
./scripts/start.sh
```

### 机器 A
```bash
cd /home/ubuntu/mock-system/outer-server
./scripts/start.sh
```

---

*最后更新：2026-01-16*
