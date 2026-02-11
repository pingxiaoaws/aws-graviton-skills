# AWS Graviton Skills

AWS Graviton 迁移和优化 Skill 集合。

## Skills

### 1. graviton-migration

将 AWS 工作负载从 x86 迁移到 Graviton (ARM64)，实现 20-40% 成本节省。

- 自动分析（AWS Porting Advisor）+ 手动分析 + Build-First 验证
- 支持 ECS Fargate、Lambda、EC2、容器工作负载
- 包含真实案例和故障排查

详细文档: [graviton-migration/SKILL.md](./graviton-migration/SKILL.md)

### 2. al2-to-al2023-migration

EKS 节点从 Amazon Linux 2 迁移到 Amazon Linux 2023。

- 三种迁移方案：Karpenter / 托管节点组 / 自管理节点组
- 兼容性检查脚本（cgroupv2、IMDS、GPU/CUDA）
- K8s 1.33 强制迁移时间线和回滚方案

详细文档: [al2-to-al2023-migration/SKILL.md](./al2-to-al2023-migration/SKILL.md)

### 3. graviton-performance-tuning

Graviton 实例性能调优指南。

- 编译器标志和 LSE 原子操作优化
- 语言专项调优（Java、Python、Go、Rust、C/C++、Node.js、.NET、PHP）
- OS/内核参数调优（THP、网络、文件描述符）
- 二进制优化分析（LSE、NEON、SVE 检测）
- 性能剖析工具（perf、flamegraph、PMU 计数器）
- SIMD/向量化移植（SSE2NEON、SIMDe、ARM NEON）
- 基准测试最佳实践

详细文档: [graviton-performance-tuning/SKILL.md](./graviton-performance-tuning/SKILL.md)

### 4. graviton-benchmark

量化对比 Graviton vs x86 实例性能，覆盖 Redis 和 Nginx 典型场景。

- Redis memtier_benchmark：多 IO 线程模式对比
- Nginx WRK：HTTPS 负载均衡 RPS 和延迟测试
- OS 级别性能调优（网络、内存、文件描述符）
- 结果对比模板和性价比计算

详细文档: [graviton-benchmark/SKILL.md](./graviton-benchmark/SKILL.md)

## 目录结构

```
aws-graviton-skills/
├── graviton-migration/           # x86 → ARM64 迁移
├── al2-to-al2023-migration/      # AL2 → AL2023 迁移
├── graviton-performance-tuning/  # 性能调优
└── graviton-benchmark/           # 性能基准测试
```
