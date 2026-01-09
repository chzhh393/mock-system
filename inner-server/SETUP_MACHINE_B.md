# 机器 B（内网）部署指令

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

**记录本机 IP**：`__MACHINE_B_IP__`（例如：192.168.1.101）

### 1.3 询问机器 A 的 IP 地址

**需要用户提供**：机器 A（外网）的 IP 地址 `__MACHINE_A_IP__`

---

## 第二步：准备配置文件

### 2.1 进入项目目录

```bash
cd $(dirname "$0")  # 当前目录
# 或者
# cd /path/to/mock-system/inner-server
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
sed -i '' "s/__MACHINE_B_IP__/实际的机器B_IP/g" config/canal/instance.properties
```

---

## 第三步：启动基础设施

### 3.1 启动 MySQL、Canal

```bash
docker-compose up -d mysql canal
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
docker exec -it mysql-inner mysql -uroot -proot123 -e "SHOW DATABASES;"
```

**预期输出**：显示数据库列表，包含 `inner_gateway`

### 3.5 验证请求表已创建

```bash
docker exec -it mysql-inner mysql -uroot -proot123 -e "USE inner_gateway; SHOW TABLES;"
```

**预期输出**：显示 `inner_request` 表

---

## 第四步：配置 MySQL 允许远程连接

### 4.1 创建远程访问用户

```bash
docker exec -it mysql-inner mysql -uroot -proot123 -e "
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root123';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
"
```

### 4.2 验证远程访问配置

```bash
docker exec -it mysql-inner mysql -uroot -proot123 -e "SELECT user, host FROM mysql.user WHERE user='root';"
```

**预期输出**：应该有 `root @ %` 的记录

---

## 第五步：验证跨机器连通性

### 5.1 测试能否连接机器 A 的 Kafka

**注意**：这一步需要在机器 A 启动 Kafka 后执行

```bash
# 测试网络连通
nc -zv __MACHINE_A_IP__ 9092

# 或者使用 telnet
telnet __MACHINE_A_IP__ 9092
```

**预期输出**：连接成功

### 5.2 测试能否连接机器 A 的 MySQL

```bash
nc -zv __MACHINE_A_IP__ 3306
```

**预期输出**：连接成功

**如果连接失败**：
- 检查机器 A 是否已启动对应服务
- 检查机器 A 的防火墙设置
- 检查两台机器是否在同一网络

---

## 第六步：检查清单

请确认以下所有项目都已完成：

- [x] Docker 已安装并运行
- [x] 已获取本机 IP 地址
- [x] 已获取机器 A 的 IP 地址
- [x] 已替换配置文件中的 IP 占位符
- [x] MySQL 已启动并可连接
- [x] 请求表（inner_request）已创建
- [x] MySQL 已配置允许远程连接
- [x] Canal 已启动
- [x] 可以连接到机器 A 的 Kafka (9092)
- [x] 可以连接到机器 A 的 MySQL (3306)

---

## 第七步：验证机器 A 能连接本机 MySQL

请在机器 A 上执行以下命令验证：

```bash
mysql -h __MACHINE_B_IP__ -P 3306 -uroot -proot123 -e "USE inner_gateway; SELECT COUNT(*) FROM inner_request;"
```

**预期输出**：`COUNT(*) = 0`（表存在，数据为空）

---

## 第八步：启动应用服务（待后续补充）

应用服务代码开发完成后，执行：

```bash
docker-compose up -d scp0006 target-service
```

---

## 故障排查

### MySQL 无法启动
```bash
docker-compose logs mysql
```

### Canal 无法启动
```bash
docker-compose logs canal
```

### MySQL 远程连接失败
1. 检查是否执行了步骤 4（创建远程用户）
2. 检查 MySQL 配置是否允许远程连接
3. 检查防火墙设置

### Canal 无法连接 Kafka
1. 检查机器 A 的 Kafka 是否启动
2. 检查 `instance.properties` 中的 Kafka 地址是否正确
3. 检查网络连通性

---

## 完成标志

当看到以下输出时，表示机器 B 基础设施部署完成：

```bash
docker-compose ps
```

```
NAME           STATUS    PORTS
mysql-inner    Up        0.0.0.0:3306->3306/tcp
canal-inner    Up        0.0.0.0:11111->11111/tcp
```

**状态**：✅ 机器 B 基础设施部署完成
