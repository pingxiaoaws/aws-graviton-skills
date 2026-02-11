# Language-Specific Graviton Tuning Guide

Detailed optimization guidance for each programming language on AWS Graviton processors.

## Java

### JDK Selection

| JDK Distribution | Graviton Support | Recommendation |
|-------------------|-----------------|----------------|
| Amazon Corretto | Best | **Recommended** — includes Graviton-specific patches |
| Eclipse Temurin | Good | Solid alternative |
| Oracle JDK | Good | Commercial license |
| GraalVM | Good | For native image workloads |

### JVM Flags Matrix

| Flag | Impact | Workload Type |
|------|--------|---------------|
| `-XX:-TieredCompilation` | Up to 1.5x throughput | Long-running servers |
| `-XX:ReservedCodeCacheSize=64M` | Reduced memory, better locality | All |
| `-XX:+UseTransparentHugePages` | Reduced TLB misses | All |
| `-XX:+OmitStackTraceInFastThrow` | 2x improvement for exception-heavy | Exception-heavy code |
| `-XX:ThreadStackSize=1024` | Reduced memory for many threads | Many-threaded apps |
| `-XX:+UseAESCTRIntrinsics` | 3.5-5x AES/GCM crypto | TLS/crypto workloads |

### Corretto 17 Specific

```bash
# Maximum optimization for Corretto 17+
java \
  -XX:-TieredCompilation \
  -XX:ReservedCodeCacheSize=64M \
  -XX:InitialCodeCacheSize=64M \
  -XX:CICompilerCount=2 \
  -XX:CompilationMode=high-only \
  -XX:+UseTransparentHugePages \
  -XX:+OmitStackTraceInFastThrow \
  -XX:ThreadStackSize=1024 \
  -jar app.jar
```

### Common Anti-Patterns on Graviton

1. **Exception-based control flow**: Stack trace generation is 2x more expensive on ARM64
2. **Excessive thread creation**: Default 2MB stack on aarch64 (vs 1MB on x86)
3. **Unfair benchmarking**: Each Graviton vCPU is a full core — push to higher utilization
4. **Missing THP**: Enable THP or huge pages for JVM heap

---

## Python

### NumPy/SciPy Optimization

```bash
# Ensure Graviton-optimized OpenBLAS
pip install "numpy>=1.21.1"  # Includes Graviton-specific gemv/gemm
pip install "scipy>=1.7.2"

# Verify BLAS backend
python3 -c "import numpy; numpy.show_config()"

# Enable multi-threading
export OMP_NUM_THREADS=$(nproc)

# BLIS alternative (may be faster for some workloads)
pip install blis
export BLIS_NUM_THREADS=$(nproc)
```

### BLAS Priority Control

```bash
# Prioritize OpenBLAS
export NPY_BLAS_ORDER=openblas,blis
export NPY_LAPACK_ORDER=openblas

# Or prioritize BLIS
export NPY_BLAS_ORDER=blis,openblas
```

### PyTorch on Graviton

```bash
# CPU-only PyTorch for ARM64
pip install torch --index-url https://download.pytorch.org/whl/cpu

# Verify ARM64 optimization
python3 -c "import torch; print(torch.__config__.show())"
```

---

## Go

### Version Impact

| Go Version | Key Improvement on ARM64 |
|------------|--------------------------|
| 1.16 | ARMv8.1-A atomics for mutex performance |
| 1.17 | crypto/ed25519 2x faster, P-521 3x faster |
| 1.18+ | Register-based calling convention: **10%+ improvement** |

### Container CPU Limits

```go
// Problem: GOMAXPROCS defaults to host CPU count in containers
// Solution 1: Set manually
// GOMAXPROCS=2 (for --cpus=2)

// Solution 2: Use automaxprocs
import _ "go.uber.org/automaxprocs"
```

### Build Flags

```bash
# Cross-compile for Graviton
GOOS=linux GOARCH=arm64 go build -o app

# Enable PGO (Go 1.21+)
go build -pgo=auto -o app
```

---

## Rust

### Compiler Flags

```bash
# LSE atomics (critical for multi-threaded)
RUSTFLAGS="-Ctarget-feature=+lse"

# Target specific generation
RUSTFLAGS="-Ctarget-cpu=neoverse-n1"  # Graviton2
RUSTFLAGS="-Ctarget-cpu=neoverse-v1"  # Graviton3
RUSTFLAGS="-Ctarget-cpu=neoverse-v2"  # Graviton4

# Combined (Graviton2+ with LSE)
RUSTFLAGS="-Ctarget-cpu=neoverse-n1 -Ctarget-feature=+lse"

# LTO for release builds
[profile.release]
lto = true
codegen-units = 1
```

### Cross-Compilation

```bash
# Add ARM64 target
rustup target add aarch64-unknown-linux-gnu

# Build
cargo build --release --target aarch64-unknown-linux-gnu
```

---

## C/C++

### Signed Char Difference

```c
// ARM defaults to UNSIGNED char (x86 = signed)
// BAD: char c = -1;  // Different behavior on ARM vs x86
// GOOD: int8_t c = -1;  // Explicit signed
// GOOD: uint8_t c = 255;  // Explicit unsigned

// Or compile with:
// gcc -fsigned-char  (match x86 behavior)
```

### SIMD Migration

```c
// x86 SSE → ARM NEON migration paths:

// Option 1: SSE2NEON (drop-in replacement)
// Replace: #include <emmintrin.h>
// With:    #include "sse2neon.h"
// No other code changes needed

// Option 2: SIMDe (broader coverage)
// #include "simde/x86/sse2.h"

// Option 3: Native NEON (best performance)
#include <arm_neon.h>
float32x4_t a = vld1q_f32(ptr);
float32x4_t b = vmulq_f32(a, a);
vst1q_f32(ptr, b);
```

### Recommended Flags by Graviton Generation

```bash
# Graviton2
CFLAGS="-mcpu=neoverse-n1 -O2 -flto"

# Graviton3
CFLAGS="-mcpu=neoverse-v1 -O2 -flto"
# With SVE:
CFLAGS="-mcpu=neoverse-v1 -msve-vector-bits=256 -O2 -flto"

# Graviton4
CFLAGS="-mcpu=neoverse-v2 -O2 -flto"

# Portable (all Graviton2+)
CFLAGS="-march=armv8.2-a -moutline-atomics -O2 -flto"
```

---

## Node.js

### Architecture Optimization

```bash
# Use statically linked binaries from nodejs.org
# Reduced function-call overhead vs distro packages

# Multi-process architecture (Node is single-threaded)
# Option 1: Cluster module
node cluster-app.js

# Option 2: PM2
pm2 start app.js -i max

# Option 3: Nginx as reverse proxy with multiple Node processes
```

### V8 JIT Issue

```bash
# For regex-heavy workloads — avoids veneer chain issue
node --regexp-interpret-all app.js
```

---

## .NET

### Build for ARM64

```bash
# .NET 8+ recommended for best arm64 vectorization
dotnet publish -c Release -r linux-arm64

# Self-contained deployment
dotnet publish -c Release -r linux-arm64 --self-contained true

# AOT compilation (.NET 8+)
dotnet publish -c Release -r linux-arm64 -p:PublishAot=true
```

---

## PHP

### OPcache

```bash
# AL2023: Included by default
# AL2: Install manually
sudo yum install -y php-opcache

# Verify OPcache status
php -i | grep opcache

# Optimize OPcache settings (php.ini)
opcache.enable=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=4000
opcache.revalidate_freq=60
opcache.fast_shutdown=1
```
