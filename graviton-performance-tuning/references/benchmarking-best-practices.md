# Graviton Benchmarking Best Practices

## Methodology

### 1. Use Production Workloads

Synthetic benchmarks often don't reflect real-world performance. Always validate with actual production workloads.

```bash
# Bad: Synthetic microbenchmark
sysbench cpu run

# Good: Actual application benchmark with production data
./run-load-test.sh --scenario production --duration 300
```

### 2. Match Environments

Ensure fair comparison between x86 and Graviton:

| Factor | Must Match |
|--------|-----------|
| OS version | Same major version |
| Kernel version | Same or very close |
| Package versions | Identical |
| Configuration | Same settings |
| Data set | Identical |
| Network topology | Same placement |

### 3. Instance Selection

```
Graviton2 comparisons:
  c6g vs c5/c5a (compute)
  m6g vs m5/m5a (general)
  r6g vs r5/r5a (memory)

Graviton3 comparisons:
  c7g vs c6i (compute)
  m7g vs m6i (general)
  r7g vs r6i (memory)

Graviton4 comparisons:
  c8g vs c7i (compute)
  m8g vs m7i (general)
  r8g vs r7i (memory)
```

### 4. Dedicated Tenancy (Initial)

Use dedicated tenancy for initial benchmarks to establish a variance baseline. Shared tenancy introduces neighbor noise.

```bash
# Launch with dedicated tenancy
aws ec2 run-instances \
  --instance-type c7g.xlarge \
  --tenancy dedicated \
  ...
```

## Test Setup

### Load Generator Sizing

```bash
# Load generator should be at least 12xlarge
# Ensure generator spends <50% CPU on load generation
# Use multiple generators if needed

# Verify generator is not the bottleneck:
top  # CPU should be < 50% on load generator
```

### Network Configuration

```bash
# Use placement groups for network benchmarks
aws ec2 create-placement-group \
  --group-name bench-cluster \
  --strategy cluster

# All instances in same subnet
# Verify latency:
ping <target-ip>     # Should be tens of microseconds
traceroute <target-ip>  # Should be 3 or fewer hops
```

### Warm-Up Period

Allow applications to warm up before measuring:

```bash
# JVM: Wait for JIT compilation
# Typically 2-5 minutes of sustained load

# General: Wait for caches to fill
# Run load for 2-3 minutes before recording metrics
```

## Key Architectural Differences

### No Hyperthreading

Graviton's most important architectural difference:

```
x86 (c6i.8xlarge):
  32 vCPUs = 16 physical cores x 2 threads
  At 100% CPU utilization: ~63% effective compute

Graviton (c7g.8xlarge):
  32 vCPUs = 32 physical cores x 1 thread
  At 100% CPU utilization: ~96% effective compute
```

**Implications:**
- Graviton scales nearly linearly to 100% CPU
- x86 shows diminishing returns after 50% CPU
- Load balancer thresholds can be higher on Graviton
- Fewer Graviton instances may handle same load

### Testing at Saturation

```bash
# Test at multiple load levels
for load in 25 50 75 90 95 100; do
  echo "Testing at ${load}% target CPU..."
  ./benchmark --threads $(nproc) --target-cpu-pct $load --duration 120
done

# Compare: Graviton maintains performance at high utilization
# x86 degrades significantly above 50%
```

## Binary Verification

Before benchmarking, verify binaries are properly compiled:

### Check for ARM64 Optimization

```bash
# Verify architecture
file ./your-binary
# Should show: ELF 64-bit LSB ... aarch64

# Check for LSE atomics
objdump -d ./your-binary | grep -c "cas\b\|casp\|ldadd\|stadd\|swp\b"
# Should be > 0 for multi-threaded applications

# Check for NEON vectorization
objdump -d ./your-binary | grep -c "fmla\|fmul\|fadd\|ld1\|st1"
# Higher is better for numerical workloads
```

### Java Binary Dependencies

```bash
# Check for x86 native libraries in JARs
find /path/to/app -name "*.jar" -exec unzip -l {} \; 2>/dev/null | \
  grep "\.so$" | grep -v "aarch64\|arm64"

# Check for assembly code
find /path/to/app -name "*.S" -o -name "*.s" | head -20
grep -r "__asm__" /path/to/app --include="*.c" --include="*.cpp" | head -10
```

## Metrics to Collect

### System Metrics

```bash
# CPU utilization (per-core)
mpstat -P ALL 1

# Memory
vmstat 1
free -h

# Disk I/O
iostat -x 1

# Network
sar -n DEV 1
```

### Application Metrics

| Metric | Why |
|--------|-----|
| Requests/second (throughput) | Primary performance metric |
| p50/p99/p999 latency | User experience metric |
| Error rate | Correctness verification |
| CPU utilization | Efficiency metric |
| Memory usage | Resource efficiency |
| Context switches | Scheduling efficiency |

### Comparison Template

```
Benchmark: [workload name]
Date: [date]
Duration: [seconds]

| Metric | x86 (c6i.xlarge) | Graviton (c7g.xlarge) | Difference |
|--------|-------------------|-----------------------|------------|
| Throughput (req/s) | | | |
| p50 latency (ms) | | | |
| p99 latency (ms) | | | |
| CPU utilization (%) | | | |
| Memory (MB) | | | |
| Cost/hour ($) | | | |
| Cost per 1M requests ($) | | | |
```

## Common Pitfalls

### 1. Unfair JVM Comparison

```bash
# BAD: Different JVM flags
# x86:     java -jar app.jar
# Graviton: java -jar app.jar
# (both use defaults, but defaults may differ)

# GOOD: Explicit matching flags
java \
  -XX:-TieredCompilation \
  -XX:ReservedCodeCacheSize=64M \
  -Xmx4g -Xms4g \
  -jar app.jar
```

### 2. Missing LSE Atomics

```bash
# Verify before benchmarking
objdump -d /path/to/binary | grep -c "cas\b\|ldadd\|swp\b"
# If 0, recompile with -march=armv8.2-a or -moutline-atomics
```

### 3. Go GOMAXPROCS in Containers

```bash
# Container sees all host CPUs by default
# Set explicitly:
GOMAXPROCS=<container-cpu-limit>
```

### 4. Python Single-Threaded BLAS

```bash
# Default: single-threaded numerical operations
export OMP_NUM_THREADS=$(nproc)
```

### 5. Testing Only at Low Load

```bash
# Graviton advantage appears at higher utilization
# Always test at 75%+ CPU target
```

## Reporting Results

### Price-Performance Comparison

```bash
# Calculate cost per request
COST_PER_HOUR_X86=0.17   # c6i.xlarge
COST_PER_HOUR_ARM=0.1445  # c7g.xlarge

THROUGHPUT_X86=10000  # req/s
THROUGHPUT_ARM=11000  # req/s

COST_PER_MILLION_X86=$(echo "scale=4; $COST_PER_HOUR_X86 / $THROUGHPUT_X86 / 3.6" | bc)
COST_PER_MILLION_ARM=$(echo "scale=4; $COST_PER_HOUR_ARM / $THROUGHPUT_ARM / 3.6" | bc)

echo "Cost per million requests:"
echo "  x86:     $COST_PER_MILLION_X86"
echo "  Graviton: $COST_PER_MILLION_ARM"
```

### Fleet Size Estimation

Since Graviton maintains performance at higher utilization:

```bash
# x86: Target 50% CPU (hyperthreading degradation beyond)
# Graviton: Target 70-80% CPU (linear scaling)

# Example: 100K req/s production load
# x86 at 50% = 20 instances
# Graviton at 75% = 12 instances (40% fewer instances)
```
