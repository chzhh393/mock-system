#!/bin/bash
#
# 机器C/D 远程部署脚本（沙箱环境专用）
#
# 特点：
#   - 无需 SSH 和 Maven
#   - 通过远程 Docker Daemon 部署
#   - 通过私有 Registry 分发镜像
#
# 使用方法:
#   ./deploy-cd.sh all       # 部署所有应用服务
#   ./deploy-cd.sh outer     # 只部署机器C的服务 (scp0005, outer-consumer)
#   ./deploy-cd.sh inner     # 只部署机器D的服务 (scp0006, target-service)
#   ./deploy-cd.sh scp0006   # 只部署 scp0006
#   ./deploy-cd.sh status    # 查看服务状态
#   ./deploy-cd.sh test      # 运行端到端测试
#   ./deploy-cd.sh logs <服务名>  # 查看日志
#

set -e

# ==================== 配置 ====================
REGISTRY="192.168.123.113:5000"
MACHINE_C="tcp://192.168.123.113:2375"  # 外网
MACHINE_D="tcp://192.168.123.114:2375"  # 内网
MACHINE_C_IP="192.168.123.113"
MACHINE_D_IP="192.168.123.114"

# Docker 网络名称（与 deploy-registryCD.sh init 创建的网络一致）
OUTER_NET="outer_net"
INNER_NET="inner_net"

# 设置 Docker API 版本（兼容较新版本 Docker）
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

# ==================== 检查 Registry 连接 ====================
check_registry() {
    log_info "检查 Registry 连接..."
    if curl -s --connect-timeout 5 "http://${REGISTRY}/v2/_catalog" > /dev/null 2>&1; then
        log_info "Registry 连接正常 (http://${REGISTRY})"
    else
        log_error "无法连接到 Registry: ${REGISTRY}"
        exit 1
    fi
}

# ==================== 检查 Docker Daemon 连接 ====================
check_docker() {
    log_info "检查 Docker Daemon 连接..."

    if docker -H $MACHINE_C info > /dev/null 2>&1; then
        log_info "机器C Docker 连接正常"
    else
        log_error "无法连接机器C Docker: $MACHINE_C"
        exit 1
    fi

    if docker -H $MACHINE_D info > /dev/null 2>&1; then
        log_info "机器D Docker 连接正常"
    else
        log_error "无法连接机器D Docker: $MACHINE_D"
        exit 1
    fi
}

# ==================== 构建并推送镜像 ====================
build_and_push() {
    local path=$1
    local name=$2

    log_step "构建 $name..."
    docker -H $MACHINE_C build -t $REGISTRY/$name:latest ./$path

    log_info "推送 $name 到 Registry..."
    docker -H $MACHINE_C push $REGISTRY/$name:latest
}

# ==================== 部署机器C服务 ====================
deploy_scp0005() {
    log_step "部署 scp0005 到机器C..."
    docker -H $MACHINE_C pull $REGISTRY/scp0005:latest
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
    log_step "部署 outer-consumer 到机器C..."
    docker -H $MACHINE_C pull $REGISTRY/outer-consumer:latest
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

# ==================== 部署机器D服务 ====================
deploy_scp0006() {
    log_step "部署 scp0006 到机器D..."
    docker -H $MACHINE_D pull $REGISTRY/scp0006:latest
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
    log_step "部署 target-service 到机器D..."
    docker -H $MACHINE_D pull $REGISTRY/target-service:latest
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
        -d "code=yhzx&paramData={\"test\":\"deploy-test\"}" \
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
    echo "机器 C ($MACHINE_C_IP) - 外网:"
    echo "─────────────────────────────────────────────────────────────"
    docker -H $MACHINE_C ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || log_error "无法连接机器C"
    echo ""
    echo "机器 D ($MACHINE_D_IP) - 内网:"
    echo "─────────────────────────────────────────────────────────────"
    docker -H $MACHINE_D ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || log_error "无法连接机器D"
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
            echo "机器C服务: scp0005, outer-consumer, canal-outer, mysql-outer, redis, kafka-outer"
            echo "机器D服务: scp0006, target-service, canal-inner, mysql-inner, kafka-inner"
            ;;
    esac
}

# ==================== 主流程 ====================
main() {
    local cmd=${1:-"help"}

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "          穿透网关 - 机器C/D 部署工具（沙箱版）"
    echo "════════════════════════════════════════════════════════════"
    echo "机器C (外网): $MACHINE_C_IP"
    echo "机器D (内网): $MACHINE_D_IP"
    echo "Registry: $REGISTRY"
    echo ""

    case $cmd in
        "all")
            check_registry
            check_docker

            log_step "======== 构建镜像 ========"
            build_and_push "outer-server/scp0005" "scp0005"
            build_and_push "outer-server/outer-consumer" "outer-consumer"
            build_and_push "inner-server/scp0006" "scp0006"
            build_and_push "inner-server/target-service" "target-service"

            log_step "======== 部署服务 ========"
            deploy_scp0005
            deploy_outer_consumer
            deploy_target_service
            deploy_scp0006

            log_step "======== 验证部署 ========"
            run_e2e_test || log_warn "测试未通过，请检查日志"

            show_status
            ;;

        "outer")
            check_registry
            check_docker
            build_and_push "outer-server/scp0005" "scp0005"
            build_and_push "outer-server/outer-consumer" "outer-consumer"
            deploy_scp0005
            deploy_outer_consumer
            show_status
            ;;

        "inner")
            check_registry
            check_docker
            build_and_push "inner-server/scp0006" "scp0006"
            build_and_push "inner-server/target-service" "target-service"
            deploy_target_service
            deploy_scp0006
            show_status
            ;;

        "scp0006")
            check_registry
            check_docker
            build_and_push "inner-server/scp0006" "scp0006"
            deploy_scp0006
            show_status
            ;;

        "status")
            check_docker
            show_status
            ;;

        "test")
            run_e2e_test
            ;;

        "logs")
            if [ -z "$2" ]; then
                log_error "请指定服务名: $0 logs <service> [lines]"
                echo "机器C服务: scp0005, outer-consumer, canal-outer, mysql-outer, redis, kafka-outer"
                echo "机器D服务: scp0006, target-service, canal-inner, mysql-inner, kafka-inner"
            else
                show_logs "$2" "${3:-50}"
            fi
            ;;

        "images")
            log_info "Registry 中的镜像:"
            curl -s "http://${REGISTRY}/v2/_catalog" | python3 -m json.tool 2>/dev/null || curl -s "http://${REGISTRY}/v2/_catalog"
            ;;

        "help"|*)
            echo "用法: $0 <命令>"
            echo ""
            echo "部署命令:"
            echo "  all       构建并部署所有应用服务"
            echo "  outer     只部署机器C的服务 (scp0005, outer-consumer)"
            echo "  inner     只部署机器D的服务 (scp0006, target-service)"
            echo "  scp0006   只构建并部署 scp0006（快速迭代用）"
            echo ""
            echo "查看命令:"
            echo "  status    查看所有服务状态"
            echo "  test      运行端到端测试"
            echo "  logs      查看服务日志: $0 logs <service> [lines]"
            echo "  images    查看 Registry 中的镜像"
            echo ""
            echo "示例:"
            echo "  $0 all            # 首次部署所有服务"
            echo "  $0 scp0006        # 修改 scp0006 后快速部署"
            echo "  $0 status         # 查看服务状态"
            echo "  $0 logs scp0006   # 查看 scp0006 日志"
            ;;
    esac

    echo ""
    log_info "完成!"
}

main "$@"
