#!/bin/bash

# Graviton 性能基准测试 - OS 级别调优脚本
# 用于 Redis、Nginx 等高性能网络服务的系统优化
# 使用方法：source 或直接执行
#   source ./common/os-tuning.sh
#   或: bash ./common/os-tuning.sh [--disable-thp] [--irq-affinity] [--skip-network]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 解析参数
DISABLE_THP=true
IRQ_AFFINITY=false
SKIP_NETWORK=false

for arg in "$@"; do
    case $arg in
        --irq-affinity)   IRQ_AFFINITY=true ;;
        --skip-network)   SKIP_NETWORK=true ;;
        --no-thp)         DISABLE_THP=false ;;
        --help)
            echo "用法: $0 [选项]"
            echo "  --irq-affinity   启用网卡中断亲和性设置（停止 irqbalance）"
            echo "  --skip-network   跳过网络参数调优"
            echo "  --no-thp         不禁用透明大页面"
            exit 0
            ;;
    esac
done

# OS 检测
OS_NAME=$(grep ^NAME /etc/os-release | awk -F '"' '{print $2}')
OS_VERSION=$(grep ^VERSION_ID /etc/os-release | awk -F '"' '{print $2}')
ARCH=$(uname -m)

echo -e "${GREEN}=== OS 级别性能调优 ===${NC}"
echo "操作系统: $OS_NAME $OS_VERSION"
echo "CPU 架构: $ARCH"
echo "CPU 核数: $(nproc)"
echo ""

if [[ "$OS_NAME" == "Amazon Linux" ]] && [[ "$OS_VERSION" == "2023" ]]; then
    echo -e "${GREEN}[OK] Amazon Linux 2023${NC}"
else
    echo -e "${YELLOW}[WARN] 非 Amazon Linux 2023，部分优化可能不适用${NC}"
fi

# 1. 禁用透明大页面（THP）
if $DISABLE_THP; then
    echo ""
    echo "[1] 禁用透明大页面 (THP)..."
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    echo never > /sys/kernel/mm/transparent_hugepage/defrag

    # 持久化
    if ! grep -q "transparent_hugepage" /etc/rc.local 2>/dev/null; then
        cat >> /etc/rc.local << 'RCEOF'
if test -f /sys/kernel/mm/transparent_hugepage/enabled; then
  echo never > /sys/kernel/mm/transparent_hugepage/enabled
fi
if test -f /sys/kernel/mm/transparent_hugepage/defrag; then
  echo never > /sys/kernel/mm/transparent_hugepage/defrag
fi
RCEOF
        chmod +x /etc/rc.local
    fi
    echo -e "${GREEN}  THP 已禁用${NC}"
fi

# 2. 网络参数调优
if ! $SKIP_NETWORK; then
    echo "[2] 网络参数调优..."
    cat > /etc/sysctl.d/99-benchmark-network.conf << 'EOF'
# === 网络队列和缓冲区 ===
net.core.netdev_max_backlog = 250000
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 16777216
net.core.wmem_default = 16777216
net.core.optmem_max = 16777216
net.core.somaxconn = 65535

# === TCP 优化 ===
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_max_syn_backlog = 30000
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_window_scaling = 1

# === BBR 拥塞控制 ===
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq

# === 端口范围 ===
net.ipv4.ip_local_port_range = 1024 65535

# === 软中断优化 ===
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 10000
net.core.dev_weight = 600

# === 禁用 IPv6 ===
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# === 内存管理 ===
vm.swappiness = 0
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.min_free_kbytes = 1048576
vm.zone_reclaim_mode = 0
vm.max_map_count = 1048576
vm.overcommit_memory = 1

# === 文件系统 ===
fs.file-max = 20000000
fs.nr_open = 20000000
fs.aio-max-nr = 1048576
fs.inotify.max_user_watches = 524288
EOF
    sysctl -p /etc/sysctl.d/99-benchmark-network.conf > /dev/null 2>&1
    echo -e "${GREEN}  网络参数已优化${NC}"
fi

# 3. 文件描述符限制
echo "[3] 文件描述符限制..."
if ! grep -q "# benchmark-tuning" /etc/security/limits.conf 2>/dev/null; then
    cat >> /etc/security/limits.conf << 'EOF'
# benchmark-tuning
root soft nofile 1000000
root hard nofile 1000000
root soft nproc 65535
root hard nproc 65535
* soft nofile 1000000
* hard nofile 1000000
EOF
fi
echo -e "${GREEN}  文件描述符限制已设置${NC}"

# 4. 网卡中断亲和性（可选）
if $IRQ_AFFINITY; then
    echo "[4] 网卡中断亲和性..."
    systemctl stop irqbalance 2>/dev/null || true
    IFACE=$(ip route | grep default | awk '{print $5}')
    if [ -n "$IFACE" ]; then
        irqs=$(grep "${IFACE}-Tx-Rx" /proc/interrupts | awk -F':' '{print $1}')
        cpu=0
        for i in $irqs; do
            echo $cpu > /proc/irq/$i/smp_affinity_list 2>/dev/null || true
            cpu=$((cpu + 1))
        done
        echo -e "${GREEN}  中断亲和性已设置 (接口: $IFACE)${NC}"
    else
        echo -e "${YELLOW}  未检测到默认网络接口${NC}"
    fi
else
    echo "[4] 网卡中断亲和性: 跳过（使用 --irq-affinity 启用）"
fi

echo ""
echo -e "${GREEN}=== OS 调优完成 ===${NC}"
echo ""
echo "当前关键参数:"
echo "  TCP 拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
echo "  THP 状态: $(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)"
echo "  文件描述符上限: $(sysctl -n fs.file-max 2>/dev/null)"
echo "  vm.overcommit_memory: $(sysctl -n vm.overcommit_memory 2>/dev/null)"
