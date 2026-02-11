# Graviton Performance Tuning Skill

优化 AWS Graviton (ARM64) 处理器上的应用性能。

## 适用场景

```
性能不达预期?
├─ 编译器/构建优化 → check-binary-optimization.sh
├─ Java 应用调优 → check-java-tuning.sh
├─ 系统/内核参数 → tune-system.sh
├─ 网络性能问题 → 参考 SKILL.md 网络优化章节
└─ 不确定问题在哪 → check-performance-config.sh (全面检查)
```

## 脚本工具

| 脚本 | 用途 |
|------|------|
| `scripts/detect-graviton-gen.sh` | 检测 Graviton 代数，推荐最佳编译器标志 |
| `scripts/check-performance-config.sh` | 全面检查系统性能配置（THP、LSE、内核参数、网络） |
| `scripts/tune-system.sh` | 应用推荐的内核和 OS 调优参数 |
| `scripts/check-binary-optimization.sh` | 分析二进制文件是否使用了最佳编译选项 |
| `scripts/profile-workload.sh` | 性能剖析包装脚本（perf/flamegraph） |
| `scripts/check-java-tuning.sh` | 分析运行中的 JVM 实例，检查 Graviton 优化项 |

### 快速使用

```bash
# 1. 检测 Graviton 代数
./scripts/detect-graviton-gen.sh

# 2. 全面检查性能配置
./scripts/check-performance-config.sh

# 3. 应用系统调优（先 dry-run 查看）
./scripts/tune-system.sh --dry-run
./scripts/tune-system.sh --apply

# 4. 检查二进制优化
./scripts/check-binary-optimization.sh /usr/local/bin/my-app

# 5. Java 应用调优
./scripts/check-java-tuning.sh
```

## 关键优化速查

### 编译器标志

```bash
# 通用（支持 Graviton2/3/4）
-march=armv8.2-a -moutline-atomics

# Graviton4 专用
-mcpu=neoverse-v2
```

### Java 关键 JVM 参数

```bash
-XX:-TieredCompilation
-XX:ReservedCodeCacheSize=64M
-XX:InitialCodeCacheSize=64M
-XX:+UseTransparentHugePages
-XX:+OmitStackTraceInFastThrow
```

### Go 容器环境

```bash
# 容器 CPU limit 场景下手动设置
export GOMAXPROCS=<cpu-limit>
```

### Rust LSE 优化

```bash
RUSTFLAGS="-Ctarget-feature=+lse"
```

## 文件结构

```
graviton-performance-tuning/
├── README.md                              # 快速入门（本文件）
├── SKILL.md                               # 完整调优指南
├── scripts/
│   ├── detect-graviton-gen.sh             # 检测 Graviton 代数
│   ├── check-performance-config.sh        # 全面性能配置检查
│   ├── tune-system.sh                     # 系统调优应用
│   ├── check-binary-optimization.sh       # 二进制优化分析
│   ├── profile-workload.sh                # 性能剖析
│   └── check-java-tuning.sh              # Java 调优分析
└── references/
    ├── language-tuning-guide.md           # 语言专项优化详解
    ├── profiling-guide.md                 # 性能剖析方法论
    └── benchmarking-best-practices.md     # 基准测试最佳实践
```

## 详细文档

完整指南请参考 [SKILL.md](SKILL.md)，包含：
- 编译器标志和架构靶向（LSE、SVE、PGO）
- 语言专项优化（Java、Python、Go、Rust、C/C++、Node.js、.NET、PHP）
- OS/内核调优（THP、网络参数、文件描述符）
- 网络性能调优（ENA、CloudWatch 监控）
- SIMD/向量化移植（SSE2NEON、SIMDe、ARM NEON）
- 同步和原子操作（LSE、自旋锁优化）
- 性能剖析和调试（perf、flamegraph、PMU 计数器）
- 基准测试最佳实践

## 参考资源

- [AWS Graviton Getting Started](https://github.com/aws/aws-graviton-getting-started)
- [Graviton Performance Runbook](https://github.com/aws/aws-graviton-getting-started/tree/main/perfrunbook)
- [Amazon Corretto](https://aws.amazon.com/corretto/)
- [AWS APerf](https://github.com/aws/aperf)
