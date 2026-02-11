# Graviton Performance Profiling Guide

## Overview

This guide covers performance profiling methodology specific to AWS Graviton processors. Graviton's architecture (no SMT, full physical cores) requires adjusted profiling approaches compared to x86.

## Tools Overview

| Tool | Best For | Availability |
|------|----------|--------------|
| **AWS APerf** | First-line automated analysis | All instances |
| **Linux perf** | Detailed CPU profiling, flamegraphs | All instances |
| **SPE** | Per-instruction tracing | Metal instances (Graviton2/3) |
| **CMN PMU** | System fabric monitoring | Metal instances |
| **eBPF/BCC** | Kernel-level investigation | All instances |
| **Java Flight Recorder** | JVM profiling | JVM workloads |

## Quick Start: AWS APerf

APerf is the recommended first-line tool for Graviton performance analysis.

```bash
# Install
curl -L https://github.com/aws/aperf/releases/latest/download/aperf-x86_64-unknown-linux-gnu -o aperf
chmod +x aperf
sudo mv aperf /usr/local/bin/

# Record (30 seconds)
sudo aperf record -d 30

# Generate report
aperf report

# Open HTML report
open aperf_report.html
```

## On-CPU Profiling

### When to Use
- Application is CPU-bound (high CPU utilization)
- Need to find hot functions consuming CPU time
- Comparing performance between x86 and Graviton

### Methodology

```bash
# 1. Compile with debug symbols and frame pointers
CFLAGS="-g -fno-omit-frame-pointer"

# 2. Record CPU samples
sudo perf record -F 99 -ag -- sleep 30

# 3. Generate flamegraph
sudo perf script | stackcollapse-perf.pl | flamegraph.pl > oncpu.svg

# 4. Alternative: record specific process
sudo perf record -F 99 -p <PID> -g -- sleep 30
```

### Interpreting On-CPU Flamegraphs

- **Wide bars at top**: Hot functions consuming most CPU
- **Deep stacks**: Complex call chains (may benefit from -flto)
- **`arch_local_irq_restore`**: Enable pseudo-NMI (see below)
- **`__aarch64_ldadd_acq_rel`**: Outline atomics in use (normal)
- **`ldxr/stxr` loops**: Legacy atomics, recompile with LSE

## Off-CPU Profiling

### When to Use
- Application has low CPU utilization but high latency
- Suspect lock contention or I/O blocking
- Threads are waiting instead of working

### Methodology

```bash
# Record scheduler events
sudo perf record -e sched:sched_switch -p <PID> -g -- sleep 30

# Generate off-CPU flamegraph
sudo perf script | stackcollapse-perf.pl | flamegraph.pl \
  --color=io --title="Off-CPU Flamegraph" > offcpu.svg
```

### What to Look For

| Pattern in Stack | Indicates | Action |
|------------------|-----------|--------|
| `futex_wait` | Lock contention | Enable LSE atomics |
| `mutex_lock` | Mutex contention | Consider lock-free or RW locks |
| `semaphore` | Semaphore wait | Review concurrency design |
| `epoll_wait` | I/O wait | Normal for event loops |
| `read`/`write` | Disk I/O | Check storage performance |
| `work_pending` | Involuntary preemption | Ignore (scheduler noise) |

## PMU Counter Analysis

### Top-Down Methodology

```bash
# Step 1: Basic IPC measurement
perf stat -e cycles,instructions,cache-references,cache-misses \
  -- <command>

# IPC = instructions / cycles
# Good: IPC > 2.0
# Investigate: IPC < 1.0
```

```bash
# Step 2: Frontend analysis (instruction delivery)
perf stat -e \
  L1-icache-load-misses,\
  iTLB-load-misses,\
  branch-misses \
  -- <command>

# Warning thresholds:
# branch-mpki > 10    → Branch prediction issues
# inst-l1-mpki > 20   → Instruction cache pressure
# iTLB misses high    → Large code footprint
```

```bash
# Step 3: Backend analysis (data access)
perf stat -e \
  L1-dcache-load-misses,\
  L2-cache-misses,\
  LLC-load-misses,\
  dTLB-load-misses \
  -- <command>

# Warning thresholds:
# data-l1-mpki > 20   → Data cache misses
# l2-mpki > 10        → L2 cache pressure
# l3-mpki > 10        → Memory-bound workload
# dTLB misses high    → Enable huge pages
```

### PMU Instance Requirements

Full PMU counter access requires specific instance sizes:

| Graviton Gen | Minimum Instance |
|-------------|------------------|
| Graviton2 | c6g.16xlarge |
| Graviton3 | c7g.16xlarge |
| Graviton4 | c8g.16xlarge |

Smaller instances provide shared/sampled access.

## Pseudo-NMI for Kernel Profiling

When `perf` shows excessive time in `arch_local_irq_restore`, kernel interrupts are interfering with profiling.

### Setup

```bash
# Check kernel support
grep CONFIG_ARM64_PSEUDO_NMI /boot/config-$(uname -r)

# Enable (add to kernel command line in GRUB)
irqchip.gicv3_pseudo_nmi=1

# Use hardware PMU events instead of software
sudo perf record -e r11 -ag -- sleep 30    # r11 = CPU cycles (Graviton)
sudo perf record -e r8 -ag -- sleep 30     # r8 = instructions retired
```

## SPE (Statistical Profiling Extension)

Available on **Graviton2/3 metal instances** only.

```bash
# Check SPE support
ls /sys/bus/event_source/devices/arm_spe_0/

# Record SPE events
perf record -e arm_spe// -a -- sleep 10

# Analyze
perf report --sort=symbol
```

SPE provides per-instruction metrics including:
- Cache miss attribution
- TLB miss source
- Branch mispredict source
- Latency per instruction

## Java Profiling

### JFR (Java Flight Recorder)

```bash
# Enable JFR
java -XX:StartFlightRecording=duration=60s,filename=recording.jfr \
     -jar app.jar

# Or attach to running JVM
jcmd <PID> JFR.start duration=60s filename=recording.jfr
```

### perf + JVM

```bash
# Launch JVM with frame pointers and perf agent
java -XX:+PreserveFramePointer \
     -agentpath:/usr/lib64/libperf-jvmti.so \
     -jar app.jar

# Record with perf
sudo perf record -F 99 -p <JVM_PID> -g -- sleep 30

# The perf agent enables Java symbol resolution in flamegraphs
```

### async-profiler (Recommended for JVM)

```bash
# Download
curl -L https://github.com/async-profiler/async-profiler/releases/latest/download/async-profiler-linux-arm64.tar.gz | tar xz

# Profile
./asprof -d 30 -f flamegraph.html <PID>

# CPU + allocation profiling
./asprof -d 30 -e cpu,alloc -f combined.html <PID>
```

## Graviton-Specific Profiling Tips

### 1. No Hyperthreading Consideration

Every vCPU is a physical core. When comparing with x86:
- Graviton at 100% CPU = truly 100% compute
- x86 at 100% CPU = 50% compute + 50% hyperthreading overhead

### 2. LSE Detection in Profiles

Look for these patterns in flamegraphs:
- `__aarch64_cas_*` → Outline atomics (good, portable)
- `__aarch64_ldadd_*` → Outline atomics (good, portable)
- `ldxr`/`stxr` loops → Legacy atomics (bad, needs recompilation)
- `cas`/`casp`/`swp` → Direct LSE (best)

### 3. Large Core Count Scaling

On Graviton4 (up to 192 cores):
- Profile at target core count, not reduced
- Lock contention amplifies with more cores
- LSE impact is proportional to core count

### 4. Cache Line Size

Graviton uses 64-byte cache lines (same as most x86). Data structures should be aligned to 64 bytes for optimal performance.

```c
// Align to cache line
struct __attribute__((aligned(64))) PerCpuData {
    uint64_t counter;
    // padding to fill cache line
    char pad[56];
};
```
