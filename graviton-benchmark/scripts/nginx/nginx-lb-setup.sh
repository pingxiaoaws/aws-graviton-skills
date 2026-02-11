#!/bin/bash

# Graviton 性能基准测试 - Nginx 负载均衡器安装配置脚本
# 使用方法：sudo bash nginx-lb-setup.sh <web1-ip> <web2-ip>
#
# 推荐实例: r8g.2xlarge (与 web 服务器保持一致)
# OS: Amazon Linux 2023
# EBS: gp3 40GB

set -e

INSTANCE_IP_WEB1="${1}"
INSTANCE_IP_WEB2="${2}"

if [ -z "$INSTANCE_IP_WEB1" ] || [ -z "$INSTANCE_IP_WEB2" ]; then
    echo "用法: $0 <web1-ip> <web2-ip>"
    echo ""
    echo "示例:"
    echo "  $0 10.0.1.10 10.0.1.20"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Nginx 负载均衡器安装配置 ==="
echo "后端 Web1: $INSTANCE_IP_WEB1"
echo "后端 Web2: $INSTANCE_IP_WEB2"
echo ""

# 1. 安装依赖
echo "[1/4] 安装依赖..."
dnf install -y -q git irqbalance python3-pip
pip3 install -q dool
systemctl enable irqbalance --now

# 2. OS 调优
echo "[2/4] OS 调优..."
if [ -f "$SCRIPT_DIR/../common/os-tuning.sh" ]; then
    bash "$SCRIPT_DIR/../common/os-tuning.sh" --irq-affinity
else
    echo "  警告: 未找到 os-tuning.sh，跳过 OS 调优"
fi

# conntrack 模块
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

# 4. 配置 Nginx 负载均衡
echo "[4/4] 配置 Nginx 负载均衡..."

NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_CONF_DIR=$(dirname "$NGINX_CONF")
cp "$NGINX_CONF" "${NGINX_CONF}.bak"

# 生成自签名证书
openssl req -new -x509 -newkey rsa:2048 -nodes \
    -subj "/C=US/ST=Benchmark/L=Test/O=Graviton/CN=127.0.0.1" \
    -keyout "${NGINX_CONF_DIR}/rsa-key.key" \
    -out "${NGINX_CONF_DIR}/rsa-cert.crt" 2>/dev/null

cat > "$NGINX_CONF" << EOF
user root;
worker_processes auto;
worker_rlimit_nofile 1234567;
pid /run/nginx.pid;

events {
    use epoll;
    worker_connections 65535;
    multi_accept on;
    accept_mutex off;
}

http {
    access_log          off;
    include             ${NGINX_CONF_DIR}/mime.types;
    default_type        application/octet-stream;
    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         off;

    # 缓冲区
    proxy_buffers 256 16k;
    proxy_buffer_size 32k;
    client_body_buffer_size 128k;
    client_max_body_size 100m;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 4k;
    output_buffers 1 32k;
    postpone_output 1460;

    # 长连接 (RPS 测试)
    keepalive_timeout   300s;
    keepalive_requests  1000000;

    # 短连接 (TPS 测试，取消注释以下两行，注释上面两行)
    # keepalive_timeout 0;
    # keepalive_requests 1;

    types_hash_max_size 2048;
    types_hash_bucket_size 128;

    # SSL/TLS 优化
    ssl_session_cache shared:SSL:50m;
    ssl_session_timeout 1h;
    ssl_session_tickets off;
    ssl_buffer_size 4k;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers on;
    ssl_ecdh_curve X25519:secp384r1;

    # 后端服务器组
    upstream nginx-webserver-group {
        server ${INSTANCE_IP_WEB1} weight=100;
        server ${INSTANCE_IP_WEB2} weight=100;
        keepalive 64;
    }

    server {
        listen       80;
        listen       443 ssl backlog=102400;
        http2        on;

        ssl_certificate     ${NGINX_CONF_DIR}/rsa-cert.crt;
        ssl_certificate_key ${NGINX_CONF_DIR}/rsa-key.key;

        root         /usr/share/nginx/html;

        location / {
            proxy_pass http://nginx-webserver-group;
        }
    }
}
EOF

systemctl enable nginx
systemctl restart nginx

echo ""
echo "=== Nginx 负载均衡器安装完成 ==="
echo ""
echo "状态: $(systemctl is-active nginx)"
echo "HTTP:  80"
echo "HTTPS: 443 (自签名证书)"
echo ""
echo "后端服务器:"
echo "  $INSTANCE_IP_WEB1 (weight=100)"
echo "  $INSTANCE_IP_WEB2 (weight=100)"
