#!/bin/bash
#
# 通过私有 Registry 远程部署脚本
#
# 使用方法:
#   ./deploy-registry.sh all      # 部署所有应用服务
#   ./deploy-registry.sh outer    # 只部署机器 A 的服务
#   ./deploy-registry.sh inner    # 只部署机器 B 的服务
#   ./deploy-registry.sh status   # 查看服务状态
#   ./deploy-registry.sh test     # 运行端到端测试
#

set -e

# ==================== 配置 ====================
REGISTRY="192.168.123.66:5000"
MACHINE_A="tcp://192.168.123.66:2375"
MACHINE_B="tcp://192.168.123.81:2375"
MACHINE_A_IP="192.168.123.66"
MACHINE_B_IP="192.168.123.81"

# Docker 网络名称
OUTER_NET="outer-server_outer_net"
INNER_NET="inner-server_inner_net"

# 设置 Docker API 版本
export DOCKER_API_VERSION=1.44

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==================== 检查 Registry 连接 ====================
check_registry() {
    log_info "检查 Registry 连接..."
    if curl -s --connect-timeout 5 "http://${REGISTRY}/v2/_catalog" > /dev/null 2>&1; then
        log_info "Registry 连接正常 (http://${REGISTRY})"
    else
        log_error "无法连接到 Registry: ${REGISTRY}"
        log_error "请确保 Registry 服务已启动"
        exit 1
    fi
}

# ==================== 构建并推送镜像 ====================
build_and_push() {
    local path=$1
    local name=$2

    log_info "构建 $name..."
    docker -H $MACHINE_A build -t $REGISTRY/$name:latest ./$path

    log_info "推送 $name 到 Registry..."
    docker -H $MACHINE_A push $REGISTRY/$name:latest
}

# ==================== 部署机器 A 服务 ====================
deploy_scp0005() {
    log_info "部署 scp0005 到机器 A..."
    docker -H $MACHINE_A pull $REGISTRY/scp0005:latest
    docker -H $MACHINE_A stop scp0005 2>/dev/null || true
    docker -H $MACHINE_A rm scp0005 2>/dev/null || true

    # 启动容器，使用 IP 地址配置
    docker -H $MACHINE_A run -d \
        --name scp0005 \
        -p 8080:8080 \
        -e INNER_DB_HOST=$MACHINE_B_IP \
        -e INNER_DB_PORT=3306 \
        -e INNER_DB_NAME=inner_gateway \
        -e INNER_DB_USER=root \
        -e INNER_DB_PASSWORD=root123 \
        -e REDIS_HOST=redis \
        -e REDIS_PORT=6379 \
        $REGISTRY/scp0005:latest

    # 连接到 docker-compose 网络（用于访问 redis）
    docker -H $MACHINE_A network connect $OUTER_NET scp0005 2>/dev/null || true
    log_info "scp0005 已部署并连接到网络"
}

deploy_outer_consumer() {
    log_info "部署 outer-consumer 到机器 A..."
    docker -H $MACHINE_A pull $REGISTRY/outer-consumer:latest
    docker -H $MACHINE_A stop outer-consumer 2>/dev/null || true
    docker -H $MACHINE_A rm outer-consumer 2>/dev/null || true

    # 启动容器，使用容器名配置（同一网络内可解析）
    docker -H $MACHINE_A run -d \
        --name outer-consumer \
        -p 8081:8081 \
        -e REDIS_HOST=redis \
        -e REDIS_PORT=6379 \
        -e KAFKA_BOOTSTRAP=kafka:9092 \
        -e KAFKA_TOPIC=outer_response_binlog \
        -e RESULT_KEY_PREFIX=gateway:result: \
        $REGISTRY/outer-consumer:latest

    # 连接到 docker-compose 网络
    docker -H $MACHINE_A network connect $OUTER_NET outer-consumer 2>/dev/null || true
    log_info "outer-consumer 已部署并连接到网络"
}

# ==================== 部署机器 B 服务 ====================
deploy_scp0006() {
    log_info "部署 scp0006 到机器 B..."
    docker -H $MACHINE_B pull $REGISTRY/scp0006:latest
    docker -H $MACHINE_B stop scp0006 2>/dev/null || true
    docker -H $MACHINE_B rm scp0006 2>/dev/null || true

    # 启动容器
    docker -H $MACHINE_B run -d \
        --name scp0006 \
        -p 8082:8082 \
        -e OUTER_DB_HOST=$MACHINE_A_IP \
        -e OUTER_DB_PORT=3306 \
        -e OUTER_DB_NAME=outer_gateway \
        -e OUTER_DB_USER=root \
        -e OUTER_DB_PASSWORD=root123 \
        -e KAFKA_BOOTSTRAP=kafka:9092 \
        -e KAFKA_TOPIC=inner_request_binlog \
        -e TARGET_SERVICE_URL=http://target-service:8083 \
        $REGISTRY/scp0006:latest

    # 连接到 docker-compose 网络（用于访问 kafka 和 target-service）
    docker -H $MACHINE_B network connect $INNER_NET scp0006 2>/dev/null || true
    log_info "scp0006 已部署并连接到网络"
}

deploy_target_service() {
    log_info "部署 target-service 到机器 B..."
    docker -H $MACHINE_B pull $REGISTRY/target-service:latest
    docker -H $MACHINE_B stop target-service 2>/dev/null || true
    docker -H $MACHINE_B rm target-service 2>/dev/null || true

    # 启动容器
    docker -H $MACHINE_B run -d \
        --name target-service \
        -p 8083:8083 \
        -e SERVER_PORT=8083 \
        -e MOCK_DELAY_MS=50 \
        -e MOCK_ERROR_RATE=0 \
        $REGISTRY/target-service:latest

    # 连接到 docker-compose 网络
    docker -H $MACHINE_B network connect $INNER_NET target-service 2>/dev/null || true
    log_info "target-service 已部署并连接到网络"
}

# ==================== 端到端测试 ====================
run_e2e_test() {
    log_info "等待服务就绪..."
    sleep 5

    log_info "执行端到端测试..."
    local response=$(curl -s -X POST "http://${MACHINE_A_IP}:8080/inner/c1/yhzx" \
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
    echo "                    服务状态"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "机器 A (192.168.123.66) - 外网:"
    echo "─────────────────────────────────────────────────────────────"
    docker -H $MACHINE_A ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || log_error "无法连接机器 A"
    echo ""
    echo "机器 B (192.168.123.81) - 内网:"
    echo "─────────────────────────────────────────────────────────────"
    docker -H $MACHINE_B ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || log_error "无法连接机器 B"
    echo ""
}

# ==================== 查看日志 ====================
show_logs() {
    local service=$1
    local lines=${2:-50}

    case $service in
        scp0005|outer-consumer|canal-outer|mysql-outer|redis|kafka-outer)
            docker -H $MACHINE_A logs $service --tail $lines
            ;;
        scp0006|target-service|canal-inner|mysql-inner|kafka-inner)
            docker -H $MACHINE_B logs $service --tail $lines
            ;;
        *)
            log_error "未知服务: $service"
            echo "可用服务: scp0005, outer-consumer, scp0006, target-service, canal-outer, canal-inner"
            ;;
    esac
}

# ==================== 主流程 ====================
main() {
    local cmd=${1:-"help"}

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "              穿透网关 - 应用部署工具"
    echo "════════════════════════════════════════════════════════════"
    echo "Registry: $REGISTRY"
    echo ""

    case $cmd in
        "all")
            check_registry

            log_info "======== 构建镜像 ========"
            build_and_push "outer-server/scp0005" "scp0005"
            build_and_push "outer-server/outer-consumer" "outer-consumer"
            build_and_push "inner-server/scp0006" "scp0006"
            build_and_push "inner-server/target-service" "target-service"

            log_info "======== 部署服务 ========"
            deploy_scp0005
            deploy_outer_consumer
            deploy_scp0006
            deploy_target_service

            log_info "======== 验证部署 ========"
            run_e2e_test || log_warn "测试未通过，请检查日志"

            show_status
            ;;

        "outer")
            check_registry
            build_and_push "outer-server/scp0005" "scp0005"
            build_and_push "outer-server/outer-consumer" "outer-consumer"
            deploy_scp0005
            deploy_outer_consumer
            show_status
            ;;

        "inner")
            check_registry
            build_and_push "inner-server/scp0006" "scp0006"
            build_and_push "inner-server/target-service" "target-service"
            deploy_scp0006
            deploy_target_service
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
                echo "可用服务: scp0005, outer-consumer, scp0006, target-service, canal-outer, canal-inner"
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
            echo "命令:"
            echo "  all      构建并部署所有应用服务（推荐）"
            echo "  outer    只部署机器 A 的服务 (scp0005, outer-consumer)"
            echo "  inner    只部署机器 B 的服务 (scp0006, target-service)"
            echo "  status   查看所有服务状态"
            echo "  test     运行端到端测试"
            echo "  logs     查看服务日志: $0 logs <service> [lines]"
            echo "  images   查看 Registry 中的镜像"
            echo ""
            echo "示例:"
            echo "  $0 all           # 修改代码后，一键部署"
            echo "  $0 status        # 查看服务状态"
            echo "  $0 test          # 验证部署是否成功"
            echo "  $0 logs scp0005  # 查看 scp0005 日志"
            ;;
    esac

    echo ""
    log_info "完成!"
}

main "$@"
