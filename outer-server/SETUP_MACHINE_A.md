# 机器 A（外网）部署指令

## AI 助手执行说明

本文档是给 AI 助手（Claude Code / Cursor / Gemini）的执行指令。
请按照步骤顺序执行，每个步骤都要验证成功后再继续下一步。

---

## 第一步：检查环境

### 1.1 检查 Docker 是否安装

```bash
docker --version
docker-compose --version
```

**预期输出**：显示 Docker 版本号

**如果未安装**：
- 请用户手动安装 Docker Desktop for Mac
- 下载地址：https://www.docker.com/products/docker-desktop
- 安装后重新执行此步骤

### 1.2 获取本机 IP 地址

```bash
# macOS
ipconfig getifaddr en0 || ipconfig getifaddr en1

# 或者使用
ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}'
```

**记录本机 IP**：`__MACHINE_A_IP__`（例如：192.168.1.100）

### 1.3 询问机器 B 的 IP 地址

**需要用户提供**：机器 B（内网）的 IP 地址 `__MACHINE_B_IP__`

---

## 第二步：准备配置文件

### 2.1 进入项目目录

```bash
cd $(dirname "$0")  # 当前目录
# 或者
# cd /path/to/mock-system/outer-server
```

### 2.2 替换 IP 地址

将 `docker-compose.yml` 中的 IP 占位符替换为实际 IP：

```bash
# 替换机器 A 的 IP
sed -i '' "s/__MACHINE_A_IP__/实际的机器A_IP/g" docker-compose.yml

# 替换机器 B 的 IP
sed -i '' "s/__MACHINE_B_IP__/实际的机器B_IP/g" docker-compose.yml
```

**示例**（假设机器 A IP 是 192.168.1.100，机器 B IP 是 192.168.1.101）：
```bash
sed -i '' "s/__MACHINE_A_IP__/192.168.1.100/g" docker-compose.yml
sed -i '' "s/__MACHINE_B_IP__/192.168.1.101/g" docker-compose.yml
```

### 2.3 同样替换 Canal 配置

```bash
sed -i '' "s/__MACHINE_A_IP__/实际的机器A_IP/g" config/canal/instance.properties
```

---

## 第三步：启动基础设施

### 3.1 启动 MySQL、Redis、Kafka、Canal

```bash
docker-compose up -d mysql redis kafka canal
```

### 3.2 等待服务启动完成（约 30 秒）

```bash
sleep 30
```

### 3.3 验证服务状态

```bash
docker-compose ps
```

**预期输出**：所有服务状态为 `Up`

### 3.4 验证 MySQL 连接

```bash
docker exec -it mysql-outer mysql -uroot -proot123 -e "SHOW DATABASES;"
```

**预期输出**：显示数据库列表，包含 `outer_gateway`

### 3.5 验证 Redis 连接

```bash
docker exec -it redis redis-cli ping
```

**预期输出**：`PONG`

### 3.6 验证 Kafka

```bash
docker exec -it kafka kafka-topics.sh --bootstrap-server localhost:9092 --list
```

**预期输出**：空列表或已有 topic 列表（无报错即可）

---

## 第四步：创建 Kafka Topic

```bash
# 创建内网请求 topic
docker exec -it kafka kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic inner_request_binlog --partitions 3 --replication-factor 1

# 创建外网响应 topic
docker exec -it kafka kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic outer_response_binlog --partitions 3 --replication-factor 1
```

### 验证 Topic 创建成功

```bash
docker exec -it kafka kafka-topics.sh --bootstrap-server localhost:9092 --list
```

**预期输出**：
```
inner_request_binlog
outer_response_binlog
```

---

## 第五步：验证跨机器连通性

### 5.1 测试能否连接机器 B 的 MySQL

**注意**：这一步需要在机器 B 启动 MySQL 后执行

```bash
# 测试网络连通
nc -zv __MACHINE_B_IP__ 3306

# 或者使用 telnet
telnet __MACHINE_B_IP__ 3306
```

**预期输出**：连接成功

**如果连接失败**：
- 检查机器 B 是否已启动 MySQL
- 检查机器 B 的防火墙设置
- 检查两台机器是否在同一网络

---

## 第六步：检查清单

请确认以下所有项目都已完成：

- [x] Docker 已安装并运行
- [x] 已获取本机 IP 地址
- [x] 已获取机器 B 的 IP 地址
- [x] 已替换配置文件中的 IP 占位符
- [x] MySQL 已启动并可连接
- [x] Redis 已启动并可连接
- [x] Kafka 已启动
- [x] Canal 已启动
- [x] Kafka Topic 已创建

---

## 第七步：等待机器 B 部署完成

在继续下一步之前，请确保机器 B 已完成基础设施部署。

可以通过以下命令测试机器 B 的 MySQL：

```bash
mysql -h __MACHINE_B_IP__ -P 3306 -uroot -proot123 -e "SHOW DATABASES;"
```

**预期输出**：显示数据库列表，包含 `inner_gateway`

---

## 第八步：启动应用服务（待后续补充）

应用服务代码开发完成后，执行：

```bash
docker-compose up -d scp0005 outer-consumer
```

---

## 故障排查

### MySQL 无法启动
```bash
docker-compose logs mysql
```

### Kafka 无法启动
```bash
docker-compose logs kafka
```

### Canal 无法启动
```bash
docker-compose logs canal
```

### 跨机器 MySQL 连接失败
1. 检查 MySQL 是否允许远程连接
2. 检查防火墙设置
3. 检查 Docker 网络配置

---

## 完成标志

当看到以下输出时，表示机器 A 基础设施部署完成：

```bash
docker-compose ps
```

```
NAME           STATUS    PORTS
mysql-outer    Up        0.0.0.0:3306->3306/tcp
redis          Up        0.0.0.0:6379->6379/tcp
kafka          Up        0.0.0.0:9092->9092/tcp
canal-outer    Up        0.0.0.0:11111->11111/tcp
```

**状态**：✅ 机器 A 基础设施部署完成

---

## 执行日志和状态

**状态**: 所有步骤已成功完成。机器 A 基础设施已根据本文档部署和验证完毕。

**关键信息**:
- **机器 A IP 地址**: `192.168.123.66`
- **机器 B IP 地址**: `192.168.123.65`

**执行摘要**:
1.  **环境检查**: 成功。Docker 已安装。
2.  **配置文件**: 成功。`docker-compose.yml` 中的 `__MACHINE_A_IP__` 已被替换。`config/canal/instance.properties` 无需更改。
3.  **启动基础设施**: 成功。所有服务（MySQL, Redis, Kafka, Canal）已启动并运行。
    - **问题排查**:
        - **Kafka 镜像问题**: `bitnami/kafka:3.5` 镜像无法找到。已将其替换为 `apache/kafka:latest`。
        - **Kafka 配置问题**: `apache/kafka` 镜像需要不同的环境变量格式。已更新 `docker-compose.yml` 以使用正确的环境变量名称（例如 `KAFKA_NODE_ID`）和格式（从列表更改为映射）。
4.  **创建 Kafka Topic**: 成功。`inner_request_binlog` 和 `outer_response_binlog` 已创建并验证。
5.  **跨机器连通性**: 成功。已从机器 A 的 `mysql-outer` 容器成功连接到机器 B 的 MySQL，并查询了 `inner_gateway.inner_request` 表。

**结论**: 机器 A 准备就绪。
