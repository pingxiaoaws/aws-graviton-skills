# Graviton 性能基准测试实战指南

**量化 Graviton 性价比优势 - Redis 与 Nginx 基准测试**

## 概述

本 Skill 提供一套完整的 Graviton 性能基准测试方案，用于量化对比 AWS Graviton (ARM64) 与 x86 实例在典型网络服务场景下的性能差异。

### 支持的测试场景

| 测试场景 | 工具 | 指标 | 对比维度 |
|----------|------|------|----------|
| Redis 内存数据库 | memtier_benchmark | OPS/sec, 延迟 | 单线程 vs 多 IO 线程 |
| Nginx Web 服务器 | WRK | RPS, 延迟百分位 | HTTP/HTTPS, 不同文件大小 |

### 推荐对比实例

| 用途 | Graviton (ARM64) | x86 对比 | 说明 |
|------|-------------------|----------|------|
| Redis 服务端 | r8g.2xlarge | r7i.2xlarge | 内存优化型，8 vCPU |
| Nginx 服务端 | r8g.2xlarge | r7i.2xlarge | 内存优化型，8 vCPU |
| 测试客户端 | c6i.4xlarge 或 c7a.4xlarge | - | 确保客户端不是瓶颈 |

> **测试原则**：被测服务器使用相同规格的 Graviton 和 x86 实例，测试客户端使用足够大的实例避免成为瓶颈。所有实例应在同一 VPC、同一子网中。

---

## 通用 OS 调优

所有被测服务器都需要进行 OS 级别调优，以消除系统配置对测试结果的影响。

### 调优项目

| 调优项 | 配置 | 原因 |
|--------|------|------|
| 透明大页面 (THP) | 禁用 | 避免内存分配延迟抖动 |
| TCP 拥塞控制 | BBR | 提升网络吞吐 |
| 网络缓冲区 | 128MB | 支撑高并发连接 |
| 文件描述符 | 1,000,000 | 支撑大量连接 |
| vm.overcommit_memory | 1 | Redis 要求 |
| vm.swappiness | 0 | 避免 swap 影响 |
| TCP keepalive | 优化 | 减少连接重建开销 |
| 中断亲和性 | 可选 | 减少跨 CPU 中断处理 |

### 使用方法

```bash
# 基本调优（适用于 Redis）
sudo bash scripts/common/os-tuning.sh

# 启用中断亲和性（适用于 Nginx）
sudo bash scripts/common/os-tuning.sh --irq-affinity

# 查看帮助
bash scripts/common/os-tuning.sh --help
```

### 关键内核参数说明

```bash
# 网络缓冲区 - 支撑高吞吐
net.core.rmem_max = 134217728          # 128MB 接收缓冲区
net.core.wmem_max = 134217728          # 128MB 发送缓冲区
net.core.somaxconn = 65535             # 监听队列上限

# TCP 优化 - 减少延迟
net.ipv4.tcp_tw_reuse = 1             # 复用 TIME_WAIT 连接
net.ipv4.tcp_fin_timeout = 10         # 快速回收 FIN_WAIT
net.ipv4.tcp_slow_start_after_idle = 0 # 禁用空闲后慢启动
net.ipv4.tcp_congestion_control = bbr  # BBR 拥塞控制

# 内存 - 稳定性
vm.overcommit_memory = 1              # Redis fork 要求
vm.swappiness = 0                     # 禁用 swap
vm.min_free_kbytes = 1048576          # 1GB 保留内存
```

---

## 测试一：Redis 性能基准

### 测试架构

```
┌──────────────────────┐     ┌──────────────────────────────┐
│  测试客户端           │     │  Redis 服务端                 │
│  c6i.4xlarge         │────→│  r8g.2xlarge / r7i.2xlarge   │
│  memtier_benchmark   │     │  Redis 7.0.15 (Docker)       │
│                      │     │  4 种 IO 线程配置              │
└──────────────────────┘     └──────────────────────────────┘
       同一子网
```

### Redis IO 线程模式

Redis 7.0 引入了 IO 多线程特性，可以将网络 IO 操作分配到多个线程处理，而命令执行仍为单线程。

安装脚本自动创建 4 个 Redis 实例：

| 端口 | IO 线程数 | 说明 |
|------|----------|------|
| 6379 | 1（禁用） | 单线程基线 |
| 8000+N | CPU 的 40% | 保守配置 |
| 8000+N | CPU 的 65% | 均衡配置 |
| 8000+N | CPU 的 90% | 激进配置 |

> 例如 8 vCPU 实例：端口 6379(单线程)、8003(3线程)、8005(5线程)、8007(7线程)

### 步骤 1：部署 Redis 服务端

在被测服务器上（分别在 Graviton 和 x86 实例上执行）：

```bash
sudo su - root

# 下载脚本
# git clone ... 或 scp 脚本到服务器

# 安装并启动 Redis
bash scripts/redis/redis-server-setup.sh

# 验证
docker ps | grep redis
redis-cli -p 6379 ping    # 应返回 PONG
```

### 步骤 2：部署测试客户端

在测试客户端机器上（c6i.4xlarge）：

```bash
sudo su - root

# 安装 memtier_benchmark
yum install -y autoconf automake make gcc gcc-c++ \
    pcre pcre-devel zlib-devel libmemcached-devel \
    libevent-devel openssl-devel

cd /root
git clone https://github.com/RedisLabs/memtier_benchmark.git
cd memtier_benchmark
git checkout tags/2.0.0
autoreconf -ivf
./configure
make -j && make install
memtier_benchmark --version

# 安装 redis-cli
cd /root
wget https://download.redis.io/releases/redis-7.2.4.tar.gz
tar xzf redis-7.2.4.tar.gz && cd redis-7.2.4
make && make install
redis-cli -v
```

### 步骤 3：运行测试

```bash
# 测试单线程 Redis（基线）
bash scripts/redis/redis-benchmark.sh <redis-ip> 6379 60

# 测试不同 IO 线程配置
bash scripts/redis/redis-benchmark.sh <redis-ip> 8003 60   # 40% CPU
bash scripts/redis/redis-benchmark.sh <redis-ip> 8005 60   # 65% CPU
bash scripts/redis/redis-benchmark.sh <redis-ip> 8007 60   # 90% CPU
```

### 测试参数说明

| 参数 | 值 | 说明 |
|------|------|------|
| --threads | 1,2,4,8,16,32,64 | 逐步增加客户端线程数 |
| --clients | 4 | 每线程 4 个连接 |
| --test-time | 60s | 每轮持续时间 |
| --data-size-range | 1-4096 | 随机数据大小 |
| --ratio | 1:4 | 读写比（20% 读，80% 写） |
| --run-count | 3 | 每组重复 3 次取平均 |

### 结果分析

```bash
# 查看汇总结果
grep "Totals" /root/benchmark-results/redis/*.txt

# 关键指标
# - Ops/sec: 每秒操作数（越高越好）
# - Avg Latency: 平均延迟（越低越好）
# - p99 Latency: 99 百分位延迟（越低越好）
```

**对比要点**：
- 对比 Graviton (r8g) vs x86 (r7i) 在相同 IO 线程配置下的 OPS/sec
- 观察随线程数增加的扩展性差异
- 关注 p99 延迟的稳定性

---

## 测试二：Nginx 性能基准

### 测试架构

```
┌──────────────┐     ┌────────────────┐     ┌──────────────┐
│  测试客户端   │     │  Nginx LB      │     │  Nginx Web1  │
│  c7a.4xlarge │────→│  r8g.2xlarge   │────→│  r8g.2xlarge │
│  WRK 4.2.0   │     │  SSL/TLS       │     │  静态资源     │
│              │     │  HTTP/2        │  ┌─→│              │
│              │     │  负载均衡       │──┘  └──────────────┘
│              │     │               │     ┌──────────────┐
│              │     │               │────→│  Nginx Web2  │
│              │     │               │     │  r8g.2xlarge │
└──────────────┘     └────────────────┘     └──────────────┘
                   同一子网（3+1 个实例）
```

### 步骤 1：部署 Nginx Web 服务器（2 台）

分别在两台 Web 服务器上执行：

```bash
sudo su - root
bash scripts/nginx/nginx-webserver-setup.sh

# 验证
curl -s http://localhost/1kb.bin | wc -c    # 应返回 1024
curl -s http://localhost/get/               # 应返回 HTML
```

### 步骤 2：部署 Nginx 负载均衡器（1 台）

```bash
sudo su - root

# 参数为两台 Web 服务器的 IP 地址
bash scripts/nginx/nginx-lb-setup.sh <web1-ip> <web2-ip>

# 验证
curl -sk https://localhost/1kb.bin | wc -c   # 应返回 1024
```

### 步骤 3：部署测试客户端

在测试客户端上（c7a.4xlarge）：

```bash
sudo su - root

# 安装编译工具和 WRK
yum -y group install development
cd /root
wget https://github.com/wg/wrk/archive/refs/tags/4.2.0.tar.gz
tar zxf 4.2.0.tar.gz && rm -f 4.2.0.tar.gz
cd wrk-4.2.0
make -j
```

### 步骤 4：运行测试

```bash
# 测试 1KB 文件
bash scripts/nginx/nginx-benchmark.sh <lb-ip> 1kb.bin

# 测试不同大小
bash scripts/nginx/nginx-benchmark.sh <lb-ip> 10kb.bin
bash scripts/nginx/nginx-benchmark.sh <lb-ip> 100kb.bin
```

### 测试参数说明

| 参数 | 值 | 说明 |
|------|------|------|
| --threads | 8 | 固定 8 线程 |
| --connections | 10-300 | 逐步增加并发连接 |
| --duration | 3m | 每轮 3 分钟 |
| 协议 | HTTPS | 经过 SSL/TLS + 负载均衡 |

### 结果分析

```bash
# 查看结果
cat /root/benchmark-results/nginx/*.txt

# 输出格式:
# Connections, RPS, p50(us), p90(us), p99(us), p99.99(us)
```

**关键指标**：
- **RPS (Requests Per Second)**：每秒请求数，核心吞吐指标
- **p50 延迟**：中位数延迟
- **p99 延迟**：99 百分位延迟，衡量尾部延迟
- **p99.99 延迟**：极端情况延迟

**对比要点**：
- Graviton 在 SSL/TLS 握手场景的性能（ARM 加密指令加速）
- 随连接数增加的 RPS 曲线
- 不同文件大小下的吞吐差异

---

## Nginx 测试模式切换

负载均衡器脚本支持两种测试模式，通过修改 nginx.conf 切换：

### RPS 测试（默认 - 长连接）

测试在持久连接下的请求处理能力：

```nginx
keepalive_timeout   300s;
keepalive_requests  1000000;
```

### TPS 测试（短连接）

测试 TLS 握手性能，每个请求新建连接：

```nginx
keepalive_timeout 0;
keepalive_requests 1;
```

修改后重启 Nginx：
```bash
sudo systemctl restart nginx
```

---

## 监控和分析

### 服务端监控

在被测服务器上运行 dool（dstat 替代）收集系统指标：

```bash
# 后台运行 dool 收集 CPU、内存、网络、磁盘指标
dool --cpu --sys --mem --net --net-packets --disk --io --proc-count --time --bits 60 100 \
    > /root/dool-$(date +%Y%m%d-%H%M%S).txt 2>&1 &
```

### 关注指标

| 指标 | 说明 | 预期 |
|------|------|------|
| CPU user% | 应用 CPU 使用率 | 接近 100% 说明已打满 |
| CPU softirq% | 软中断（网络处理） | Graviton 通常更低 |
| NET recv/send | 网络吞吐 | 不应接近 ENA 带宽上限 |
| Memory used | 内存使用 | Redis 应稳定不持续增长 |

---

## 结果对比模板

### Redis 对比

| 配置 | r8g.2xlarge (Graviton) | r7i.2xlarge (x86) | 差异 |
|------|----------------------|-------------------|------|
| 单线程, t=8 | ___ OPS/sec | ___ OPS/sec | __% |
| IO 40%, t=8 | ___ OPS/sec | ___ OPS/sec | __% |
| IO 65%, t=8 | ___ OPS/sec | ___ OPS/sec | __% |
| IO 90%, t=8 | ___ OPS/sec | ___ OPS/sec | __% |

### Nginx 对比

| 连接数 | r8g (RPS) | r7i (RPS) | 差异 | r8g p99 | r7i p99 |
|--------|-----------|-----------|------|---------|---------|
| 10 | ___ | ___ | __% | ___us | ___us |
| 100 | ___ | ___ | __% | ___us | ___us |
| 200 | ___ | ___ | __% | ___us | ___us |
| 300 | ___ | ___ | __% | ___us | ___us |

### 性价比计算

```
Graviton 性能 / x86 性能 = 性能比
Graviton 价格 / x86 价格 = 价格比
性价比提升 = (性能比 / 价格比 - 1) × 100%

# 示例 (us-east-1):
# r8g.2xlarge: $0.4032/hr
# r7i.2xlarge: $0.5292/hr
# 如果 Graviton 性能 = x86 性能:
# 性价比提升 = (1.0 / 0.762 - 1) × 100% = 31.2%
```

---

## 常见问题

### 测试结果波动大

- 确保测试持续时间足够（>= 60 秒）
- 使用 `--run-count=3` 多次运行取平均
- 检查是否有后台任务干扰
- 确认未触发 CPU throttling（T 系列实例）

### 客户端成为瓶颈

- 测试客户端应使用足够大的实例（推荐 4xlarge+）
- 监控客户端 CPU 使用率不应超过 70%
- 可使用多台客户端分担负载

### 网络带宽瓶颈

- 确认实例网络带宽上限（r8g.2xlarge: 最高 12.5 Gbps）
- 使用 `iperf3` 预先测试网络带宽
- 避免跨可用区测试

### Redis 连接被拒绝

```bash
# 检查 Redis 容器状态
docker ps -a | grep redis

# 检查配置
docker logs redis-6379

# 确认端口开放
redis-cli -h <ip> -p <port> ping
```

### WRK 连接超时

```bash
# 检查 Nginx 状态
systemctl status nginx
nginx -t   # 检查配置语法

# 检查安全组是否开放 80/443
# 确认负载均衡器能访问后端 Web 服务器
curl -sk https://<lb-ip>/1kb.bin | wc -c
```

---

## 参考资源

### 工具文档
- [memtier_benchmark](https://github.com/RedisLabs/memtier_benchmark)
- [WRK HTTP Benchmarking Tool](https://github.com/wg/wrk)
- [Redis IO Threads](https://redis.io/docs/management/optimization/io-threads/)

### AWS 文档
- [Graviton 性能优化指南](https://github.com/aws/aws-graviton-getting-started/blob/main/optimizing.md)
- [ENA 网络性能](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/enhanced-networking-ena.html)
- [EC2 实例类型对比](https://aws.amazon.com/ec2/instance-types/)

---

**版本**：v1.0
**最后更新**：2026-02-11
