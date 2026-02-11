#!/bin/bash
# check-performance-config.sh - Check system performance configuration for Graviton
# Usage: ./check-performance-config.sh

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Graviton Performance Configuration Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
OPTIMAL=0
WARNINGS=0
ISSUES=0

optimal() { OPTIMAL=$((OPTIMAL + 1)); }
warn()    { WARNINGS=$((WARNINGS + 1)); }
issue()   { ISSUES=$((ISSUES + 1)); }

# ---- Architecture ----
echo "[1/8] Architecture..."
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    echo -e "  ${GREEN}[OK]${NC} ARM64 architecture detected"
    optimal
else
    echo -e "  ${YELLOW}[WARN]${NC} Architecture: $ARCH (not Graviton)"
    echo "        This script is optimized for Graviton instances"
    warn
fi
echo ""

# ---- Kernel Version ----
echo "[2/8] Kernel version..."
KERNEL=$(uname -r)
KERNEL_MAJOR=$(echo "$KERNEL" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL" | cut -d. -f2)
echo "  Kernel: $KERNEL"
if [ "$KERNEL_MAJOR" -ge 6 ]; then
    echo -e "  ${GREEN}[OK]${NC} Kernel 6.x+ (supports latest Graviton features)"
    optimal
elif [ "$KERNEL_MAJOR" -eq 5 ] && [ "$KERNEL_MINOR" -ge 10 ]; then
    echo -e "  ${GREEN}[OK]${NC} Kernel 5.10+ (good Graviton support)"
    optimal
elif [ "$KERNEL_MAJOR" -eq 5 ] && [ "$KERNEL_MINOR" -ge 4 ]; then
    echo -e "  ${YELLOW}[WARN]${NC} Kernel 5.4 (consider upgrading for better performance)"
    warn
else
    echo -e "  ${RED}[ISSUE]${NC} Kernel < 5.4 (upgrade recommended for Graviton support)"
    issue
fi
echo ""

# ---- Transparent Huge Pages ----
echo "[3/8] Transparent Huge Pages (THP)..."
if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
    THP_STATUS=$(cat /sys/kernel/mm/transparent_hugepage/enabled | sed 's/.*\[\([a-z]*\)\].*/\1/')
    if [ "$THP_STATUS" = "always" ]; then
        echo -e "  ${GREEN}[OK]${NC} THP: always (good for most workloads)"
        echo "        Note: For Java with many threads, consider 'madvise'"
        optimal
    elif [ "$THP_STATUS" = "madvise" ]; then
        echo -e "  ${GREEN}[OK]${NC} THP: madvise (fine-grained control)"
        optimal
    elif [ "$THP_STATUS" = "never" ]; then
        echo -e "  ${YELLOW}[WARN]${NC} THP: never (disabled)"
        echo "        Recommendation: echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled"
        warn
    fi

    # Check huge page allocation
    if [ -f /proc/meminfo ]; then
        HP_TOTAL=$(grep "HugePages_Total" /proc/meminfo | awk '{print $2}')
        HP_FREE=$(grep "HugePages_Free" /proc/meminfo | awk '{print $2}')
        HP_SIZE=$(grep "Hugepagesize" /proc/meminfo | awk '{print $2, $3}')
        echo "  Huge Pages: Total=$HP_TOTAL Free=$HP_FREE Size=$HP_SIZE"
    fi
else
    echo -e "  ${YELLOW}[WARN]${NC} THP not available"
    warn
fi
echo ""

# ---- CPU Governor ----
echo "[4/8] CPU frequency governor..."
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
    if [ "$GOV" = "performance" ]; then
        echo -e "  ${GREEN}[OK]${NC} CPU governor: performance (optimal)"
        optimal
    elif [ "$GOV" = "ondemand" ] || [ "$GOV" = "schedutil" ]; then
        echo -e "  ${YELLOW}[WARN]${NC} CPU governor: $GOV"
        echo "        For benchmarking: sudo cpupower frequency-set -g performance"
        warn
    else
        echo -e "  ${YELLOW}[WARN]${NC} CPU governor: $GOV"
        warn
    fi
else
    echo "  CPU governor: not accessible (likely managed by hypervisor)"
fi
echo ""

# ---- Network Parameters ----
echo "[5/8] Network parameters..."

# Port range
PORT_RANGE=$(sysctl -n net.ipv4.ip_local_port_range 2>/dev/null || echo "unknown")
PORT_LOW=$(echo "$PORT_RANGE" | awk '{print $1}')
PORT_HIGH=$(echo "$PORT_RANGE" | awk '{print $2}')

if [ "$PORT_RANGE" != "unknown" ]; then
    RANGE_SIZE=$((PORT_HIGH - PORT_LOW))
    if [ "$RANGE_SIZE" -ge 60000 ]; then
        echo -e "  ${GREEN}[OK]${NC} Port range: $PORT_RANGE ($RANGE_SIZE ports)"
        optimal
    else
        echo -e "  ${YELLOW}[WARN]${NC} Port range: $PORT_RANGE ($RANGE_SIZE ports)"
        echo "        Recommendation: sudo sysctl -w net.ipv4.ip_local_port_range='1024 65535'"
        warn
    fi
fi

# TCP TW reuse
TW_REUSE=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null || echo "unknown")
if [ "$TW_REUSE" = "1" ] || [ "$TW_REUSE" = "2" ]; then
    echo -e "  ${GREEN}[OK]${NC} tcp_tw_reuse: $TW_REUSE (enabled)"
    optimal
elif [ "$TW_REUSE" = "0" ]; then
    echo -e "  ${YELLOW}[WARN]${NC} tcp_tw_reuse: 0 (disabled)"
    echo "        Recommendation: sudo sysctl -w net.ipv4.tcp_tw_reuse=1"
    warn
fi

# somaxconn
SOMAXCONN=$(sysctl -n net.core.somaxconn 2>/dev/null || echo "unknown")
if [ "$SOMAXCONN" != "unknown" ]; then
    if [ "$SOMAXCONN" -ge 4096 ]; then
        echo -e "  ${GREEN}[OK]${NC} somaxconn: $SOMAXCONN"
        optimal
    else
        echo -e "  ${YELLOW}[WARN]${NC} somaxconn: $SOMAXCONN (recommend >= 4096 for high-traffic servers)"
        echo "        Recommendation: sudo sysctl -w net.core.somaxconn=65535"
        warn
    fi
fi
echo ""

# ---- File Descriptor Limits ----
echo "[6/8] File descriptor limits..."
SOFT_NOFILE=$(ulimit -Sn 2>/dev/null || echo "unknown")
HARD_NOFILE=$(ulimit -Hn 2>/dev/null || echo "unknown")

if [ "$SOFT_NOFILE" != "unknown" ]; then
    if [ "$SOFT_NOFILE" -ge 65535 ]; then
        echo -e "  ${GREEN}[OK]${NC} Soft nofile: $SOFT_NOFILE"
        optimal
    else
        echo -e "  ${YELLOW}[WARN]${NC} Soft nofile: $SOFT_NOFILE (recommend >= 65535)"
        echo "        Recommendation: ulimit -n 65535"
        echo "        Permanent: add to /etc/security/limits.conf"
        warn
    fi
fi

if [ "$HARD_NOFILE" != "unknown" ]; then
    if [ "$HARD_NOFILE" -ge 65535 ]; then
        echo -e "  ${GREEN}[OK]${NC} Hard nofile: $HARD_NOFILE"
        optimal
    else
        echo -e "  ${YELLOW}[WARN]${NC} Hard nofile: $HARD_NOFILE"
        warn
    fi
fi
echo ""

# ---- Swappiness ----
echo "[7/8] Memory configuration..."
SWAPPINESS=$(sysctl -n vm.swappiness 2>/dev/null || echo "unknown")
if [ "$SWAPPINESS" != "unknown" ]; then
    if [ "$SWAPPINESS" -le 10 ]; then
        echo -e "  ${GREEN}[OK]${NC} vm.swappiness: $SWAPPINESS (low, good for performance)"
        optimal
    elif [ "$SWAPPINESS" -le 30 ]; then
        echo -e "  ${YELLOW}[WARN]${NC} vm.swappiness: $SWAPPINESS (consider lowering to 10)"
        echo "        Recommendation: sudo sysctl -w vm.swappiness=10"
        warn
    else
        echo -e "  ${YELLOW}[WARN]${NC} vm.swappiness: $SWAPPINESS (high, may cause performance issues)"
        echo "        Recommendation: sudo sysctl -w vm.swappiness=10"
        warn
    fi
fi

# NUMA
if command -v numactl &> /dev/null; then
    NUMA_NODES=$(numactl --hardware 2>/dev/null | grep "available:" | awk '{print $2}')
    if [ -n "$NUMA_NODES" ]; then
        echo "  NUMA nodes: $NUMA_NODES"
    fi
fi
echo ""

# ---- Compiler/Runtime Versions ----
echo "[8/8] Compiler and runtime versions..."

# GCC
if command -v gcc &> /dev/null; then
    GCC_VERSION=$(gcc -dumpversion)
    GCC_MAJOR=$(echo "$GCC_VERSION" | cut -d. -f1)
    if [ "$GCC_MAJOR" -ge 11 ]; then
        echo -e "  ${GREEN}[OK]${NC} GCC: $GCC_VERSION (good for Graviton3/4)"
        optimal
    elif [ "$GCC_MAJOR" -ge 10 ]; then
        echo -e "  ${GREEN}[OK]${NC} GCC: $GCC_VERSION (good, supports -moutline-atomics)"
        optimal
    elif [ "$GCC_MAJOR" -ge 9 ]; then
        echo -e "  ${YELLOW}[WARN]${NC} GCC: $GCC_VERSION (upgrade to 11+ for Graviton3/4)"
        warn
    else
        echo -e "  ${RED}[ISSUE]${NC} GCC: $GCC_VERSION (upgrade to 10+ recommended)"
        issue
    fi
else
    echo "  GCC: not installed"
fi

# Clang/LLVM
if command -v clang &> /dev/null; then
    CLANG_VERSION=$(clang --version | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1)
    echo "  Clang: $CLANG_VERSION"
fi

# Java
if command -v java &> /dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | head -1 | awk -F'"' '{print $2}')
    JAVA_MAJOR=$(echo "$JAVA_VERSION" | cut -d. -f1)
    if [ "$JAVA_MAJOR" -ge 17 ]; then
        echo -e "  ${GREEN}[OK]${NC} Java: $JAVA_VERSION (optimal for Graviton)"
        optimal
    elif [ "$JAVA_MAJOR" -ge 11 ]; then
        echo -e "  ${GREEN}[OK]${NC} Java: $JAVA_VERSION (good, consider upgrading to 17+)"
        optimal
    else
        echo -e "  ${YELLOW}[WARN]${NC} Java: $JAVA_VERSION (upgrade to 11+ recommended)"
        warn
    fi
fi

# Go
if command -v go &> /dev/null; then
    GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    GO_MINOR=$(echo "$GO_VERSION" | cut -d. -f2)
    if [ "$GO_MINOR" -ge 18 ]; then
        echo -e "  ${GREEN}[OK]${NC} Go: $GO_VERSION (register ABI, optimal for ARM64)"
        optimal
    else
        echo -e "  ${YELLOW}[WARN]${NC} Go: $GO_VERSION (upgrade to 1.18+ for 10%+ ARM64 improvement)"
        warn
    fi
fi

# Python
if command -v python3 &> /dev/null; then
    PY_VERSION=$(python3 --version | awk '{print $2}')
    PY_MINOR=$(echo "$PY_VERSION" | cut -d. -f2)
    if [ "$PY_MINOR" -ge 10 ]; then
        echo -e "  ${GREEN}[OK]${NC} Python: $PY_VERSION"
        optimal
    else
        echo -e "  ${YELLOW}[WARN]${NC} Python: $PY_VERSION (recommend 3.10+)"
        warn
    fi
fi

# Rust
if command -v rustc &> /dev/null; then
    RUST_VERSION=$(rustc --version | awk '{print $2}')
    echo "  Rust: $RUST_VERSION"
fi

# Node.js
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    echo "  Node.js: $NODE_VERSION"
fi

echo ""

# ---- Summary ----
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Check Results Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}Optimal: $OPTIMAL${NC}"
echo -e "  ${YELLOW}Warnings: $WARNINGS${NC}"
echo -e "  ${RED}Issues:   $ISSUES${NC}"
echo ""

if [ $ISSUES -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}  All checks passed! System is well-configured for Graviton.${NC}"
elif [ $ISSUES -eq 0 ]; then
    echo -e "${YELLOW}  $WARNINGS warning(s) found. Review recommendations above.${NC}"
else
    echo -e "${RED}  $ISSUES issue(s) found. Address these for optimal Graviton performance.${NC}"
fi

echo ""
echo "Next steps:"
echo "  - Apply tuning: ./scripts/tune-system.sh --dry-run"
echo "  - Check binaries: ./scripts/check-binary-optimization.sh /path/to/binary"
echo "  - Profile workload: ./scripts/profile-workload.sh --pid <PID>"
echo ""
