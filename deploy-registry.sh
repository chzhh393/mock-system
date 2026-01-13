#!/bin/bash
#
# 通过私有 Registry 远程部署脚本
# 无需 SSH，直接使用 Docker TCP 命令
#

set -e

# ==================== 配置 ====================
REGISTRY="192.168.123.66:5000"
MACHINE_A="tcp://192.168.123.66:2375"
MACHINE_B="tcp://192.168.123.81:2375"

# Docker API 版本（远程机器需要 1.44，本地构建不设置）
# export DOCKER_API_VERSION=1.44

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==================== 检查连接 ====================
check_connections() {
    log_info "检查连接..."

    # 检查 Registry
    if curl -s "http://${REGISTRY}/v2/_catalog" > /dev/null 2>&1; then
        log_info "✓ Registry ($REGISTRY) 可访问"
    else
        log_error "✗ Registry ($REGISTRY) 无法访问"
        exit 1
    fi

    # 检查机器 A
    if docker -H $MACHINE_A ps > /dev/null 2>&1; then
        log_info "✓ 机器 A ($MACHINE_A) 可访问"
    else
        log_error "✗ 机器 A ($MACHINE_A) 无法访问"
        exit 1
    fi

    # 检查机器 B
    if docker -H $MACHINE_B ps > /dev/null 2>&1; then
        log_info "✓ 机器 B ($MACHINE_B) 可访问"
    else
        log_error "✗ 机器 B ($MACHINE_B) 无法访问"
        exit 1
    fi
}

# ==================== 构建并推送镜像 ====================
build_and_push() {
    local path=$1
    local name=$2

    log_info "构建 $name..."
    docker build -t $name:latest ./$path

    log_info "推送 $name 到 Registry..."
    docker tag $name:latest $REGISTRY/$name:latest
    docker push $REGISTRY/$name:latest
}

# ==================== 部署到远程 ====================
deploy_to() {
    local host=$1
    local name=$2
    local port=$3
    local env_vars=$4

    log_info "部署 $name 到 $host..."

    # 拉取镜像
    docker -H $host pull $REGISTRY/$name:latest

    # 停止并删除旧容器
    docker -H $host stop $name 2>/dev/null || true
    docker -H $host rm $name 2>/dev/null || true

    # 启动新容器
    if [ -n "$env_vars" ]; then
        docker -H $host run -d --name $name -p $port $env_vars $REGISTRY/$name:latest
    else
        docker -H $host run -d --name $name -p $port $REGISTRY/$name:latest
    fi

    log_info "✓ $name 部署完成"
}

# ==================== 主流程 ====================
main() {
    local cmd=${1:-"all"}

    echo "════════════════════════════════════════════"
    echo "   通过私有 Registry 远程部署"
    echo "════════════════════════════════════════════"
    echo ""
    echo "Registry: $REGISTRY"
    echo "机器 A:   $MACHINE_A"
    echo "机器 B:   $MACHINE_B"
    echo ""

    check_connections

    case $cmd in
        "all")
            # 构建并推送所有镜像
            log_info "========== 构建并推送镜像 =========="
            build_and_push "outer-server/scp0005" "scp0005"
            build_and_push "outer-server/outer-consumer" "outer-consumer"
            build_and_push "inner-server/scp0006" "scp0006"
            build_and_push "inner-server/target-service" "target-service"

            # 部署到机器 A
            log_info "========== 部署到机器 A =========="
            deploy_to "$MACHINE_A" "scp0005" "8080:8080"
            deploy_to "$MACHINE_A" "outer-consumer" "8081:8081"

            # 部署到机器 B
            log_info "========== 部署到机器 B =========="
            deploy_to "$MACHINE_B" "scp0006" "8082:8082"
            deploy_to "$MACHINE_B" "target-service" "8017:8017"
            ;;

        "outer")
            log_info "========== 部署 outer-server 服务 =========="
            build_and_push "outer-server/scp0005" "scp0005"
            build_and_push "outer-server/outer-consumer" "outer-consumer"
            deploy_to "$MACHINE_A" "scp0005" "8080:8080"
            deploy_to "$MACHINE_A" "outer-consumer" "8081:8081"
            ;;

        "inner")
            log_info "========== 部署 inner-server 服务 =========="
            build_and_push "inner-server/scp0006" "scp0006"
            build_and_push "inner-server/target-service" "target-service"
            deploy_to "$MACHINE_B" "scp0006" "8082:8082"
            deploy_to "$MACHINE_B" "target-service" "8017:8017"
            ;;

        "status")
            log_info "========== 服务状态 =========="
            echo ""
            echo "机器 A (192.168.123.66):"
            docker -H $MACHINE_A ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            echo ""
            echo "机器 B (192.168.123.81):"
            docker -H $MACHINE_B ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            ;;

        "images")
            log_info "========== Registry 镜像 =========="
            curl -s "http://${REGISTRY}/v2/_catalog" | python3 -m json.tool
            ;;

        *)
            echo "用法: $0 [all|outer|inner|status|images]"
            echo ""
            echo "  all     - 构建并部署所有服务"
            echo "  outer   - 只部署 outer-server 服务 (机器 A)"
            echo "  inner   - 只部署 inner-server 服务 (机器 B)"
            echo "  status  - 查看所有服务状态"
            echo "  images  - 查看 Registry 中的镜像"
            exit 1
            ;;
    esac

    echo ""
    log_info "════════════════════════════════════════════"
    log_info "   完成！"
    log_info "════════════════════════════════════════════"
}

main "$@"
