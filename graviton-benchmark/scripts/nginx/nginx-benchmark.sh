#!/bin/bash

# Graviton 性能基准测试 - Nginx WRK 压测脚本
# 在测试客户端机器上运行
# 使用方法：bash nginx-benchmark.sh <lb-ip> [resource-file]
#
# 推荐客户端实例: c7a.4xlarge (x86, 确保客户端不是瓶颈)
# OS: Amazon Linux 2023
#
# 前置依赖 (在客户端安装):
#   yum -y group install development
#   cd /root && wget https://github.com/wg/wrk/archive/refs/tags/4.2.0.tar.gz
#   tar zxf 4.2.0.tar.gz && cd wrk-4.2.0 && make -j

set -e

SUT_IP="${1}"
RESOURCE_FILE="${2:-1kb.bin}"

if [ -z "$SUT_IP" ]; then
    echo "用法: $0 <lb-ip> [resource-file]"
    echo ""
    echo "示例:"
    echo "  $0 10.0.1.30              # 测试默认 1kb.bin"
    echo "  $0 10.0.1.30 100kb.bin    # 测试 100KB 文件"
    echo "  $0 10.0.1.30 test.html    # 测试 HTML 页面"
    echo ""
    echo "资源文件 (在 web 服务器上生成):"
    echo "  0kb.bin, 1kb.bin, 10kb.bin, 100kb.bin, 1mb.bin, test.html"
    exit 1
fi

# 检查 WRK
WRK_BIN="${WRK_BIN:-$HOME/wrk-4.2.0/wrk}"
if [ ! -f "$WRK_BIN" ]; then
    WRK_BIN=$(which wrk 2>/dev/null || true)
fi
if [ -z "$WRK_BIN" ] || [ ! -f "$WRK_BIN" ]; then
    echo "错误: WRK 未找到"
    echo "请安装 WRK 或设置 WRK_BIN 环境变量"
    echo ""
    echo "安装方法:"
    echo "  yum -y group install development"
    echo "  cd /root && wget https://github.com/wg/wrk/archive/refs/tags/4.2.0.tar.gz"
    echo "  tar zxf 4.2.0.tar.gz && cd wrk-4.2.0 && make -j"
    exit 1
fi

WRK_DIR=$(dirname "$WRK_BIN")
RESULT_DIR="/root/benchmark-results/nginx"
mkdir -p "$RESULT_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "unknown")

echo "=== Nginx 性能基准测试 (WRK) ==="
echo "目标: https://$SUT_IP/$RESOURCE_FILE"
echo "WRK: $WRK_BIN"
echo "客户端实例: $INSTANCE_TYPE"
echo ""

THREADS=8
CONNECTIONS="10 20 30 40 60 80 100 150 200 300"
DURATION="3m"

RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}_${SUT_IP}_${RESOURCE_FILE}.txt"

echo "线程数: $THREADS"
echo "连接数列表: $CONNECTIONS"
echo "测试时长: $DURATION / 轮"
echo "结果文件: $RESULT_FILE"
echo ""
echo "Connections, RPS, p50(us), p90(us), p99(us), p99.99(us)" | tee "$RESULT_FILE"
echo "---" | tee -a "$RESULT_FILE"

for CONN in $CONNECTIONS; do
    # 生成 Lua 报告脚本
    cat > "${WRK_DIR}/report.lua" << LUAEOF
done = function(summary, latency, requests)
   rps = summary.requests / (summary.duration/1000/1000)
   io.write(string.format("%s, RPS, %.0f, %d, %d, %d, %d\n", "$CONN", rps, latency:percentile(50), latency:percentile(90), latency:percentile(99), latency:percentile(99.99)))
end
LUAEOF

    echo -n "  connections=$CONN ... "

    "$WRK_BIN" \
        --threads "$THREADS" \
        --connections "$CONN" \
        --duration "$DURATION" \
        --script "${WRK_DIR}/report.lua" \
        "https://${SUT_IP}/${RESOURCE_FILE}" >> "$RESULT_FILE" 2>/dev/null

    # 显示最新一行结果
    tail -1 "$RESULT_FILE"

    sleep 10
done

echo ""
echo "=== 测试完成 ==="
echo "结果文件: $RESULT_FILE"
echo ""
echo "结果汇总:"
cat "$RESULT_FILE"
