#!/bin/bash
# check-binary-optimization.sh - Analyze binary for optimal Graviton compilation
# Usage: ./check-binary-optimization.sh /path/to/binary

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
    echo "Usage: $0 <binary-path> [OPTIONS]"
    echo ""
    echo "Analyze a compiled binary for optimal Graviton compilation flags."
    echo ""
    echo "OPTIONS:"
    echo "    -v, --verbose   Show detailed disassembly analysis"
    echo "    -h, --help      Show this help"
    echo ""
    echo "EXAMPLES:"
    echo "    $0 /usr/local/bin/my-app"
    echo "    $0 ./target/release/my-rust-app --verbose"
    echo ""
}

BINARY=""
VERBOSE=false

while [ $# -gt 0 ]; do
    case "$1" in
        -v|--verbose) VERBOSE=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        -*) echo "Unknown option: $1"; show_help; exit 1 ;;
        *) BINARY="$1"; shift ;;
    esac
done

if [ -z "$BINARY" ]; then
    echo "Error: No binary path provided"
    echo ""
    show_help
    exit 1
fi

if [ ! -f "$BINARY" ]; then
    echo "Error: File not found: $BINARY"
    exit 1
fi

# Check for required tools
for cmd in objdump file readelf; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: $cmd is required but not installed${NC}"
        exit 1
    fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Binary Optimization Analysis"
echo "  Target: $BINARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

OPTIMAL=0
WARNINGS=0
ISSUES=0

optimal() { OPTIMAL=$((OPTIMAL + 1)); }
warn()    { WARNINGS=$((WARNINGS + 1)); }
issue()   { ISSUES=$((ISSUES + 1)); }

# ---- File Type ----
echo "[1/6] File type..."
FILE_INFO=$(file "$BINARY")
echo "  $FILE_INFO"

if echo "$FILE_INFO" | grep -qi "aarch64\|arm64\|ARM aarch64"; then
    echo -e "  ${GREEN}[OK]${NC} ARM64/aarch64 binary"
    optimal
elif echo "$FILE_INFO" | grep -qi "x86-64\|x86_64\|AMD64"; then
    echo -e "  ${RED}[ISSUE]${NC} x86_64 binary (not ARM64!)"
    echo "        This binary was compiled for x86. Recompile for ARM64."
    issue
    echo ""
    echo "Summary: Binary is x86_64, cannot analyze for Graviton optimization."
    exit 1
else
    echo -e "  ${YELLOW}[WARN]${NC} Unknown architecture"
    warn
fi
echo ""

# ---- LSE Atomics ----
echo "[2/6] LSE Atomics (Large System Extensions)..."
LSE_COUNT=$(objdump -d "$BINARY" 2>/dev/null | grep -cE "cas[[:space:]]|casp|casb|cash|ldadd|stadd|swp[[:space:]]|swpb|ldclr|stclr" || true)

if [ "$LSE_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}[OK]${NC} LSE instructions found: $LSE_COUNT occurrences"
    echo "        Binary uses LSE atomics (CAS, LDADD, SWP, etc.)"
    optimal

    if [ "$VERBOSE" = true ]; then
        echo ""
        echo "  LSE instruction breakdown:"
        objdump -d "$BINARY" 2>/dev/null | grep -oE "cas[[:space:]]|casp|casb|cash|ldadd|stadd|swp[[:space:]]|swpb|ldclr|stclr" | sort | uniq -c | sort -rn | head -10 | while read count instr; do
            echo "    $count x $instr"
        done
    fi
else
    # Check for outline atomics (runtime detection)
    OUTLINE_COUNT=$(objdump -d "$BINARY" 2>/dev/null | grep -c "__aarch64_cas\|__aarch64_ldadd\|__aarch64_swp" || true)
    if [ "$OUTLINE_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}[OK]${NC} Outline atomics detected: $OUTLINE_COUNT references"
        echo "        Binary uses -moutline-atomics (runtime LSE detection)"
        optimal
    else
        # Check for legacy LL/SC atomics
        LDXR_COUNT=$(objdump -d "$BINARY" 2>/dev/null | grep -cE "ldxr|ldaxr|stxr|stlxr" || true)
        if [ "$LDXR_COUNT" -gt 0 ]; then
            echo -e "  ${RED}[ISSUE]${NC} Legacy LL/SC atomics only ($LDXR_COUNT occurrences)"
            echo "        No LSE or outline atomics found!"
            echo "        Recompile with: -march=armv8.2-a or -moutline-atomics"
            echo "        Impact: Up to 10x worse lock performance on large instances"
            issue
        else
            echo -e "  ${YELLOW}[WARN]${NC} No atomic instructions detected"
            echo "        Binary may not use atomics, or analysis was inconclusive"
            warn
        fi
    fi
fi
echo ""

# ---- NEON/SIMD ----
echo "[3/6] NEON/SIMD vectorization..."
NEON_COUNT=$(objdump -d "$BINARY" 2>/dev/null | grep -cE "fmla|fmul|fadd|fsub|fmax|fmin|ld1|st1|dup|movi|addv|saddl|uaddl" || true)

if [ "$NEON_COUNT" -gt 100 ]; then
    echo -e "  ${GREEN}[OK]${NC} NEON instructions found: $NEON_COUNT occurrences"
    echo "        Binary uses SIMD vectorization"
    optimal
elif [ "$NEON_COUNT" -gt 0 ]; then
    echo -e "  ${YELLOW}[WARN]${NC} Limited NEON usage: $NEON_COUNT occurrences"
    echo "        Consider enabling auto-vectorization: -O2 or -O3"
    warn
else
    echo -e "  ${YELLOW}[WARN]${NC} No NEON instructions detected"
    echo "        May benefit from: -O2 -ftree-vectorize"
    warn
fi
echo ""

# ---- SVE ----
echo "[4/6] SVE (Scalable Vector Extension)..."
SVE_COUNT=$(objdump -d "$BINARY" 2>/dev/null | grep -cE "z[0-9]+\.[bhsd]|p[0-9]+/[mz]|whilel|ptrue|pfalse|sve_" || true)

if [ "$SVE_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}[OK]${NC} SVE instructions found: $SVE_COUNT occurrences"
    echo "        Binary uses SVE (optimal for Graviton3/4)"
    optimal
else
    echo "  SVE instructions: none detected"
    echo "        SVE available on Graviton3 (256-bit) and Graviton4 (128-bit)"
    echo "        Enable with: -mcpu=neoverse-v1 (GCC 11+) or -march=armv8.4-a+sve"
fi
echo ""

# ---- Crypto Instructions ----
echo "[5/6] Crypto acceleration..."
CRYPTO_COUNT=$(objdump -d "$BINARY" 2>/dev/null | grep -cE "aese|aesd|aesmc|aesimc|sha256h|sha256su|sha1" || true)

if [ "$CRYPTO_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}[OK]${NC} Crypto instructions found: $CRYPTO_COUNT occurrences"
    echo "        Binary uses hardware AES/SHA acceleration"
    optimal
else
    echo "  No crypto instructions detected (normal for non-crypto workloads)"
fi
echo ""

# ---- CRC32 Instructions ----
echo "[6/6] CRC32 acceleration..."
CRC_COUNT=$(objdump -d "$BINARY" 2>/dev/null | grep -cE "crc32[bcdhwx]" || true)

if [ "$CRC_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}[OK]${NC} CRC32 instructions found: $CRC_COUNT occurrences"
    optimal
else
    echo "  No CRC32 instructions detected (normal for many workloads)"
fi
echo ""

# ---- Build Info ----
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Build Information"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check for build metadata
COMMENT=$(readelf -p .comment "$BINARY" 2>/dev/null | grep -v "^$\|String" | head -5 || true)
if [ -n "$COMMENT" ]; then
    echo "  Compiler info:"
    echo "$COMMENT" | while read line; do
        echo "    $line"
    done
fi

# Check ELF attributes
BUILD_ATTRS=$(readelf -A "$BINARY" 2>/dev/null | grep -E "Tag_|arch" | head -10 || true)
if [ -n "$BUILD_ATTRS" ]; then
    echo "  ELF attributes:"
    echo "$BUILD_ATTRS" | while read line; do
        echo "    $line"
    done
fi

echo ""

# ---- Summary ----
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Analysis Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}Optimal: $OPTIMAL${NC}"
echo -e "  ${YELLOW}Warnings: $WARNINGS${NC}"
echo -e "  ${RED}Issues:   $ISSUES${NC}"
echo ""

if [ $ISSUES -gt 0 ]; then
    echo -e "${RED}  Critical issues found! Recompilation recommended.${NC}"
    echo ""
    echo "  Recommended recompilation flags:"
    echo "    GCC/Clang: -march=armv8.2-a -moutline-atomics -O2 -flto"
    echo "    Rust:      RUSTFLAGS=\"-Ctarget-feature=+lse -Ctarget-cpu=neoverse-n1\""
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}  Some optimizations may be missing. Review warnings above.${NC}"
else
    echo -e "${GREEN}  Binary is well-optimized for Graviton!${NC}"
fi
echo ""
