#!/bin/bash

# Graviton 性能基准测试 - Redis memtier_benchmark 运行脚本
# 在测试客户端机器上运行（非 Redis 服务器）
# 使用方法：bash redis-benchmark.sh <redis-ip> <port> <test-time-seconds>
#
# 推荐客户端实例: c6i.4xlarge (x86, 确保客户端不是瓶颈)
# OS: Amazon Linux 2023
#
# 前置依赖 (在客户端安装):
#   yum install -y autoconf automake make gcc gcc-c++ \
#     pcre pcre-devel zlib-devel libmemcached-devel libevent-devel openssl-devel
#   git clone https://github.com/RedisLabs/memtier_benchmark.git
#   cd memtier_benchmark && git checkout tags/2.0.0
#   autoreconf -ivf && ./configure && make -j && make install
#
#   wget https://download.redis.io/releases/redis-7.2.4.tar.gz
#   tar xzf redis-7.2.4.tar.gz && cd redis-7.2.4
#   make && make install   # 提供 redis-cli

set -e

SUT_IP="${1}"
SUT_PORT="${2:-6379}"
TEST_TIME="${3:-60}"

if [ -z "$SUT_IP" ]; then
    echo "用法: $0 <redis-ip> [port] [test-time-seconds]"
    echo ""
    echo "示例:"
    echo "  $0 172.31.1.100 6379 60       # 测试单线程 Redis"
    echo "  $0 172.31.1.100 8003 60       # 测试 io-threads=3 模式"
    echo ""
    echo "参数:"
    echo "  redis-ip           Redis 服务器 IP 地址"
    echo "  port               Redis 端口 (默认: 6379)"
    echo "  test-time-seconds  每轮测试时长 (默认: 60)"
    exit 1
fi

# 检查依赖
for cmd in memtier_benchmark redis-cli; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "错误: $cmd 未安装"
        echo "请参考脚本头部注释安装依赖"
        exit 1
    fi
done

RESULT_DIR="/root/benchmark-results/redis"
mkdir -p "$RESULT_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ARCH=$(uname -m)

echo "=== Redis 性能基准测试 ==="
echo "目标: $SUT_IP:$SUT_PORT"
echo "测试时长: ${TEST_TIME}s / 轮"
echo "客户端架构: $ARCH"
echo "结果目录: $RESULT_DIR"
echo ""

# 连通性检查
if ! redis-cli -h "$SUT_IP" -p "$SUT_PORT" ping 2>/dev/null | grep -q PONG; then
    echo "错误: 无法连接到 Redis $SUT_IP:$SUT_PORT"
    exit 1
fi

THREAD_LIST="1 2 4 8 16 32 64"

echo "线程列表: $THREAD_LIST"
echo "每个线程 4 个客户端连接"
echo "数据模式: 随机 1-4096 字节, 读写比 1:4"
echo "每组运行 3 次取平均"
echo ""

for THREADS in $THREAD_LIST; do
    echo "--- 测试: threads=$THREADS ---"

    # 清空数据
    redis-cli -h "$SUT_IP" -p "$SUT_PORT" flushall > /dev/null 2>&1

    RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}_${SUT_IP}_${SUT_PORT}_t${THREADS}.txt"

    memtier_benchmark \
        --server "$SUT_IP" \
        --port "$SUT_PORT" \
        --threads "$THREADS" \
        --clients 4 \
        --test-time "$TEST_TIME" \
        --random-data \
        --data-size-range=1-4096 \
        --data-size-pattern=S \
        --hide-histogram \
        --run-count=3 \
        --ratio=1:4 \
        --out-file="$RESULT_FILE"

    # 提取关键指标
    if [ -f "$RESULT_FILE" ]; then
        OPS=$(grep "Totals" "$RESULT_FILE" | tail -1 | awk '{print $2}')
        LATENCY=$(grep "Totals" "$RESULT_FILE" | tail -1 | awk '{print $5}')
        echo "  OPS/sec: $OPS  |  Avg Latency: ${LATENCY}ms"
    fi

    echo ""
done

echo "=== 测试完成 ==="
echo "结果文件: ${RESULT_DIR}/${TIMESTAMP}_*.txt"
echo ""
echo "汇总所有结果:"
echo "  grep 'Totals' ${RESULT_DIR}/${TIMESTAMP}_*.txt"
