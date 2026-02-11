#!/bin/bash

# Graviton 性能基准测试 - Redis 服务端安装配置脚本
# 在被测 Redis 服务器上运行
# 使用方法：sudo bash redis-server-setup.sh
#
# 推荐实例:
#   Graviton: r8g.2xlarge
#   x86:      r7i.2xlarge
# OS: Amazon Linux 2023
# EBS: gp3 40GB

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REDIS_VERSION="${REDIS_VERSION:-7.0.15}"

echo "=== Redis 服务端安装配置 ==="
echo "Redis 版本: $REDIS_VERSION"
echo "CPU 核数: $(nproc)"
echo "内存总量: $(free -h | grep Mem | awk '{print $2}')"
echo ""

# OS 检测
OS_NAME=$(grep ^NAME /etc/os-release | awk -F '"' '{print $2}')
OS_VERSION=$(grep ^VERSION_ID /etc/os-release | awk -F '"' '{print $2}')

if [[ "$OS_NAME" != "Amazon Linux" ]] || [[ "$OS_VERSION" != "2023" ]]; then
    echo "警告: 推荐在 Amazon Linux 2023 上运行"
fi

# 1. 安装依赖
echo "[1/4] 安装依赖..."
yum update -y -q
yum install -y -q python3-pip docker
pip3 install -q dool
systemctl enable docker
systemctl start docker

# 2. OS 调优
echo "[2/4] OS 调优..."
if [ -f "$SCRIPT_DIR/../common/os-tuning.sh" ]; then
    bash "$SCRIPT_DIR/../common/os-tuning.sh"
else
    echo "  警告: 未找到 os-tuning.sh，跳过 OS 调优"
    echo "  请手动运行: bash common/os-tuning.sh"
fi

# 3. 拉取 Redis 镜像
echo "[3/4] 拉取 Redis 镜像..."
docker pull "redis:$REDIS_VERSION"

# 4. 启动 Redis 实例
echo "[4/4] 启动 Redis 实例..."

# 计算内存上限 (总内存的 80%)
MEM_TOTAL_GB=$(free -g | grep Mem | awk '{print $2}')
MAX_MEM=$((MEM_TOTAL_GB * 80 / 100))

# 计算 IO 线程数
CPU_CORES=$(nproc)
IO_40=$((CPU_CORES * 40 / 100))
IO_65=$((CPU_CORES * 65 / 100))
IO_90=$((CPU_CORES * 90 / 100))

# 确保 io-threads 至少为 1
[ "$IO_40" -lt 1 ] && IO_40=1
[ "$IO_65" -lt 1 ] && IO_65=1
[ "$IO_90" -lt 1 ] && IO_90=1

echo ""
echo "内存配额: ${MAX_MEM}GB / ${MEM_TOTAL_GB}GB"
echo "IO 线程配置: $IO_40 (40%), $IO_65 (65%), $IO_90 (90%)"
echo ""

sysctl -w vm.overcommit_memory=1 > /dev/null

# 停止并清理旧容器
for name in redis-6379 redis-$((8000 + IO_40)) redis-$((8000 + IO_65)) redis-$((8000 + IO_90)); do
    docker rm -f "$name" 2>/dev/null || true
done

# 实例 1：单线程 Redis（基线，端口 6379）
cat > /root/redis-6379.conf << EOF
port 6379
bind 0.0.0.0
protected-mode no
maxmemory ${MAX_MEM}gb
maxmemory-policy allkeys-lru
EOF

docker run -d --name redis-6379 --restart=always \
    -p 6379:6379 \
    -v /root/redis-6379.conf:/etc/redis/redis.conf \
    "redis:$REDIS_VERSION" \
    redis-server /etc/redis/redis.conf

# 实例 2-4：多 IO 线程模式
for IO_THREADS in $IO_40 $IO_65 $IO_90; do
    PORT=$((8000 + IO_THREADS))
    cat > "/root/redis-${PORT}.conf" << EOF
bind 0.0.0.0
port 6379
protected-mode no
maxmemory ${MAX_MEM}gb
maxmemory-policy allkeys-lru
io-threads-do-reads yes
io-threads $IO_THREADS
EOF

    docker run -d --name "redis-${PORT}" --restart=always \
        -p "${PORT}:6379" \
        -v "/root/redis-${PORT}.conf:/etc/redis/redis.conf" \
        "redis:$REDIS_VERSION" \
        redis-server /etc/redis/redis.conf
done

sleep 3

echo ""
echo "=== Redis 实例状态 ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep redis
echo ""

echo "Redis 端口映射:"
echo "  6379              -> 单线程（基线）"
echo "  $((8000 + IO_40)) -> io-threads=$IO_40 (40% CPU)"
echo "  $((8000 + IO_65)) -> io-threads=$IO_65 (65% CPU)"
echo "  $((8000 + IO_90)) -> io-threads=$IO_90 (90% CPU)"
echo ""
echo "=== Redis 服务端安装完成 ==="
