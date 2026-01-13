#!/bin/bash
#
# 远程部署脚本
# 将 mock-system 部署到机器 A 和机器 B
#

set -e

# ==================== 配置 ====================
MACHINE_A_IP="192.168.123.66"
MACHINE_B_IP="192.168.123.81"
SSH_USER="shulie"
REMOTE_PATH="/Users/shulie/mock-system"
LOCAL_PATH="$(cd "$(dirname "$0")" && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==================== 检查依赖 ====================
check_dependencies() {
    log_info "检查依赖..."

    if command -v sshpass &> /dev/null; then
        USE_SSHPASS=true
        log_info "检测到 sshpass，将使用自动密码输入"
    else
        USE_SSHPASS=false
        log_warn "未安装 sshpass，每次 SSH/SCP 操作都需要输入密码"
        log_info "可通过 'brew install sshpass' 安装 (需要先 brew install hudochenkov/sshpass/sshpass)"
    fi
}

# ==================== 获取密码 ====================
get_password() {
    if [ "$USE_SSHPASS" = true ]; then
        echo -n "请输入 SSH 密码: "
        read -s SSH_PASSWORD
        echo
        export SSHPASS="$SSH_PASSWORD"
    fi
}

# ==================== SSH/SCP 包装函数 ====================
do_ssh() {
    local host=$1
    shift
    if [ "$USE_SSHPASS" = true ]; then
        sshpass -e ssh -o StrictHostKeyChecking=no "$SSH_USER@$host" "$@"
    else
        ssh -o StrictHostKeyChecking=no "$SSH_USER@$host" "$@"
    fi
}

do_scp() {
    if [ "$USE_SSHPASS" = true ]; then
        sshpass -e scp -o StrictHostKeyChecking=no "$@"
    else
        scp -o StrictHostKeyChecking=no "$@"
    fi
}

# ==================== 测试连接 ====================
test_connection() {
    local host=$1
    local name=$2
    log_info "测试连接 $name ($host)..."
    if do_ssh "$host" "echo 'SSH 连接成功'" 2>/dev/null; then
        log_info "$name 连接成功"
        return 0
    else
        log_error "$name 连接失败"
        return 1
    fi
}

# ==================== 传输代码 ====================
transfer_code() {
    local host=$1
    local name=$2
    local folder=$3

    log_info "传输代码到 $name ($host)..."

    # 创建远程目录
    do_ssh "$host" "mkdir -p $REMOTE_PATH"

    # 打包并传输指定文件夹
    log_info "传输 $folder 到 $name..."

    # 使用 rsync 如果可用，否则用 tar + scp
    if command -v rsync &> /dev/null && [ "$USE_SSHPASS" = false ]; then
        rsync -avz --delete \
            --exclude 'target/' \
            --exclude 'node_modules/' \
            --exclude '.git/' \
            --exclude '*.log' \
            "$LOCAL_PATH/$folder/" "$SSH_USER@$host:$REMOTE_PATH/$folder/"
    else
        # 打包
        cd "$LOCAL_PATH"
        tar czf "/tmp/${folder}.tar.gz" \
            --exclude='target' \
            --exclude='node_modules' \
            --exclude='.git' \
            --exclude='*.log' \
            "$folder"

        # 传输
        do_scp "/tmp/${folder}.tar.gz" "$SSH_USER@$host:/tmp/"

        # 解压
        do_ssh "$host" "cd $REMOTE_PATH && rm -rf $folder && tar xzf /tmp/${folder}.tar.gz && rm /tmp/${folder}.tar.gz"

        # 清理本地临时文件
        rm -f "/tmp/${folder}.tar.gz"
    fi

    log_info "$folder 传输完成"
}

# ==================== 部署机器 B ====================
deploy_machine_b() {
    log_info "========== 开始部署机器 B (内网 $MACHINE_B_IP) =========="

    # 传输 inner-server
    transfer_code "$MACHINE_B_IP" "机器B" "inner-server"

    # 执行部署
    log_info "在机器 B 上执行部署..."
    do_ssh "$MACHINE_B_IP" "bash -s" << 'REMOTE_SCRIPT'
set -e
cd /Users/shulie/mock-system/inner-server

echo "=== 停止旧容器 ==="
docker-compose down 2>/dev/null || true

echo "=== 启动 MySQL 和 Kafka ==="
docker-compose up -d mysql kafka

echo "=== 等待 MySQL 就绪 (30秒) ==="
sleep 30

echo "=== 检查服务状态 ==="
docker-compose ps

echo "=== 启动 Canal ==="
docker-compose up -d canal

echo "=== 等待 Canal 就绪 (20秒) ==="
sleep 20

echo "=== 检查 Canal 日志 ==="
docker logs canal-inner --tail 20 2>&1 | grep -E "(find start position|binlog|error)" || echo "Canal 启动中..."

echo "=== 启动应用服务 ==="
docker-compose up -d --build target-service scp0006

echo "=== 最终状态 ==="
docker-compose ps

echo "=== 机器 B 部署完成 ==="
REMOTE_SCRIPT

    log_info "机器 B 部署完成"
}

# ==================== 部署机器 A ====================
deploy_machine_a() {
    log_info "========== 开始部署机器 A (外网 $MACHINE_A_IP) =========="

    # 传输 outer-server
    transfer_code "$MACHINE_A_IP" "机器A" "outer-server"

    # 执行部署
    log_info "在机器 A 上执行部署..."
    do_ssh "$MACHINE_A_IP" "bash -s" << 'REMOTE_SCRIPT'
set -e
cd /Users/shulie/mock-system/outer-server

echo "=== 停止旧容器 ==="
docker-compose down 2>/dev/null || true

echo "=== 启动 MySQL, Redis 和 Kafka ==="
docker-compose up -d mysql redis kafka

echo "=== 等待 MySQL 就绪 (30秒) ==="
sleep 30

echo "=== 检查服务状态 ==="
docker-compose ps

echo "=== 启动 Canal ==="
docker-compose up -d canal

echo "=== 等待 Canal 就绪 (20秒) ==="
sleep 20

echo "=== 检查 Canal 日志 ==="
docker logs canal-outer --tail 20 2>&1 | grep -E "(find start position|binlog|error)" || echo "Canal 启动中..."

echo "=== 启动应用服务 ==="
docker-compose up -d --build scp0005 outer-consumer

echo "=== 最终状态 ==="
docker-compose ps

echo "=== 机器 A 部署完成 ==="
REMOTE_SCRIPT

    log_info "机器 A 部署完成"
}

# ==================== 验证部署 ====================
verify_deployment() {
    log_info "========== 验证部署 =========="

    log_info "检查机器 B 服务状态..."
    do_ssh "$MACHINE_B_IP" "cd /Users/shulie/mock-system/inner-server && docker-compose ps"

    log_info "检查机器 B Canal 状态..."
    do_ssh "$MACHINE_B_IP" "docker logs canal-inner --tail 10 2>&1 | grep -E '(find start position|binlog|running)' || echo 'Canal 状态未知'"

    log_info "检查机器 A 服务状态..."
    do_ssh "$MACHINE_A_IP" "cd /Users/shulie/mock-system/outer-server && docker-compose ps"

    log_info "检查机器 A Canal 状态..."
    do_ssh "$MACHINE_A_IP" "docker logs canal-outer --tail 10 2>&1 | grep -E '(find start position|binlog|running)' || echo 'Canal 状态未知'"
}

# ==================== Canal 验证 ====================
verify_canal() {
    log_info "========== 验证 Canal 数据捕获 =========="

    # 机器 B - 测试 inner_request 表
    log_info "测试机器 B Canal (inner_request)..."
    TEST_ID_B="verify-canal-b-$(date +%s)"
    do_ssh "$MACHINE_B_IP" "docker exec mysql-inner mysql -uroot -proot123 inner_gateway -e \"INSERT INTO inner_request (request_id, code, param_data) VALUES ('$TEST_ID_B', 'test', '{\\\"verify\\\":\\\"canal\\\"}')\""
    sleep 3
    log_info "检查 Kafka topic..."
    do_ssh "$MACHINE_B_IP" "docker exec kafka-inner timeout 5 kafka-console-consumer --bootstrap-server localhost:9092 --topic inner_request_binlog --from-beginning --max-messages 1 2>/dev/null || echo '未能消费消息'"

    # 机器 A - 测试 outer_response 表
    log_info "测试机器 A Canal (outer_response)..."
    TEST_ID_A="verify-canal-a-$(date +%s)"
    do_ssh "$MACHINE_A_IP" "docker exec mysql-outer mysql -uroot -proot123 outer_gateway -e \"INSERT INTO outer_response (request_id, response_data, response_code) VALUES ('$TEST_ID_A', '{\\\"verify\\\":\\\"canal\\\"}', '0000')\""
    sleep 3
    log_info "检查 Kafka topic..."
    do_ssh "$MACHINE_A_IP" "docker exec kafka-outer timeout 5 kafka-console-consumer --bootstrap-server localhost:9092 --topic outer_response_binlog --from-beginning --max-messages 1 2>/dev/null || echo '未能消费消息'"
}

# ==================== 端到端测试 ====================
e2e_test() {
    log_info "========== 端到端测试 =========="

    log_info "发送测试请求到机器 A..."
    RESPONSE=$(do_ssh "$MACHINE_A_IP" "curl -s -X POST 'http://localhost:8080/inner/c1/yhzx' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        -d 'code=yhzx&paramData={\"test\":\"remote-deploy\"}'")

    echo "响应: $RESPONSE"

    if echo "$RESPONSE" | grep -q '"code":"200"'; then
        log_info "端到端测试通过!"
    else
        log_warn "端到端测试可能失败，请检查响应"
    fi
}

# ==================== 主流程 ====================
main() {
    echo "======================================"
    echo "   Mock System 远程部署脚本"
    echo "======================================"
    echo ""
    echo "机器 A (外网): $MACHINE_A_IP"
    echo "机器 B (内网): $MACHINE_B_IP"
    echo "部署路径: $REMOTE_PATH"
    echo ""

    check_dependencies
    get_password

    # 测试连接
    if ! test_connection "$MACHINE_B_IP" "机器B"; then
        log_error "无法连接机器 B，请检查网络和 SSH 配置"
        exit 1
    fi

    if ! test_connection "$MACHINE_A_IP" "机器A"; then
        log_error "无法连接机器 A，请检查网络和 SSH 配置"
        exit 1
    fi

    # 按顺序部署
    deploy_machine_b

    log_info "等待 10 秒后部署机器 A..."
    sleep 10

    deploy_machine_a

    # 验证
    log_info "等待 30 秒让服务完全启动..."
    sleep 30

    verify_deployment

    # Canal 验证
    echo ""
    read -p "是否验证 Canal 数据捕获? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        verify_canal
    fi

    # 可选: 端到端测试
    echo ""
    read -p "是否执行端到端测试? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        e2e_test
    fi

    echo ""
    log_info "======================================"
    log_info "   部署完成!"
    log_info "======================================"
}

# 运行
main "$@"
