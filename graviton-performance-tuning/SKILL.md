---
name: graviton-performance-tuning
description: Optimize application performance on AWS Graviton processors (Graviton2/3/4). Use when tuning compiler flags, JVM settings, kernel parameters, network configuration, or profiling workloads on ARM64 instances. Covers language-specific optimizations (Java, Python, Go, Rust, C/C++, Node.js, .NET), OS/kernel tuning, LSE atomics, SIMD vectorization, and benchmarking best practices.
---

# Graviton Performance Tuning Skill

Optimize application performance on AWS Graviton (ARM64) processors. This skill covers compiler flags, language-specific tuning, OS/kernel optimization, network performance, profiling, and benchmarking best practices.

**Source:** Based on [aws-graviton-getting-started](https://github.com/aws/aws-graviton-getting-started) official guidance.

---

## Quick Start

### 1. Detect Graviton Generation and Current Configuration

```bash
./scripts/detect-graviton-gen.sh
```

### 2. Check System Configuration

```bash
./scripts/check-performance-config.sh
```

### 3. Apply Recommended Kernel/OS Tuning

```bash
./scripts/tune-system.sh --apply
```

### 4. Analyze Binary for Optimal Compilation

```bash
./scripts/check-binary-optimization.sh /path/to/binary
```

### 5. Profile Your Workload

```bash
./scripts/profile-workload.sh --pid <PID> --duration 30
```

---

## Graviton Architecture Overview

### Generation Comparison

| Feature | Graviton2 | Graviton3/3E | Graviton4 |
|---------|-----------|--------------|-----------|
| Architecture | Neoverse N1 | Neoverse V1 | Neoverse V2 |
| Max vCPUs | 64 | 64 (3E: 64) | 192 |
| SVE | No | Yes (256-bit) | Yes (128-bit) |
| Cache Line | 64 bytes | 64 bytes | 64 bytes |
| LSE Atomics | Yes | Yes | Yes |
| Instance Family | c6g, m6g, r6g | c7g, m7g, r7g | c8g, m8g, r8g |
| Optimal `-mcpu` | `neoverse-n1` | `neoverse-v1` | `neoverse-v2` |

### Key Architectural Difference vs x86

- **No SMT/Hyperthreading**: Each Graviton vCPU is a **full physical core**
- Performance scales **nearly linearly** — Graviton3 achieves **96% efficiency** at full utilization
- x86 degrades after 50% CPU (hyperthreading contention) — only **63% efficiency** at full capacity
- **Implication**: Load balancer thresholds can be set higher on Graviton, potentially reducing fleet size

---

## Compiler Flags and Architecture Targeting

### Universal Flag (Recommended for Multi-Generation Support)

```bash
# Targets Graviton2/3/4 simultaneously; enables LSE atomics
-march=armv8.2-a

# Runtime detection of LSE vs legacy atomics (GCC 10+)
# Backward compatible with Graviton1/A1
-moutline-atomics
```

### Generation-Specific Flags

```bash
# Graviton2 only
-mcpu=neoverse-n1

# Graviton3/3E only
-mcpu=neoverse-v1

# Graviton4 only
-mcpu=neoverse-v2

# Balanced for Graviton3 + Graviton4
-mcpu=neoverse-512tvb
```

### Minimum Compiler Versions for Best Performance

| Graviton Gen | GCC | LLVM/Clang |
|-------------|-----|------------|
| Graviton2 | 9+ | 10+ |
| Graviton3/3E | 11+ | 14+ |
| Graviton4 | 13+ | 16+ |

**Impact**: Upgrading from GCC 7 to GCC 10 alone yields **~15% better performance** on Graviton2.

### Additional Optimization Flags

```bash
# Link-Time Optimization — reduces instruction footprint
-flto

# Size optimization when instruction cache pressure is high
-Os

# Profile-Guided Optimization (two-pass)
# Pass 1: Build with profiling
gcc -fprofile-generate -o app app.c
./app  # Run representative workload
# Pass 2: Build with collected profile
gcc -fprofile-use -o app app.c
```

### Large System Extensions (LSE) — Critical

LSE provides **order-of-magnitude improvements** for highly contended locks on large-core systems (up to 192 cores on Graviton4).

```bash
# Verify LSE usage in binary
objdump -d /path/to/binary | grep -E "cas[[:space:]]|casp|ldadd|stadd|swp[[:space:]]"

# If no LSE instructions found, recompile with:
-march=armv8.2-a
# or for portable binaries:
-moutline-atomics   # GCC 10+, LLVM 12+
```

---

## Language-Specific Optimizations

### Java

**Recommended JDK**: Amazon Corretto 17+ (JDK 11 minimum, JDK 8 runs but suboptimal)

#### Critical JVM Flags

```bash
# Disable tiered compilation for server workloads — up to 1.5x improvement
-XX:-TieredCompilation -XX:ReservedCodeCacheSize=64M -XX:InitialCodeCacheSize=64M

# For Corretto 17+
-XX:CICompilerCount=2 -XX:CompilationMode=high-only

# AES/GCM crypto acceleration — 3.5-5x faster on Graviton2
# Default in Corretto; for older OpenJDK:
-XX:+UnlockDiagnosticVMOptions -XX:+UseAESCTRIntrinsics

# Huge pages (recommended)
-XX:+UseTransparentHugePages
# or explicit huge pages:
-XX:+UseLargePages

# Profiling support (for flamegraphs)
-XX:+PreserveFramePointer -agentpath:/usr/lib64/libperf-jvmti.so
```

#### Thread Stack Size Issue

aarch64 defaults to **2MB** thread stack (vs 1MB on x86). For many-threaded apps with THP `always`:

```bash
# Option 1: Reduce thread stack size
-XX:ThreadStackSize=1024

# Option 2: Switch THP to madvise
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
```

#### Exception Anti-Pattern

Stack trace generation costs up to **2x more on Graviton** vs x86. Avoid exceptions for control flow.

```bash
# Mitigate with:
-XX:+OmitStackTraceInFastThrow
```

#### Benchmarking Tip

Each Graviton vCPU is a full physical core (no hyperthreading). Push workloads closer to **saturation** for realistic comparison — Graviton performs proportionally better under high load.

### Python

**⚠️ Strongly Recommended: Python 3.10+**

Python 3.9 and earlier versions have significantly degraded performance on Graviton. Key reasons:
- Missing ARM64-specific optimizations in the interpreter
- NumPy/SciPy binary wheels may not be fully optimized
- Performance gap can be 20-40% compared to Python 3.10+

**Minimum Usable Version**: Python 3.8 (not recommended for production)

```bash
# NumPy >= 1.21.1 with OpenBLAS >= 0.3.17 (includes Graviton-specific gemv/gemm)
pip install "numpy>=1.21.1"

# SciPy >= 1.7.2
pip install "scipy>=1.7.2"

# BLIS as alternative to OpenBLAS for some workloads
pip install blis

# Multi-threading is NOT default — explicitly set:
export OMP_NUM_THREADS=$(nproc)
# or for BLIS:
export BLIS_NUM_THREADS=$(nproc)

# Control BLAS priority:
export NPY_BLAS_ORDER=openblas,blis
export NPY_LAPACK_ORDER=openblas
```

### Go (Golang)

**Recommended**: Go 1.18+

```bash
# Go 1.18+: Register-based calling convention — 10%+ improvement on arm64
# Go 1.17: crypto/ed25519 2x faster, P-521 3x faster on arm64
# Go 1.16: ARMv8.1-A atomics dramatically improve mutex performance

# Container tip: When using CPU limits, manually set GOMAXPROCS
export GOMAXPROCS=<cpu-limit>
# e.g., for --cpus=2:
export GOMAXPROCS=2
```

### Rust

```bash
# Enable LSE — up to 3x improvement for locks/mutexes on larger systems
RUSTFLAGS="-Ctarget-feature=+lse"

# Target specific Graviton generation
RUSTFLAGS="-Ctarget-cpu=neoverse-n1"  # Graviton2
RUSTFLAGS="-Ctarget-cpu=neoverse-v1"  # Graviton3
RUSTFLAGS="-Ctarget-cpu=neoverse-v2"  # Graviton4

# Rust 1.57+ automatically enables outline-atomics on arm64-linux
```

### C/C++

```bash
# Signed char difference: ARM defaults to UNSIGNED char (x86 = signed)
# Use explicit types or compile with:
-fsigned-char

# SVE (Scalable Vector Extension) — Graviton3/4 only
# Requires: GCC 11+, LLVM 14+, kernel 4.15+
-march=armv8.4-a+sve

# x86 intrinsics porting:
# Option 1: SSE2NEON — drop-in header for SSE to NEON conversion
#include "sse2neon.h"  // instead of <emmintrin.h>

# Option 2: SIMDe — broader x86 SIMD emulation
#include "simde/x86/sse2.h"

# Include native ARM intrinsics:
#include <arm_neon.h>   // NEON SIMD
#include <arm_acle.h>   // Architecture extensions (CRC, atomics)
```

### Node.js

```bash
# Use multi-process architecture (cluster module or Nginx)
# Node is single-threaded — maximize per-process performance

# Prefer statically linked binaries from nodejs.org
# Reduced function-call overhead vs distro packages

# For regex-heavy workloads — avoids V8 aarch64 JIT veneer chain issue
node --regexp-interpret-all app.js
```

### .NET

```bash
# .NET 8 (LTS) or .NET 9 recommended for best arm64 vectorization
dotnet publish -c Release -r linux-arm64
```

### PHP

```bash
# Enable OPcache (stores precompiled bytecode in shared memory)
# Included by default on AL2023; requires manual install on AL2:
sudo yum install -y php-opcache
```

---

## OS and Kernel Tuning

### Recommended Operating Systems

| OS | LSE Support | Notes |
|----|-------------|-------|
| Amazon Linux 2023 | Yes | Full support, recommended |
| Ubuntu 24.04 / 22.04 LTS | Yes | Full support |
| RHEL 8.2+ | Yes | Uses 64KB page size |
| Debian 12/11 | Yes | Full support |

### Transparent Huge Pages (THP)

```bash
# Enable THP
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled

# Or use madvise for finer control (recommended for Java with many threads)
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled

# Linux 6.9+: Configure folio sizes
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/hugepages-2048kB/enabled

# Reserve huge pages at boot (add to GRUB config)
# hugepagesz=2M hugepages=512

# Runtime allocation
sudo sysctl -w vm.nr_hugepages=512
```

### Network Parameters

```bash
# Prevent port exhaustion under load
sudo sysctl -w net.ipv4.ip_local_port_range="1024 65535"

# Reuse TIME_WAIT sockets
sudo sysctl -w net.ipv4.tcp_tw_reuse=1

# Process limits
ulimit -n 65535

# Permanent (in /etc/security/limits.conf):
# *    soft    nofile    65535
# *    hard    nofile    65535

# For systemd services:
# LimitNOFILE=65535
# LimitSTACK=unlimited
# LimitNPROC=65535
```

### Kernel Parameters for Benchmarking (Persistent)

```bash
# /etc/sysctl.d/99-graviton-tuning.conf
cat <<'EOF' | sudo tee /etc/sysctl.d/99-graviton-tuning.conf
# Network tuning
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000

# Memory tuning
vm.swappiness = 10
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10

# File descriptor limits
fs.file-max = 2097152
fs.nr_open = 2097152
EOF

sudo sysctl --system
```

---

## Network Performance Tuning

### ENA (Elastic Network Adapter) Optimization

```bash
# Latency-sensitive workloads:
# Disable adaptive RX and manually pin IRQs to dedicated cores
sudo ethtool -C eth0 adaptive-rx off
sudo systemctl stop irqbalance

# Verify RPS is disabled (should return 0):
cat /sys/class/net/eth0/queues/rx-0/rps_cpus

# Throughput-sensitive workloads:
# Enable adaptive RX for handling increased interrupt rates
sudo ethtool -C eth0 adaptive-rx on
```

### CloudWatch Network Monitoring

Watch for ENA throttling metrics:
- `bw_in_allowance_exceeded` — Ingress bandwidth throttled
- `bw_out_allowance_exceeded` — Egress bandwidth throttled
- `conntrack_allowance_exceeded` — Connection tracking throttled
- `pps_allowance_exceeded` — Packets-per-second throttled
- `linklocal_allowance_exceeded` — Link-local throttled

**If throttled**: Provision larger instance types for more bandwidth.

### Benchmarking Network Configuration

```bash
# Use EC2 Placement Groups with cluster strategy
aws ec2 create-placement-group \
  --group-name perf-test-group \
  --strategy cluster

# All instances in the same subnet
# Verify: Ping latencies within tens of microseconds
# Traceroute hops ideally 3 or fewer
```

---

## SIMD and Vectorization

### Auto-Vectorization

```bash
# GCC 10 shows significant improvement over GCC 9 for auto-vectorization
# Restructure inner loops to align with 128-bit NEON width:
# 4 iterations for 32-bit floats → 3-4x gains
```

### Porting x86 SIMD to ARM

```c
// SSE2NEON: Drop-in header for SSE → NEON conversion
// Replace: #include <emmintrin.h>
// With:    #include "sse2neon.h"

// SIMDe: Broader x86 SIMD emulation for rapid prototyping
// #include "simde/x86/sse2.h"

// Native ARM NEON intrinsics:
#include <arm_neon.h>

// Example: 4-wide float multiply
float32x4_t a = vld1q_f32(src_a);
float32x4_t b = vld1q_f32(src_b);
float32x4_t result = vmulq_f32(a, b);
vst1q_f32(dst, result);
```

### Runtime Feature Detection

```c
#include <sys/auxv.h>
#include <asm/hwcap.h>

unsigned long hwcaps = getauxval(AT_HWCAP);

if (hwcaps & HWCAP_CRC32)    // CRC instructions
if (hwcaps & HWCAP_ATOMICS)  // LSE atomics
if (hwcaps & HWCAP_FPHP)     // FP16 support
if (hwcaps & HWCAP_ASIMDDP)  // Dot-product operations
if (hwcaps & HWCAP_SVE)      // SVE (Graviton3/4)
```

---

## Synchronization and Atomics

### LSE Atomics — Critical for Performance

LSE atomics (`-march=armv8.2-a`) are essential for many-core Graviton instances — **order-of-magnitude improvement** on contended locks.

```bash
# For all Graviton generations (portable):
CFLAGS="-moutline-atomics"  # GCC 10+, LLVM 12+

# For Graviton2+ only (maximum performance):
CFLAGS="-march=armv8.2-a"
```

### Spin-Wait Optimization

Replace x86 `PAUSE`/`rep; nop` spin-wait with Graviton's `ISB` instruction:

```c
// x86:
// __asm__ volatile("pause");

// ARM64 (Graviton2+):
__asm__ volatile("isb");

// Or use compiler intrinsic:
__builtin_arm_isb(15);
```

### Lock Tuning

- Extend fast-path lock acquisition attempts before OS sleep to reduce context switches
- Use read-write locks where applicable — Graviton's many physical cores amplify contention
- Consider lock-free data structures for hot paths

---

## Performance Profiling and Debugging

### Recommended Tools

| Tool | Use Case |
|------|----------|
| **AWS APerf** | Automated collection and analysis; first-line tool |
| **Linux perf** | On-CPU/off-CPU flamegraphs, PMU counters |
| **SPE** | Per-instruction tracing (Graviton2/3 metal only) |
| **CMN PMU** | System-level fabric monitoring (metal only) |
| **eBPF/BCC** | Function-level kernel investigation |
| **Java Flight Recorder** | JVM-specific profiling |

### On-CPU Profiling

```bash
# Compile with debug symbols and frame pointers
CFLAGS="-g -fno-omit-frame-pointer"

# Record CPU samples (30 seconds)
sudo perf record -F 99 -ag -- sleep 30

# Generate flamegraph
sudo perf script | stackcollapse-perf.pl | flamegraph.pl > flamegraph.svg

# With AWS APerf:
aperf record -d 30
aperf report
```

### Off-CPU Profiling

Look for:
- **Lock contention**: `lock`, `mutex`, `semaphore`, `futex`
- **I/O sleeps**: `read`, `write`, `epoll`
- **Scheduler issues**: Ignore `work_pending` stacks (involuntary switches)

### PMU Counter Analysis (Top-Down Method)

```bash
# 1. Measure IPC
perf stat -e cycles,instructions -- <command>
# Compare between architectures

# 2. Frontend stalls
perf stat -e L1-icache-load-misses,iTLB-load-misses,branch-misses -- <command>
# Warning thresholds: branch-mpki > 10, inst-l1-mpki > 20

# 3. Backend stalls
perf stat -e L1-dcache-load-misses,L2-cache-misses,LLC-load-misses,dTLB-load-misses -- <command>
# Warning thresholds: data-l1-mpki > 20, l2-mpki > 10, l3-mpki > 10
```

**Note**: Full PMU access requires minimum instance sizes (e.g., c7g.16xlarge, c6g.16xlarge).

### Pseudo-NMI for Kernel Profiling

When kernel overhead appears in `arch_local_irq_restore`:

```bash
# Requires CONFIG_ARM64_PSEUDO_NMI kernel support
# Add to kernel command line:
irqchip.gicv3_pseudo_nmi=1

# Use hardware PMU events instead of cpu-clock:
sudo perf record -e r11 -ag -- sleep 30    # r11 = CPU cycles
sudo perf record -e r8 -ag -- sleep 30     # r8 = instructions retired
```

---

## DPDK/SPDK (Datapath Performance)

```bash
# Set cache line and max lcores
export RTE_MAX_LCORE=192    # Match Graviton4 max (64 for Graviton2/3)
export RTE_CACHE_LINE_SIZE=64

# Use ALL vCPUs as lcores (unlike x86 where half are unused due to SMT)
# Every Graviton vCPU is a full physical core

# Native compilation auto-leverages CRC and Crypto instructions on Graviton2+
```

---

## Metal Instance Optimization

```bash
# Disable System MMU (SMMU) on Graviton2+ metal for improved I/O
# SPE profiling available only on metal (Graviton2/3)
# CMN PMU counters for system-level fabric monitoring on metal
```

---

## Benchmarking Best Practices

### Methodology

1. **Use production workloads** rather than synthetic benchmarks
2. **Match OS, kernel, and package versions** across comparison instances
3. **Use dedicated tenancy** initially to establish performance variance baseline
4. **Load generator sizing**: Use 12xlarge or larger; ensure generator uses <50% CPU
5. **Thread pinning**: Do NOT assume SMT — every vCPU is a full core
6. **Test at saturation**: Graviton outperforms at high utilization due to no hyperthreading

### Binary Dependency Verification

```bash
# Check for aarch64-specific shared objects in Java JARs
find /path/to/app -name "*.jar" -exec unzip -l {} \; | grep -E "\.so$" | grep -v aarch64

# Scan for assembly code needing ARM64 versions
find /path/to/app -name "*.S" -o -name "*.s" | head -20
grep -r "__asm__" /path/to/app --include="*.c" --include="*.cpp"
```

### Quick Performance Comparison Script

```bash
# Compare IPC between x86 and Graviton runs
# On x86 instance:
perf stat -e cycles,instructions,cache-misses -- ./your_workload 2>&1 | tee x86_perf.txt

# On Graviton instance:
perf stat -e cycles,instructions,cache-misses -- ./your_workload 2>&1 | tee arm64_perf.txt

# Compare key metrics:
# - IPC (instructions per cycle)
# - Cache miss rate
# - Wall-clock time
```

---

## Common Performance Issues and Fixes

### Issue 1: Poor Lock Performance on Many-Core Instances

**Symptom**: Application doesn't scale beyond 16-32 cores
**Cause**: Missing LSE atomics
**Fix**:
```bash
# Verify LSE in binary
objdump -d /path/to/binary | grep -c "cas\b\|casp\|ldadd\|stadd\|swp\b"
# If 0, recompile with -march=armv8.2-a or -moutline-atomics
```

### Issue 2: Java Application Slower Than Expected

**Symptom**: Higher latency or lower throughput vs x86
**Cause**: Default JVM settings not optimized for Graviton
**Fix**:
```bash
java -XX:-TieredCompilation \
     -XX:ReservedCodeCacheSize=64M \
     -XX:InitialCodeCacheSize=64M \
     -XX:+UseTransparentHugePages \
     -XX:+OmitStackTraceInFastThrow \
     -jar app.jar
```

### Issue 3: Go Application with CPU Limits Not Performing Well

**Symptom**: Go app in container with CPU limits underperforms
**Cause**: GOMAXPROCS defaults to host CPU count, not container limit
**Fix**:
```bash
# Set GOMAXPROCS to match container CPU limit
export GOMAXPROCS=2  # Match --cpus=2

# Or use automaxprocs library:
# import _ "go.uber.org/automaxprocs"
```

### Issue 4: Python NumPy/SciPy Slower Than Expected

**Symptom**: Numerical computation slower on Graviton
**Cause**: OpenBLAS not optimized or single-threaded
**Fix**:
```bash
pip install "numpy>=1.21.1"
pip install "scipy>=1.7.2"
export OMP_NUM_THREADS=$(nproc)
```

### Issue 5: Network Throughput Below Instance Limits

**Symptom**: Not reaching advertised network bandwidth
**Cause**: ENA configuration or instance limits
**Fix**:
```bash
# Check ENA throttling
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name NetworkBandwidthExceeded \
  --dimensions Name=InstanceId,Value=<instance-id> \
  --period 300 --statistics Sum \
  --start-time $(date -d '-1 hour' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date +%Y-%m-%dT%H:%M:%S)

# Apply ENA optimization
sudo ethtool -C eth0 adaptive-rx on  # For throughput
```

---

## Automation Scripts

### 1. Detect Graviton Generation

Detects which Graviton generation is running and recommends optimal compiler flags:

```bash
./scripts/detect-graviton-gen.sh
```

### 2. Check Performance Configuration

Scans current system for Graviton performance optimization opportunities:

```bash
./scripts/check-performance-config.sh
```

### 3. Apply System Tuning

Applies recommended kernel and OS parameters:

```bash
# Dry-run (show what would change)
./scripts/tune-system.sh --dry-run

# Apply changes
./scripts/tune-system.sh --apply
```

### 4. Check Binary Optimization

Analyzes a compiled binary for optimal Graviton compilation:

```bash
./scripts/check-binary-optimization.sh /path/to/binary
```

### 5. Profile Workload

Wrapper for performance profiling with recommended settings:

```bash
./scripts/profile-workload.sh --pid <PID> --duration 30
./scripts/profile-workload.sh --command "./my-app" --duration 60
```

### 6. Java Tuning Analyzer

Analyzes running JVM instances for Graviton optimization:

```bash
./scripts/check-java-tuning.sh
```

---

## Reference Documents

- [Language Tuning Guide](references/language-tuning-guide.md) — Detailed language-specific optimization
- [Profiling Guide](references/profiling-guide.md) — Performance profiling methodology
- [Benchmarking Best Practices](references/benchmarking-best-practices.md) — Fair comparison methodology

---

## Contact

For unresolved Graviton performance issues: ec2-arm-dev-feedback@amazon.com

---

**Version**: v1.0
**Last Updated**: 2026-02-11
**Source**: Based on [aws-graviton-getting-started](https://github.com/aws/aws-graviton-getting-started) official documentation
