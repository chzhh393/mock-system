#!/bin/bash
#
# 基础环境一次性初始化脚本
#
# 说明：
#   这个脚本只需要在沙箱环境首次部署时运行一次。
#   它会启动并配置所有基础服务（MySQL、Kafka、Canal、Redis、Registry）。
#   之后开发者只需要使用 deploy-registry.sh 部署应用代码。
#
# 使用方法:
#   ./setup-base-env.sh          # 初始化基础环境
#   ./setup-base-env.sh status   # 检查基础环境状态
#   ./setup-base-env.sh reset    # 重置基础环境（危险：会删除所有数据）
#

set -e

# ==================== 配置 ====================
MACHINE_A="tcp://192.168.123.66:2375"
MACHINE_B="tcp://192.168.123.81:2375"
MACHINE_A_IP="192.168.123.66"
MACHINE_B_IP="192.168.123.81"

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

# ==================== 检查连接 ====================
check_connections() {
    log_step "检查远程 Docker 连接..."

    if docker -H $MACHINE_A info > /dev/null 2>&1; then
        log_info "机器 A ($MACHINE_A_IP) 连接正常"
    else
        log_error "无法连接机器 A ($MACHINE_A_IP)"
        exit 1
    fi

    if docker -H $MACHINE_B info > /dev/null 2>&1; then
        log_info "机器 B ($MACHINE_B_IP) 连接正常"
    else
        log_error "无法连接机器 B ($MACHINE_B_IP)"
        exit 1
    fi
}

# ==================== 机器 B 基础服务 ====================
setup_machine_b() {
    log_step "=========================================="
    log_step "配置机器 B ($MACHINE_B_IP) - 内网"
    log_step "=========================================="

    # 检查服务是否运行
    local mysql_running=$(docker -H $MACHINE_B ps --filter "name=mysql-inner" --format "{{.Names}}" 2>/dev/null)
    local kafka_running=$(docker -H $MACHINE_B ps --filter "name=kafka-inner" --format "{{.Names}}" 2>/dev/null)
    local canal_running=$(docker -H $MACHINE_B ps --filter "name=canal-inner" --format "{{.Names}}" 2>/dev/null)

    if [ -n "$mysql_running" ] && [ -n "$kafka_running" ] && [ -n "$canal_running" ]; then
        log_info "机器 B 基础服务已在运行"
    else
        log_warn "请先在机器 B 上通过 docker-compose 启动基础服务:"
        echo "  cd /path/to/mock-system/inner-server"
        echo "  docker-compose up -d mysql kafka canal"
        log_error "基础服务未启动，请先手动启动"
        return 1
    fi

    # 验证 Canal 配置
    log_info "验证 Canal 配置..."
    local canal_kafka_config=$(docker -H $MACHINE_B exec canal-inner grep "kafka.bootstrap.servers" /home/admin/canal-server/conf/canal.properties 2>/dev/null || echo "")

    if echo "$canal_kafka_config" | grep -q "$MACHINE_B_IP:9092"; then
        log_info "Canal Kafka 配置正确"
    else
        log_warn "修复 Canal Kafka 配置..."
        docker -H $MACHINE_B exec canal-inner sed -i "s|kafka.bootstrap.servers = .*|kafka.bootstrap.servers = $MACHINE_B_IP:9092|g" /home/admin/canal-server/conf/canal.properties
        docker -H $MACHINE_B restart canal-inner
        log_info "Canal 已重启"
    fi

    log_info "机器 B 基础环境就绪"
}

# ==================== 机器 A 基础服务 ====================
setup_machine_a() {
    log_step "=========================================="
    log_step "配置机器 A ($MACHINE_A_IP) - 外网"
    log_step "=========================================="

    # 检查服务是否运行
    local mysql_running=$(docker -H $MACHINE_A ps --filter "name=mysql-outer" --format "{{.Names}}" 2>/dev/null)
    local kafka_running=$(docker -H $MACHINE_A ps --filter "name=kafka-outer" --format "{{.Names}}" 2>/dev/null)
    local redis_running=$(docker -H $MACHINE_A ps --filter "name=redis" --format "{{.Names}}" 2>/dev/null)
    local canal_running=$(docker -H $MACHINE_A ps --filter "name=canal-outer" --format "{{.Names}}" 2>/dev/null)
    local registry_running=$(docker -H $MACHINE_A ps --filter "name=registry" --format "{{.Names}}" 2>/dev/null)

    if [ -n "$mysql_running" ] && [ -n "$kafka_running" ] && [ -n "$redis_running" ] && [ -n "$canal_running" ]; then
        log_info "机器 A 基础服务已在运行"
    else
        log_warn "请先在机器 A 上通过 docker-compose 启动基础服务:"
        echo "  cd /path/to/mock-system/outer-server"
        echo "  docker-compose up -d mysql redis kafka canal"
        log_error "基础服务未启动，请先手动启动"
        return 1
    fi

    # 检查 Registry
    if [ -z "$registry_running" ]; then
        log_warn "启动 Registry..."
        docker -H $MACHINE_A run -d --name registry --restart=always -p 5000:5000 registry:2 2>/dev/null || true
    fi

    # 1. 确保 outer_response 表存在
    log_info "确保数据库表存在..."
    docker -H $MACHINE_A exec mysql-outer mysql -uroot -proot123 -e "
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
    " 2>/dev/null || log_warn "表可能已存在"

    # 2. 确保 Canal 用户存在
    log_info "确保 Canal 用户存在..."
    docker -H $MACHINE_A exec mysql-outer mysql -uroot -proot123 -e "
        CREATE USER IF NOT EXISTS 'canal'@'%' IDENTIFIED BY 'canal123';
        GRANT SELECT, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'canal'@'%';
        FLUSH PRIVILEGES;
    " 2>/dev/null || log_warn "用户可能已存在"

    # 3. 修复 Canal 配置
    log_info "配置 Canal..."

    # 检查 Canal 是否有正确的配置挂载
    local canal_mounts=$(docker -H $MACHINE_A inspect canal-outer --format '{{json .Mounts}}' 2>/dev/null)

    if echo "$canal_mounts" | grep -q "canal.properties"; then
        log_info "Canal 配置文件已挂载"
    else
        log_warn "Canal 配置未挂载，直接修改容器内配置..."

        # serverMode = kafka
        docker -H $MACHINE_A exec canal-outer sed -i 's|canal.serverMode = tcp|canal.serverMode = kafka|g' /home/admin/canal-server/conf/canal.properties 2>/dev/null || true

        # kafka.bootstrap.servers
        docker -H $MACHINE_A exec canal-outer sed -i "s|kafka.bootstrap.servers = .*|kafka.bootstrap.servers = $MACHINE_A_IP:9092|g" /home/admin/canal-server/conf/canal.properties 2>/dev/null || true

        # master.address
        docker -H $MACHINE_A exec canal-outer sed -i "s|canal.instance.master.address=.*|canal.instance.master.address=$MACHINE_A_IP:3306|g" /home/admin/canal-server/conf/example/instance.properties 2>/dev/null || true

        # filter.regex
        docker -H $MACHINE_A exec canal-outer sed -i 's|canal.instance.filter.regex=.*|canal.instance.filter.regex=outer_gateway\\.outer_response|g' /home/admin/canal-server/conf/example/instance.properties 2>/dev/null || true

        # mq.topic
        docker -H $MACHINE_A exec canal-outer sed -i 's|canal.mq.topic=.*|canal.mq.topic=outer_response_binlog|g' /home/admin/canal-server/conf/example/instance.properties 2>/dev/null || true

        # dbPassword
        docker -H $MACHINE_A exec canal-outer sed -i 's|canal.instance.dbPassword=canal$|canal.instance.dbPassword=canal123|g' /home/admin/canal-server/conf/example/instance.properties 2>/dev/null || true

        log_info "重启 Canal..."
        docker -H $MACHINE_A restart canal-outer
    fi

    log_info "机器 A 基础环境就绪"
}

# ==================== 验证环境 ====================
verify_environment() {
    log_step "=========================================="
    log_step "验证基础环境"
    log_step "=========================================="

    local all_ok=true

    # 检查机器 B 服务
    echo ""
    echo "机器 B ($MACHINE_B_IP):"
    for svc in mysql-inner kafka-inner canal-inner; do
        if docker -H $MACHINE_B ps --filter "name=$svc" --format "{{.Names}}" 2>/dev/null | grep -q "$svc"; then
            echo -e "  $svc: ${GREEN}运行中${NC}"
        else
            echo -e "  $svc: ${RED}未运行${NC}"
            all_ok=false
        fi
    done

    # 检查机器 A 服务
    echo ""
    echo "机器 A ($MACHINE_A_IP):"
    for svc in mysql-outer kafka-outer redis canal-outer registry; do
        if docker -H $MACHINE_A ps --filter "name=$svc" --format "{{.Names}}" 2>/dev/null | grep -q "$svc"; then
            echo -e "  $svc: ${GREEN}运行中${NC}"
        else
            echo -e "  $svc: ${RED}未运行${NC}"
            all_ok=false
        fi
    done

    echo ""

    if $all_ok; then
        log_info "基础环境验证通过！"
        echo ""
        echo "现在可以使用 deploy-registry.sh 部署应用服务："
        echo "  ./deploy-registry.sh all"
        return 0
    else
        log_error "部分服务未运行，请检查"
        return 1
    fi
}

# ==================== 显示状态 ====================
show_status() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "               基础环境状态"
    echo "═══════════════════════════════════════════════════════════"

    echo ""
    echo "机器 B ($MACHINE_B_IP) - 内网基础服务:"
    echo "───────────────────────────────────────────────────────────"
    docker -H $MACHINE_B ps --filter "name=mysql-inner" --filter "name=kafka-inner" --filter "name=canal-inner" \
        --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || log_error "无法连接"

    echo ""
    echo "机器 A ($MACHINE_A_IP) - 外网基础服务:"
    echo "───────────────────────────────────────────────────────────"
    docker -H $MACHINE_A ps --filter "name=mysql-outer" --filter "name=kafka-outer" --filter "name=redis" --filter "name=canal-outer" --filter "name=registry" \
        --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || log_error "无法连接"

    echo ""
}

# ==================== 主流程 ====================
main() {
    local cmd=${1:-"setup"}

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "           穿透网关 - 基础环境初始化工具"
    echo "════════════════════════════════════════════════════════════"
    echo ""

    case $cmd in
        "setup")
            check_connections
            setup_machine_b
            setup_machine_a
            sleep 10
            verify_environment
            ;;

        "status")
            check_connections
            show_status
            verify_environment
            ;;

        "verify")
            check_connections
            verify_environment
            ;;

        "help"|*)
            echo "用法: $0 <命令>"
            echo ""
            echo "命令:"
            echo "  setup    初始化基础环境（首次部署时运行）"
            echo "  status   查看基础环境状态"
            echo "  verify   验证基础环境是否就绪"
            echo ""
            echo "注意:"
            echo "  1. 运行此脚本前，请先在两台机器上通过 docker-compose 启动基础服务"
            echo "  2. 此脚本只需运行一次，之后使用 deploy-registry.sh 部署应用"
            ;;
    esac

    echo ""
}

main "$@"
