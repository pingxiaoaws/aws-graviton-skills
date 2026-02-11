#!/bin/bash
# detect-graviton-gen.sh - Detect Graviton generation and recommend optimal settings
# Usage: ./detect-graviton-gen.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Graviton Generation Detection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check architecture
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
    echo -e "${YELLOW}  Architecture: $ARCH (not ARM64/Graviton)${NC}"
    echo ""
    echo "This script is designed for Graviton instances."
    echo "You appear to be on an x86_64 system."
    echo ""
    echo "Generic ARM64 compiler flags for cross-compilation:"
    echo "  -march=armv8.2-a -moutline-atomics"
    echo ""
    exit 0
fi

echo -e "${GREEN}  Architecture: $ARCH (ARM64)${NC}"

# Detect Graviton generation from instance type via IMDS
GRAVITON_GEN="unknown"
INSTANCE_TYPE=""
CPU_IMPL=""
CPU_PART=""

# Try IMDS v2 first
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)
if [ -n "$TOKEN" ]; then
    INSTANCE_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || true)
else
    # Try IMDS v1
    INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || true)
fi

# Read CPU info
if [ -f /proc/cpuinfo ]; then
    CPU_IMPL=$(grep -m1 "CPU implementer" /proc/cpuinfo | awk '{print $NF}' || true)
    CPU_PART=$(grep -m1 "CPU part" /proc/cpuinfo | awk '{print $NF}' || true)
fi

# Determine Graviton generation
if [ -n "$INSTANCE_TYPE" ]; then
    echo "  Instance Type: $INSTANCE_TYPE"

    # Parse instance family to determine Graviton gen
    FAMILY=$(echo "$INSTANCE_TYPE" | sed 's/\([a-z]*[0-9]*[a-z]*\)\..*/\1/')

    case "$FAMILY" in
        *8g*|*8gd*|*8gn*)
            GRAVITON_GEN="4"
            ;;
        *7g*|*7gd*|*7gn*|*c7gn*|*c7gd*)
            GRAVITON_GEN="3"
            ;;
        *7ge*)
            GRAVITON_GEN="3E"
            ;;
        *6g*|*6gd*|*6gn*|*t4g*)
            GRAVITON_GEN="2"
            ;;
        *a1*|*m6g*|*c6g*|*r6g*)
            # More specific matching for 6g family
            if echo "$FAMILY" | grep -qE "^(m6g|c6g|r6g|x2gd|im4gn|is4gen|t4g)"; then
                GRAVITON_GEN="2"
            fi
            ;;
    esac
fi

# Fallback: detect from CPU part number
if [ "$GRAVITON_GEN" = "unknown" ] && [ -n "$CPU_PART" ]; then
    case "$CPU_PART" in
        0xd0c)  GRAVITON_GEN="2" ;;   # Neoverse N1
        0xd40)  GRAVITON_GEN="3" ;;   # Neoverse V1
        0xd4f)  GRAVITON_GEN="4" ;;   # Neoverse V2
    esac
fi

# Fallback: detect from /sys/devices
if [ "$GRAVITON_GEN" = "unknown" ]; then
    if [ -d /sys/devices/system/cpu/cpu0 ]; then
        # Check for SVE support as a differentiator
        if grep -q "sve" /proc/cpuinfo 2>/dev/null; then
            if [ -n "$CPU_PART" ] && [ "$CPU_PART" = "0xd4f" ]; then
                GRAVITON_GEN="4"
            else
                GRAVITON_GEN="3"
            fi
        else
            GRAVITON_GEN="2"
        fi
    fi
fi

echo ""

# Display generation info and recommendations
case "$GRAVITON_GEN" in
    "2")
        echo -e "${GREEN}  Graviton Generation: Graviton2 (Neoverse N1)${NC}"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Recommended Compiler Flags"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  C/C++ (GCC 9+):"
        echo "    CFLAGS=\"-mcpu=neoverse-n1 -flto\""
        echo ""
        echo "  C/C++ (portable, GCC 10+):"
        echo "    CFLAGS=\"-march=armv8.2-a -moutline-atomics -flto\""
        echo ""
        echo "  Rust:"
        echo "    RUSTFLAGS=\"-Ctarget-cpu=neoverse-n1 -Ctarget-feature=+lse\""
        echo ""
        echo "  Go: Use Go 1.18+ (register ABI, ~10% improvement)"
        echo ""
        echo "  Features: LSE atomics, no SVE"
        echo "  Recommended GCC: 9+"
        echo "  Recommended LLVM: 10+"
        ;;
    "3"|"3E")
        echo -e "${GREEN}  Graviton Generation: Graviton${GRAVITON_GEN} (Neoverse V1)${NC}"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Recommended Compiler Flags"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  C/C++ (GCC 11+, best):"
        echo "    CFLAGS=\"-mcpu=neoverse-v1 -flto\""
        echo ""
        echo "  C/C++ (portable, GCC 10+):"
        echo "    CFLAGS=\"-march=armv8.2-a -moutline-atomics -flto\""
        echo ""
        echo "  C/C++ (SVE enabled):"
        echo "    CFLAGS=\"-mcpu=neoverse-v1 -msve-vector-bits=256 -flto\""
        echo ""
        echo "  Rust:"
        echo "    RUSTFLAGS=\"-Ctarget-cpu=neoverse-v1 -Ctarget-feature=+lse\""
        echo ""
        echo "  Go: Use Go 1.18+ (register ABI, ~10% improvement)"
        echo ""
        echo "  Features: LSE atomics, SVE (256-bit), BFloat16"
        echo "  Recommended GCC: 11+"
        echo "  Recommended LLVM: 14+"
        ;;
    "4")
        echo -e "${GREEN}  Graviton Generation: Graviton4 (Neoverse V2)${NC}"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Recommended Compiler Flags"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  C/C++ (GCC 13+, best):"
        echo "    CFLAGS=\"-mcpu=neoverse-v2 -flto\""
        echo ""
        echo "  C/C++ (portable, GCC 10+):"
        echo "    CFLAGS=\"-march=armv8.2-a -moutline-atomics -flto\""
        echo ""
        echo "  C/C++ (balanced Graviton3+4):"
        echo "    CFLAGS=\"-mcpu=neoverse-512tvb -flto\""
        echo ""
        echo "  Rust:"
        echo "    RUSTFLAGS=\"-Ctarget-cpu=neoverse-v2 -Ctarget-feature=+lse\""
        echo ""
        echo "  Go: Use Go 1.18+ (register ABI, ~10% improvement)"
        echo ""
        echo "  Features: LSE atomics, SVE (128-bit), BFloat16, up to 192 vCPUs"
        echo "  Recommended GCC: 13+"
        echo "  Recommended LLVM: 16+"
        ;;
    *)
        echo -e "${YELLOW}  Graviton Generation: Unknown${NC}"
        echo ""
        echo "Could not determine Graviton generation."
        echo "Using universal flags:"
        echo ""
        echo "  CFLAGS=\"-march=armv8.2-a -moutline-atomics -flto\""
        echo "  RUSTFLAGS=\"-Ctarget-feature=+lse\""
        ;;
esac

echo ""

# Show CPU features
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  CPU Features Detected"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -f /proc/cpuinfo ]; then
    FEATURES=$(grep -m1 "Features" /proc/cpuinfo | cut -d: -f2 | tr -s ' ')

    # Check key features
    check_feature() {
        local feature=$1
        local label=$2
        if echo "$FEATURES" | grep -qw "$feature"; then
            echo -e "  ${GREEN}[Y]${NC} $label ($feature)"
        else
            echo -e "  ${RED}[N]${NC} $label ($feature)"
        fi
    }

    check_feature "atomics" "LSE Atomics"
    check_feature "crc32" "CRC32 Instructions"
    check_feature "aes" "AES Acceleration"
    check_feature "sha2" "SHA-2 Acceleration"
    check_feature "fphp" "Half-Precision FP"
    check_feature "asimddp" "Dot-Product (ASIMD)"
    check_feature "sve" "SVE (Scalable Vector)"
    check_feature "bf16" "BFloat16"
else
    echo "  /proc/cpuinfo not available"
fi

# Show vCPU count
echo ""
VCPU_COUNT=$(nproc)
echo "  vCPU Count: $VCPU_COUNT (all physical cores, no SMT)"

echo ""
