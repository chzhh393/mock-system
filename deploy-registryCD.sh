#!/bin/bash
#
# 机器C/D 部署脚本
#
# 环境:
#   机器C（外网）: 192.168.123.113 - 部署 outer-server (scp0005, outer-consumer, MySQL, Redis, Kafka, Canal)
#   机器D（内网）: 192.168.123.114 - 部署 inner-server (scp0006, target-service, MySQL, Kafka, Canal)
#
# 使用方法:
#   ./deploy-registryCD.sh init       # 首次部署：启动基础设施 + Registry
#   ./deploy-registryCD.sh all        # 部署所有应用服务
#   ./deploy-registryCD.sh outer      # 只部署机器 C 的服务
#   ./deploy-registryCD.sh inner      # 只部署机器 D 的服务
#   ./deploy-registryCD.sh status     # 查看服务状态
#   ./deploy-registryCD.sh test       # 运行端到端测试
#   ./deploy-registryCD.sh socat      # 启动两台机器的 Docker API 转发
#   ./deploy-registryCD.sh stop       # 停止所有服务
#

set -e

# ==================== 配置 ====================
# 机器C (外网) - 相当于原来的机器A
MACHINE_C_IP="192.168.123.113"
MACHINE_C="tcp://${MACHINE_C_IP}:2375"
MACHINE_C_USER="jirenhe"
MACHINE_C_PASS="123456"

# 机器D (内网) - 相当于原来的机器B
MACHINE_D_IP="192.168.123.114"
MACHINE_D="tcp://${MACHINE_D_IP}:2375"
MACHINE_D_USER="admin"
MACHINE_D_PASS="123456"

# Registry 在机器C上
REGISTRY="${MACHINE_C_IP}:5000"

# Docker 网络名称
OUTER_NET="outer_net"
INNER_NET="inner_net"

# 设置 Docker API 版本
export DOCKER_API_VERSION=1.44

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# SSH 命令封装
ssh_c() {
    sshpass -p "$MACHINE_C_PASS" ssh -o PreferredAuthentications=password -o StrictHostKeyChecking=no "$MACHINE_C_USER@$MACHINE_C_IP" "$@"
}

ssh_d() {
    sshpass -p "$MACHINE_D_PASS" ssh -o PreferredAuthentications=password -o StrictHostKeyChecking=no "$MACHINE_D_USER@$MACHINE_D_IP" "$@"
}

copy_canal_configs_c() {
    log_info "将本地 Canal 配置文件复制到远程机器 C..."
    ssh_c "mkdir -p /tmp/mock-system/outer-server/config/"
    sshpass -p "$MACHINE_C_PASS" scp -r -o StrictHostKeyChecking=no "./outer-server/config/canal" "$MACHINE_C_USER@$MACHINE_C_IP:/tmp/mock-system/outer-server/config/"
    log_info "机器C Canal 配置文件复制完成"
}

copy_canal_configs_d() {
    log_info "将本地 Canal 配置文件复制到远程机器 D..."
    ssh_d "mkdir -p /tmp/mock-system/inner-server/config/"
    sshpass -p "$MACHINE_D_PASS" scp -r -o StrictHostKeyChecking=no "./inner-server/config/canal" "$MACHINE_D_USER@$MACHINE_D_IP:/tmp/mock-system/inner-server/config/"
    log_info "机器D Canal 配置文件复制完成"
}

# 等待 MySQL 就绪
wait_for_mysql() {
    local docker_host=$1
    local container_name=$2
    local max_retries=30
    local retry=0

    log_info "等待 $container_name 就绪..."
    while [ $retry -lt $max_retries ]; do
        if docker -H $docker_host exec $container_name mysql -uroot -proot123 -e "SELECT 1" >/dev/null 2>&1; then
            log_info "$container_name 已就绪"
            return 0
        fi
        retry=$((retry + 1))
        echo -n "."
        sleep 2
    done
    echo ""
    log_error "$container_name 启动超时"
    return 1
}

# 初始化数据库（带重试）
init_database() {
    local docker_host=$1
    local container_name=$2
    local sql_commands=$3
    local max_retries=3
    local retry=0

    while [ $retry -lt $max_retries ]; do
        if docker -H $docker_host exec $container_name mysql -uroot -proot123 -e "$sql_commands" 2>&1; then
            log_info "数据库初始化成功"
            return 0
        fi
        retry=$((retry + 1))
        log_warn "数据库初始化失败，重试 ($retry/$max_retries)..."
        sleep 3
    done
    log_error "数据库初始化失败"
    return 1
}

# ==================== 启动 Docker API 转发 ====================
start_socat() {
    log_step "启动 Docker API 转发..."

    # 机器C
    log_info "启动机器C的 socat..."
    ssh_c "export PATH=/usr/local/bin:/opt/homebrew/bin:\$PATH && \
           pkill -f 'socat.*2375' 2>/dev/null || true && \
           nohup socat TCP-LISTEN:2375,reuseaddr,fork UNIX-CONNECT:/var/run/docker.sock > /tmp/socat.log 2>&1 &"

    # 机器D
    log_info "启动机器D的 socat..."
    ssh_d "export PATH=/usr/local/bin:/opt/homebrew/bin:\$PATH && \
           pkill -f 'socat.*2375' 2>/dev/null || true && \
           nohup socat TCP-LISTEN:2375,reuseaddr,fork UNIX-CONNECT:/var/run/docker.sock > /tmp/socat.log 2>&1 &"

    sleep 2

    # 验证
    log_info "验证 Docker API 连接..."
    if curl -s --connect-timeout 5 "http://${MACHINE_C_IP}:2375/version" > /dev/null 2>&1; then
        log_info "机器C Docker API 连接正常"
    else
        log_error "机器C Docker API 连接失败"
        return 1
    fi

    if curl -s --connect-timeout 5 "http://${MACHINE_D_IP}:2375/version" > /dev/null 2>&1; then
        log_info "机器D Docker API 连接正常"
    else
        log_error "机器D Docker API 连接失败"
        return 1
    fi
}

# ==================== 检查 Registry 连接 ====================
check_registry() {
    log_info "检查 Registry 连接..."
    if curl -s --connect-timeout 5 "http://${REGISTRY}/v2/_catalog" > /dev/null 2>&1; then
        log_info "Registry 连接正常 (http://${REGISTRY})"
    else
        log_warn "Registry 未启动，正在启动..."
        start_registry
    fi
}

# ==================== 启动 Registry ====================
start_registry() {
    log_step "在机器C上启动 Registry..."

    docker -H $MACHINE_C rm -f registry 2>/dev/null || true
    docker -H $MACHINE_C run -d \
        --name registry \
        --restart always \
        -p 5000:5000 \
        -v registry_data:/var/lib/registry \
        registry:2

    sleep 3
    log_info "Registry 已启动: http://${REGISTRY}"
}

# ==================== 创建 Docker 网络 ====================
create_networks() {
    log_step "创建 Docker 网络..."

    # 机器C
    docker -H $MACHINE_C network create $OUTER_NET 2>/dev/null || log_info "机器C网络 $OUTER_NET 已存在"

    # 机器D
    docker -H $MACHINE_D network create $INNER_NET 2>/dev/null || log_info "机器D网络 $INNER_NET 已存在"
}

# ==================== 部署机器C基础设施 ====================
deploy_infra_c() {
    log_step "部署机器C基础设施 (MySQL, Redis, Kafka, Canal)..."

    # 复制 Canal 配置文件
    copy_canal_configs_c

    # MySQL
    log_info "启动 MySQL..."
    docker -H $MACHINE_C rm -f mysql-outer 2>/dev/null || true
    docker -H $MACHINE_C run -d \
        --name mysql-outer \
        --network $OUTER_NET \
        -p 3306:3306 \
        -e MYSQL_ROOT_PASSWORD=root123 \
        -e MYSQL_DATABASE=outer_gateway \
        docker.m.daocloud.io/library/mysql:8.0 \
        --server-id=1 \
        --log-bin=mysql-bin \
        --binlog-format=ROW \
        --binlog-row-image=FULL \
        --default-authentication-plugin=mysql_native_password

    # Redis
    log_info "启动 Redis..."
    docker -H $MACHINE_C rm -f redis 2>/dev/null || true
    docker -H $MACHINE_C run -d \
        --name redis \
        --network $OUTER_NET \
        -p 6379:6379 \
        redis:7-alpine \
        redis-server --appendonly yes

    # Kafka (支持内外双监听器)
    log_info "启动 Kafka..."
    docker -H $MACHINE_C rm -f kafka-outer 2>/dev/null || true
    docker -H $MACHINE_C run -d \
        --name kafka-outer \
        --network $OUTER_NET \
        -p 9092:9092 \
        -p 29092:29092 \
        -e KAFKA_NODE_ID=1 \
        -e KAFKA_PROCESS_ROLES=broker,controller \
        -e KAFKA_CONTROLLER_QUORUM_VOTERS=1@kafka-outer:9093 \
        -e KAFKA_LISTENERS=INTERNAL://0.0.0.0:29092,EXTERNAL://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093 \
        -e KAFKA_ADVERTISED_LISTENERS=INTERNAL://kafka-outer:29092,EXTERNAL://${MACHINE_C_IP}:9092 \
        -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT \
        -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
        -e KAFKA_INTER_BROKER_LISTENER_NAME=INTERNAL \
        -e KAFKA_AUTO_CREATE_TOPICS_ENABLE=false \
        -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
        -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \
        -e KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1 \
        -e CLUSTER_ID=OkU3OEVBNTcwNTJENDM2Qk \
        docker.m.daocloud.io/confluentinc/cp-kafka:7.5.0

    # 等待 MySQL 就绪
    wait_for_mysql "$MACHINE_C" "mysql-outer"

    # 初始化数据库
    log_info "初始化外网数据库..."
    init_database "$MACHINE_C" "mysql-outer" "
        CREATE DATABASE IF NOT EXISTS outer_gateway;
        USE outer_gateway;
        CREATE TABLE IF NOT EXISTS outer_response (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            request_id VARCHAR(64) NOT NULL UNIQUE,
            response_data TEXT,
            response_code VARCHAR(10) DEFAULT '0000',
            error_msg VARCHAR(500),
            create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_request_id (request_id),
            INDEX idx_create_time (create_time)
        );
        CREATE USER IF NOT EXISTS 'canal'@'%' IDENTIFIED BY 'canal123';
        GRANT SELECT, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'canal'@'%';
        CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root123';
        GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
        FLUSH PRIVILEGES;
    "

    # 验证表创建成功
    if docker -H $MACHINE_C exec mysql-outer mysql -uroot -proot123 -e "USE outer_gateway; SHOW TABLES;" 2>/dev/null | grep -q "outer_response"; then
        log_info "outer_response 表创建成功"
    else
        log_error "outer_response 表创建失败!"
        exit 1
    fi

    # 创建 Kafka Topics
    create_kafka_topics_c

    # 部署 Canal
    deploy_canal_c

    log_info "机器C基础设施部署完成"
}

# ==================== 部署机器D基础设施 ====================
deploy_infra_d() {
    log_step "部署机器D基础设施 (MySQL, Kafka, Canal)..."

    # 复制 Canal 配置文件
    copy_canal_configs_d

    # MySQL
    log_info "启动 MySQL..."
    docker -H $MACHINE_D rm -f mysql-inner 2>/dev/null || true
    docker -H $MACHINE_D run -d \
        --name mysql-inner \
        --network $INNER_NET \
        -p 3306:3306 \
        -e MYSQL_ROOT_PASSWORD=root123 \
        -e MYSQL_DATABASE=inner_gateway \
        docker.m.daocloud.io/library/mysql:8.0 \
        --server-id=2 \
        --log-bin=mysql-bin \
        --binlog-format=ROW \
        --binlog-row-image=FULL \
        --gtid-mode=ON \
        --enforce-gtid-consistency=ON \
        --default-authentication-plugin=mysql_native_password

    # Kafka (支持内外双监听器)
    log_info "启动 Kafka..."
    docker -H $MACHINE_D rm -f kafka-inner 2>/dev/null || true
    docker -H $MACHINE_D run -d \
        --name kafka-inner \
        --network $INNER_NET \
        -p 9092:9092 \
        -p 29092:29092 \
        -e KAFKA_NODE_ID=1 \
        -e KAFKA_PROCESS_ROLES=broker,controller \
        -e KAFKA_CONTROLLER_QUORUM_VOTERS=1@kafka-inner:9093 \
        -e KAFKA_LISTENERS=INTERNAL://0.0.0.0:29092,EXTERNAL://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093 \
        -e KAFKA_ADVERTISED_LISTENERS=INTERNAL://kafka-inner:29092,EXTERNAL://${MACHINE_D_IP}:9092 \
        -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT \
        -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
        -e KAFKA_INTER_BROKER_LISTENER_NAME=INTERNAL \
        -e KAFKA_AUTO_CREATE_TOPICS_ENABLE=false \
        -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
        -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \
        -e KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1 \
        -e CLUSTER_ID=MkU3OEVBNTcwNTJENDM2Qk \
        docker.m.daocloud.io/confluentinc/cp-kafka:7.5.0

    # 等待 MySQL 就绪
    wait_for_mysql "$MACHINE_D" "mysql-inner"

    # 初始化数据库
    log_info "初始化内网数据库..."
    init_database "$MACHINE_D" "mysql-inner" "
        CREATE DATABASE IF NOT EXISTS inner_gateway;
        USE inner_gateway;
        CREATE TABLE IF NOT EXISTS inner_request (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            request_id VARCHAR(64) NOT NULL UNIQUE,
            code VARCHAR(32) NOT NULL,
            param_data TEXT,
            channel_type VARCHAR(32),
            serial_no VARCHAR(64),
            source VARCHAR(32),
            target VARCHAR(32),
            status INT DEFAULT 0,
            create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
            update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_request_id (request_id),
            INDEX idx_status (status),
            INDEX idx_create_time (create_time)
        );
        CREATE TABLE IF NOT EXISTS service_route (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            code VARCHAR(32) NOT NULL UNIQUE,
            service_url VARCHAR(500) NOT NULL,
            service_name VARCHAR(100),
            enabled TINYINT DEFAULT 1,
            create_time DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        INSERT IGNORE INTO service_route (code, service_url, service_name) VALUES
            ('0000', 'http://target-service:8083/inner/c17/f01', '默认测试服务'),
            ('yhzx', 'http://target-service:8083/inner/c17/f01', '用户中心服务'),
            ('zdzx', 'http://target-service:8083/inner/c17/f01', '账单中心服务');
        CREATE USER IF NOT EXISTS 'canal'@'%' IDENTIFIED BY 'canal123';
        GRANT SELECT, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'canal'@'%';
        CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root123';
        GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
        FLUSH PRIVILEGES;
    "

    # 验证表创建成功
    if docker -H $MACHINE_D exec mysql-inner mysql -uroot -proot123 -e "USE inner_gateway; SHOW TABLES;" 2>/dev/null | grep -q "inner_request"; then
        log_info "inner_request 表创建成功"
    else
        log_error "inner_request 表创建失败!"
        exit 1
    fi

    # 创建 Kafka Topics
    create_kafka_topics_d

    # 部署 Canal
    deploy_canal_d

    log_info "机器D基础设施部署完成"
}

# ==================== 部署 Canal ====================

# 等待 Kafka 就绪并创建 topic（带重试和验证）
wait_and_create_topic() {
    local docker_host=$1
    local kafka_container=$2
    local topic_name=$3
    local partitions=$4
    local max_retries=10
    local retry=0

    log_info "等待 Kafka 就绪并创建 topic: $topic_name (分区数: $partitions)..."

    # 等待 Kafka 就绪
    while [ $retry -lt $max_retries ]; do
        if docker -H $docker_host exec $kafka_container /usr/bin/kafka-topics --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then
            break
        fi
        retry=$((retry + 1))
        log_info "等待 Kafka 就绪... ($retry/$max_retries)"
        sleep 3
    done

    if [ $retry -eq $max_retries ]; then
        log_error "Kafka 未就绪，无法创建 topic: $topic_name"
        return 1
    fi

    # 创建 topic
    docker -H $docker_host exec $kafka_container /usr/bin/kafka-topics --bootstrap-server localhost:9092 \
      --create --topic $topic_name --partitions $partitions --replication-factor 1 --if-not-exists 2>&1 || true

    sleep 2

    # 验证 topic 分区数
    local actual_partitions=$(docker -H $docker_host exec $kafka_container /usr/bin/kafka-topics --bootstrap-server localhost:9092 \
      --describe --topic $topic_name 2>/dev/null | grep -c "Partition:")

    if [ "$actual_partitions" -eq "$partitions" ]; then
        log_info "Topic $topic_name 创建成功，分区数: $actual_partitions"
    else
        log_warn "Topic $topic_name 分区数不匹配! 期望: $partitions, 实际: $actual_partitions"
        # 尝试删除并重建
        log_info "尝试删除并重建 topic..."
        docker -H $docker_host exec $kafka_container /usr/bin/kafka-topics --bootstrap-server localhost:9092 \
          --delete --topic $topic_name 2>/dev/null || true
        sleep 5
        docker -H $docker_host exec $kafka_container /usr/bin/kafka-topics --bootstrap-server localhost:9092 \
          --create --topic $topic_name --partitions $partitions --replication-factor 1 2>&1
        log_info "Topic $topic_name 重建完成"
    fi
}

create_kafka_topics_c() {
    log_info "在机器C上创建 Kafka Topics..."
    wait_and_create_topic "$MACHINE_C" "kafka-outer" "inner_request_binlog" 3
    wait_and_create_topic "$MACHINE_C" "kafka-outer" "outer_response_binlog" 3
    log_info "机器C Kafka Topics 创建完成"
}

create_kafka_topics_d() {
    log_info "在机器D上创建 Kafka Topics..."
    wait_and_create_topic "$MACHINE_D" "kafka-inner" "inner_request_binlog" 3
    wait_and_create_topic "$MACHINE_D" "kafka-inner" "outer_response_binlog" 3
    log_info "机器D Kafka Topics 创建完成"
}

deploy_canal_c() {
    log_info "部署机器C的 Canal (监听 outer_response_binlog)..."

    # 确保 MySQL 有 canal 用户
    docker -H $MACHINE_C exec mysql-outer mysql -uroot -proot123 -e "
        CREATE USER IF NOT EXISTS 'canal'@'%' IDENTIFIED BY 'canal123';
        GRANT SELECT, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'canal'@'%';
        FLUSH PRIVILEGES;
    " 2>/dev/null || true

    docker -H $MACHINE_C rm -f canal-outer 2>/dev/null || true
    docker -H $MACHINE_C run -d \
        --name canal-outer \
        --network $OUTER_NET \
        -p 11111:11111 \
        -e canal.auto.scan=false \
        -e canal.destinations=example \
        -v /tmp/mock-system/outer-server/config/canal/canal.properties:/home/admin/canal-server/conf/canal.properties \
        -v /tmp/mock-system/outer-server/config/canal/instance.properties:/home/admin/canal-server/conf/example/instance.properties \
        192.168.123.113:5000/canal-server:v1.1.7

    sleep 10
    log_info "机器C Canal 部署完成"
}

deploy_canal_d() {
    log_info "部署机器D的 Canal (监听 inner_request_binlog)..."

    docker -H $MACHINE_D rm -f canal-inner 2>/dev/null || true
    docker -H $MACHINE_D run -d \
        --name canal-inner \
        --network $INNER_NET \
        -p 11111:11111 \
        -e canal.auto.scan=false \
        -e canal.destinations=example \
        -v /tmp/mock-system/inner-server/config/canal/canal.properties:/home/admin/canal-server/conf/canal.properties \
        -v /tmp/mock-system/inner-server/config/canal/instance.properties:/home/admin/canal-server/conf/example/instance.properties \
        192.168.123.113:5000/canal-server:v1.1.7

    sleep 10
    log_info "机器D Canal 部署完成"
}

# ==================== 构建并推送镜像 ====================
build_and_push() {
    local path=$1
    local name=$2

    log_info "构建 $name..."
    docker -H $MACHINE_C build -t $REGISTRY/$name:latest ./$path

    log_info "推送 $name 到 Registry..."
    docker -H $MACHINE_C push $REGISTRY/$name:latest
}

# ==================== 部署机器C应用服务 ====================
deploy_scp0005() {
    log_info "部署 scp0005 到机器C..."
    docker -H $MACHINE_C pull $REGISTRY/scp0005:latest 2>/dev/null || true
    docker -H $MACHINE_C stop scp0005 2>/dev/null || true
    docker -H $MACHINE_C rm scp0005 2>/dev/null || true

    docker -H $MACHINE_C run -d \
        --name scp0005 \
        --network $OUTER_NET \
        -p 8080:8080 \
        -e INNER_DB_HOST=$MACHINE_D_IP \
        -e INNER_DB_PORT=3306 \
        -e INNER_DB_NAME=inner_gateway \
        -e INNER_DB_USER=root \
        -e INNER_DB_PASSWORD=root123 \
        -e REDIS_HOST=redis \
        -e REDIS_PORT=6379 \
        $REGISTRY/scp0005:latest

    log_info "scp0005 已部署到机器C"
}

deploy_outer_consumer() {
    log_info "部署 outer-consumer 到机器C..."
    docker -H $MACHINE_C pull $REGISTRY/outer-consumer:latest 2>/dev/null || true
    docker -H $MACHINE_C stop outer-consumer 2>/dev/null || true
    docker -H $MACHINE_C rm outer-consumer 2>/dev/null || true

    docker -H $MACHINE_C run -d \
        --name outer-consumer \
        --network $OUTER_NET \
        -p 8081:8081 \
        -e REDIS_HOST=redis \
        -e REDIS_PORT=6379 \
        -e KAFKA_BOOTSTRAP=kafka-outer:9092 \
        -e KAFKA_TOPIC=outer_response_binlog \
        -e RESULT_KEY_PREFIX=gateway:result: \
        $REGISTRY/outer-consumer:latest

    log_info "outer-consumer 已部署到机器C"
}

# ==================== 部署机器D应用服务 ====================
deploy_scp0006() {
    log_info "部署 scp0006 到机器D..."
    docker -H $MACHINE_D pull $REGISTRY/scp0006:latest 2>/dev/null || true
    docker -H $MACHINE_D stop scp0006 2>/dev/null || true
    docker -H $MACHINE_D rm scp0006 2>/dev/null || true

    docker -H $MACHINE_D run -d \
        --name scp0006 \
        --network $INNER_NET \
        -p 8082:8082 \
        -e OUTER_DB_HOST=$MACHINE_C_IP \
        -e OUTER_DB_PORT=3306 \
        -e OUTER_DB_NAME=outer_gateway \
        -e OUTER_DB_USER=root \
        -e OUTER_DB_PASSWORD=root123 \
        -e KAFKA_BOOTSTRAP=kafka-inner:9092 \
        -e KAFKA_TOPIC=inner_request_binlog \
        -e TARGET_SERVICE_URL=http://target-service:8083 \
        $REGISTRY/scp0006:latest

    log_info "scp0006 已部署到机器D"
}

deploy_target_service() {
    log_info "部署 target-service 到机器D..."
    docker -H $MACHINE_D pull $REGISTRY/target-service:latest 2>/dev/null || true
    docker -H $MACHINE_D stop target-service 2>/dev/null || true
    docker -H $MACHINE_D rm target-service 2>/dev/null || true

    docker -H $MACHINE_D run -d \
        --name target-service \
        --network $INNER_NET \
        -p 8083:8083 \
        -e SERVER_PORT=8083 \
        -e MOCK_DELAY_MS=50 \
        -e MOCK_ERROR_RATE=0 \
        $REGISTRY/target-service:latest

    log_info "target-service 已部署到机器D"
}

# ==================== 端到端测试 ====================
run_e2e_test() {
    log_info "等待服务就绪..."
    sleep 5

    log_info "执行端到端测试..."
    local response=$(curl -s -X POST "http://${MACHINE_C_IP}:8080/inner/c1/yhzx" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "code=yhzx&paramData={\"test\":\"deploy-test-CD\"}" \
        --max-time 35)

    if echo "$response" | grep -q '"code":"200"'; then
        log_info "端到端测试通过!"
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
        return 0
    else
        log_error "端到端测试失败!"
        echo "$response"
        return 1
    fi
}

# ==================== 查看状态 ====================
show_status() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "                    服务状态 (机器C/D)"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "机器 C (${MACHINE_C_IP}) - 外网:"
    echo "─────────────────────────────────────────────────────────────"
    docker -H $MACHINE_C ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || log_error "无法连接机器 C"
    echo ""
    echo "机器 D (${MACHINE_D_IP}) - 内网:"
    echo "─────────────────────────────────────────────────────────────"
    docker -H $MACHINE_D ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || log_error "无法连接机器 D"
    echo ""
}

# ==================== 查看日志 ====================
show_logs() {
    local service=$1
    local lines=${2:-50}

    case $service in
        scp0005|outer-consumer|canal-outer|mysql-outer|redis|kafka-outer|registry)
            docker -H $MACHINE_C logs $service --tail $lines
            ;;
        scp0006|target-service|canal-inner|mysql-inner|kafka-inner)
            docker -H $MACHINE_D logs $service --tail $lines
            ;;
        *)
            log_error "未知服务: $service"
            echo "可用服务: scp0005, outer-consumer, scp0006, target-service, mysql-outer, mysql-inner, kafka-outer, kafka-inner, redis"
            ;;
    esac
}

# ==================== 停止所有服务 ====================
stop_all() {
    log_step "停止所有服务..."

    # 机器C
    log_info "停止机器C的服务..."
    docker -H $MACHINE_C stop scp0005 outer-consumer canal-outer kafka-outer redis mysql-outer registry 2>/dev/null || true

    # 机器D
    log_info "停止机器D的服务..."
    docker -H $MACHINE_D stop scp0006 target-service canal-inner kafka-inner mysql-inner 2>/dev/null || true

    log_info "所有服务已停止"
}

# ==================== 主流程 ====================
main() {
    local cmd=${1:-"help"}

    # 获取脚本所在目录并切换到该目录
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    cd "$SCRIPT_DIR"

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "          穿透网关 - 机器C/D 部署工具"
    echo "════════════════════════════════════════════════════════════"
    echo "机器C (外网): ${MACHINE_C_IP}"
    echo "机器D (内网): ${MACHINE_D_IP}"
    echo "Registry: ${REGISTRY}"
    echo ""

    case $cmd in
        "socat")
            start_socat
            ;;

        "init")
            log_step "======== 首次部署：初始化环境 ========"
            start_socat

            # 清理旧的应用容器（避免网络名不匹配问题）
            log_info "清理旧的应用容器..."
            docker -H $MACHINE_C rm -f scp0005 outer-consumer 2>/dev/null || true
            docker -H $MACHINE_D rm -f scp0006 target-service 2>/dev/null || true

            create_networks
            start_registry
            deploy_infra_c
            deploy_infra_d
            log_info "基础设施部署完成，现在可以运行 './deploy-registryCD.sh all' 部署应用"
            show_status
            ;;

        "all")
            start_socat
            check_registry

            log_step "======== 构建镜像 ========"
            build_and_push "outer-server/scp0005" "scp0005"
            build_and_push "outer-server/outer-consumer" "outer-consumer"
            build_and_push "inner-server/scp0006" "scp0006"
            build_and_push "inner-server/target-service" "target-service"

            log_step "======== 部署服务 ========"
            deploy_scp0005
            deploy_outer_consumer
            deploy_target_service  # 必须在 scp0006 之前部署
            deploy_scp0006

            log_step "======== 验证部署 ========"
            run_e2e_test || log_warn "测试未通过，请检查日志"

            show_status
            ;;

        "outer")
            start_socat
            check_registry
            build_and_push "outer-server/scp0005" "scp0005"
            build_and_push "outer-server/outer-consumer" "outer-consumer"
            deploy_scp0005
            deploy_outer_consumer
            show_status
            ;;

        "inner")
            start_socat
            check_registry
            build_and_push "inner-server/scp0006" "scp0006"
            build_and_push "inner-server/target-service" "target-service"
            deploy_target_service  # 必须在 scp0006 之前部署
            deploy_scp0006
            show_status
            ;;

        "infra")
            start_socat
            create_networks
            deploy_infra_c
            deploy_infra_d
            show_status
            ;;

        "status")
            show_status
            ;;

        "test")
            run_e2e_test
            ;;

        "logs")
            if [ -z "$2" ]; then
                log_error "请指定服务名: $0 logs <service> [lines]"
                echo "可用服务: scp0005, outer-consumer, scp0006, target-service, mysql-outer, mysql-inner, kafka-outer, kafka-inner, redis"
            else
                show_logs "$2" "${3:-50}"
            fi
            ;;

        "stop")
            stop_all
            ;;

        "images")
            log_info "Registry 中的镜像:"
            curl -s "http://${REGISTRY}/v2/_catalog" | python3 -m json.tool 2>/dev/null || curl -s "http://${REGISTRY}/v2/_catalog"
            ;;

        "help"|*)
            echo "用法: $0 <命令>"
            echo ""
            echo "命令:"
            echo "  init     首次部署：启动基础设施 + Registry（推荐首次运行）"
            echo "  all      构建并部署所有应用服务"
            echo "  outer    只部署机器 C 的服务 (scp0005, outer-consumer)"
            echo "  inner    只部署机器 D 的服务 (scp0006, target-service)"
            echo "  infra    只部署基础设施 (MySQL, Kafka, Redis)"
            echo "  status   查看所有服务状态"
            echo "  test     运行端到端测试"
            echo "  logs     查看服务日志: $0 logs <service> [lines]"
            echo "  stop     停止所有服务"
            echo "  socat    启动 Docker API 转发"
            echo "  images   查看 Registry 中的镜像"
            echo ""
            echo "示例:"
            echo "  $0 init          # 首次部署，初始化所有基础设施"
            echo "  $0 all           # 修改代码后，一键部署应用"
            echo "  $0 status        # 查看服务状态"
            echo "  $0 test          # 验证部署是否成功"
            echo "  $0 logs scp0005  # 查看 scp0005 日志"
            ;;
    esac

    echo ""
    log_info "完成!"
}

main "$@"
