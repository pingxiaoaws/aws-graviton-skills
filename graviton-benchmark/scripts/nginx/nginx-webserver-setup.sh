#!/bin/bash

# Graviton 性能基准测试 - Nginx Web 服务器安装配置脚本
# 使用方法：sudo bash nginx-webserver-setup.sh
#
# 推荐实例: r8g.2xlarge (Graviton) 或对比实例
# OS: Amazon Linux 2023
# EBS: gp3 40GB

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Nginx Web 服务器安装配置 ==="
echo "CPU 架构: $(uname -m)"
echo "CPU 核数: $(nproc)"
echo ""

# OS 检测
OS_NAME=$(grep ^NAME /etc/os-release | awk -F '"' '{print $2}')
OS_VERSION=$(grep ^VERSION_ID /etc/os-release | awk -F '"' '{print $2}')

if [[ "$OS_NAME" != "Amazon Linux" ]] || [[ "$OS_VERSION" != "2023" ]]; then
    echo "警告: 推荐在 Amazon Linux 2023 上运行"
fi

# 1. 安装依赖
echo "[1/4] 安装依赖..."
dnf install -y -q git irqbalance python3-pip
pip3 install -q dool
systemctl enable irqbalance --now

# 2. OS 调优（启用 IRQ 亲和性，适合 Nginx）
echo "[2/4] OS 调优..."
if [ -f "$SCRIPT_DIR/../common/os-tuning.sh" ]; then
    bash "$SCRIPT_DIR/../common/os-tuning.sh" --irq-affinity
else
    echo "  警告: 未找到 os-tuning.sh，跳过 OS 调优"
fi

# 加载 conntrack 模块并设置参数
modprobe nf_conntrack 2>/dev/null || true
if [ -f /proc/sys/net/netfilter/nf_conntrack_max ]; then
    cat > /etc/sysctl.d/99-conntrack.conf << 'EOF'
net.netfilter.nf_conntrack_max = 2097152
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
EOF
    sysctl -p /etc/sysctl.d/99-conntrack.conf > /dev/null 2>&1
fi

# 3. 安装 Nginx
echo "[3/4] 安装 Nginx..."
dnf install -y -q nginx

# 4. 配置 Nginx
echo "[4/4] 配置 Nginx..."

NGINX_CONF="/etc/nginx/nginx.conf"
cp "$NGINX_CONF" "${NGINX_CONF}.bak"

cat > "$NGINX_CONF" << 'EOF'
user root;
worker_processes auto;
worker_rlimit_nofile 1234567;
pid /run/nginx.pid;

events {
    use epoll;
    multi_accept on;
    worker_connections 65535;
}

http {
    access_log   off;
    include      /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile     on;
    tcp_nopush   on;
    tcp_nodelay  off;

    # 缓冲区
    proxy_buffers 256 16k;
    proxy_buffer_size 32k;

    # 静态文件缓存
    open_file_cache max=100000 inactive=60s;
    open_file_cache_valid 90s;
    open_file_cache_min_uses 2;

    # 压缩
    gzip on;
    gzip_min_length 1k;
    gzip_comp_level 3;
    gzip_disable "msie6";
    gzip_vary on;
    gzip_proxied any;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types application/atom+xml application/geo+json application/javascript
               application/x-javascript application/json application/ld+json
               application/manifest+json application/rdf+xml application/rss+xml
               application/xhtml+xml application/xml font/eot font/otf font/ttf
               image/svg+xml text/css text/javascript text/plain text/xml;

    keepalive_timeout  300s;
    keepalive_requests 1000000;

    server {
        listen       80;
        root         /usr/share/nginx/html;

        # GET 请求
        location /get {
            root /usr/share/nginx/html;
            index index.html;
            access_log off;
        }

        # POST 请求（直接返回 200）
        location /post {
            client_body_buffer_size 128k;
            client_max_body_size 128k;
            access_log off;
            return 200;
        }
    }
}
EOF

systemctl enable nginx
systemctl restart nginx

# 生成测试静态资源
echo "生成测试静态资源..."
cd /usr/share/nginx/html
mkdir -p get
cp index.html get/

touch 0kb.bin
dd if=/dev/zero of=1kb.bin   bs=1KB  count=1  2>/dev/null
dd if=/dev/zero of=10kb.bin  bs=10KB count=1  2>/dev/null
dd if=/dev/zero of=100kb.bin bs=100KB count=1 2>/dev/null
dd if=/dev/zero of=1mb.bin   bs=1MB  count=1  2>/dev/null

# 下载 Phoronix 测试文件
if [ ! -f "500kb.bin" ]; then
    wget -q http://www.phoronix-test-suite.com/benchmark-files/http-test-files-1.tar.xz 2>/dev/null || true
    if [ -f "http-test-files-1.tar.xz" ]; then
        tar xf http-test-files-1.tar.xz
        mv -f http-test-files/* . 2>/dev/null || true
        rm -rf http-test-files http-test-files-1.tar.xz
    fi
fi

echo ""
echo "=== Nginx Web 服务器安装完成 ==="
echo ""
echo "状态: $(systemctl is-active nginx)"
echo "端口: 80"
echo ""
echo "测试资源:"
ls -lh /usr/share/nginx/html/*.bin 2>/dev/null
