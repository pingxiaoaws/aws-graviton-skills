# Graviton 性能基准测试 Skill

量化对比 AWS Graviton (ARM64) 与 x86 实例的性能差异，覆盖 Redis 和 Nginx 典型场景。

## 测试场景

| 场景 | 工具 | 被测实例 | 核心指标 |
|------|------|----------|----------|
| Redis 内存数据库 | memtier_benchmark 2.0 | r8g.2xlarge vs r7i.2xlarge | OPS/sec, 延迟 |
| Nginx HTTPS 负载均衡 | WRK 4.2.0 | r8g.2xlarge vs r7i.2xlarge | RPS, p99 延迟 |

## 快速开始

### Redis 测试

```bash
# 1. 在 Redis 服务器上 (r8g.2xlarge / r7i.2xlarge)
sudo bash scripts/redis/redis-server-setup.sh

# 2. 在测试客户端上 (c6i.4xlarge) - 安装 memtier_benchmark 后
bash scripts/redis/redis-benchmark.sh <redis-ip> 6379 60
```

### Nginx 测试

```bash
# 1. 在 2 台 Web 服务器上
sudo bash scripts/nginx/nginx-webserver-setup.sh

# 2. 在负载均衡器上
sudo bash scripts/nginx/nginx-lb-setup.sh <web1-ip> <web2-ip>

# 3. 在测试客户端上 (c7a.4xlarge) - 安装 WRK 后
bash scripts/nginx/nginx-benchmark.sh <lb-ip> 1kb.bin
```

## 文件结构

```
graviton-benchmark/
├── README.md                          # 快速入门（本文件）
├── SKILL.md                           # 完整测试指南
└── scripts/
    ├── common/
    │   └── os-tuning.sh               # OS 级别性能调优
    ├── redis/
    │   ├── redis-server-setup.sh      # Redis 服务端安装
    │   └── redis-benchmark.sh         # memtier 压测脚本
    └── nginx/
        ├── nginx-webserver-setup.sh   # Nginx Web 服务器安装
        ├── nginx-lb-setup.sh          # Nginx 负载均衡器安装
        └── nginx-benchmark.sh         # WRK 压测脚本
```

## 前置依赖

**所有脚本需要 root 权限，运行在 Amazon Linux 2023 上。**

| 组件 | 安装位置 | 安装方式 |
|------|----------|----------|
| Docker | Redis 服务端 | 脚本自动安装 |
| memtier_benchmark 2.0 | 测试客户端 | 源码编译（见 SKILL.md） |
| redis-cli | 测试客户端 | 源码编译（见 SKILL.md） |
| WRK 4.2.0 | 测试客户端 | 源码编译（见 SKILL.md） |
| Nginx | Web/LB 服务端 | 脚本自动安装 |

## 详细文档

完整指南请参考 [SKILL.md](SKILL.md)，包含：
- OS 调优参数详解
- Redis IO 多线程测试方案
- Nginx HTTPS/负载均衡测试方案
- 监控和分析方法
- 结果对比模板和性价比计算
- 常见问题排查

## 参考资源

- [memtier_benchmark](https://github.com/RedisLabs/memtier_benchmark) | [WRK](https://github.com/wg/wrk)
- [Graviton 性能优化](https://github.com/aws/aws-graviton-getting-started/blob/main/optimizing.md)
