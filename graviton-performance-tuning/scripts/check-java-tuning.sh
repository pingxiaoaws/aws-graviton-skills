#!/bin/bash
# check-java-tuning.sh - Analyze running JVM instances for Graviton optimization
# Usage: ./check-java-tuning.sh

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Java/JVM Graviton Tuning Analyzer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

OPTIMAL=0
WARNINGS=0
ISSUES=0

optimal() { OPTIMAL=$((OPTIMAL + 1)); }
warn()    { WARNINGS=$((WARNINGS + 1)); }
issue()   { ISSUES=$((ISSUES + 1)); }

# ---- Check Java Installation ----
echo "[1/5] Java installation..."
if ! command -v java &> /dev/null; then
    echo -e "${RED}  Java not found in PATH${NC}"
    echo "  Recommendation: Install Amazon Corretto 17+"
    echo "    sudo yum install -y java-17-amazon-corretto"
    exit 1
fi

JAVA_VERSION=$(java -version 2>&1 | head -1)
JAVA_VENDOR=$(java -version 2>&1 | grep -i "runtime\|openjdk\|corretto" | head -1)
echo "  Version: $JAVA_VERSION"
echo "  Runtime: $JAVA_VENDOR"

# Check for Corretto
if echo "$JAVA_VENDOR" | grep -qi "corretto"; then
    echo -e "  ${GREEN}[OK]${NC} Amazon Corretto detected (recommended for Graviton)"
    optimal
elif echo "$JAVA_VENDOR" | grep -qi "openjdk"; then
    echo -e "  ${GREEN}[OK]${NC} OpenJDK detected"
    optimal
else
    echo -e "  ${YELLOW}[WARN]${NC} Consider using Amazon Corretto for best Graviton performance"
    warn
fi

# Check JDK version
JAVA_MAJOR=$(java -version 2>&1 | head -1 | awk -F'"' '{print $2}' | cut -d. -f1)
if [ "$JAVA_MAJOR" -ge 17 ]; then
    echo -e "  ${GREEN}[OK]${NC} JDK $JAVA_MAJOR (optimal for Graviton)"
    optimal
elif [ "$JAVA_MAJOR" -ge 11 ]; then
    echo -e "  ${YELLOW}[WARN]${NC} JDK $JAVA_MAJOR (consider upgrading to 17+ for best performance)"
    warn
elif [ "$JAVA_MAJOR" -eq 8 ] || [ "$JAVA_MAJOR" -eq 1 ]; then
    echo -e "  ${RED}[ISSUE]${NC} JDK 8 (suboptimal for Graviton, upgrade to 11+ recommended)"
    issue
fi
echo ""

# ---- Find Running JVMs ----
echo "[2/5] Running JVM processes..."

if command -v jps &> /dev/null; then
    JVM_PROCS=$(jps -v 2>/dev/null | grep -v "Jps" || true)
else
    JVM_PROCS=$(ps aux | grep "[j]ava" | awk '{print $2, $11, $12, $13, $14, $15}' || true)
fi

if [ -z "$JVM_PROCS" ]; then
    echo "  No running JVM processes found"
    echo "  Showing recommended flags for new JVM instances:"
else
    echo "  Found running JVM processes:"
    echo "$JVM_PROCS" | head -10 | while read line; do
        echo "    $line"
    done
    echo ""
fi
echo ""

# ---- Analyze JVM Flags ----
echo "[3/5] JVM flag analysis..."
echo ""

# Get all JVM flags from running processes
ALL_FLAGS=""
if [ -n "$JVM_PROCS" ]; then
    ALL_FLAGS=$(ps aux | grep "[j]ava" | tr ' ' '\n' | grep "^-X\|^-D\|^-server\|^-client" | sort -u || true)
fi

# Check TieredCompilation
echo "  -- Tiered Compilation --"
if echo "$ALL_FLAGS" | grep -q "TieredCompilation"; then
    if echo "$ALL_FLAGS" | grep -q "\-TieredCompilation"; then
        echo -e "  ${GREEN}[OK]${NC} -XX:-TieredCompilation (disabled, good for server workloads)"
        optimal
    else
        echo -e "  ${YELLOW}[WARN]${NC} TieredCompilation enabled (default)"
        echo "        For server workloads, consider: -XX:-TieredCompilation"
        echo "        Can improve throughput by up to 1.5x on Graviton"
        warn
    fi
else
    echo -e "  ${YELLOW}[INFO]${NC} TieredCompilation: default (enabled)"
    echo "        Recommendation: -XX:-TieredCompilation -XX:ReservedCodeCacheSize=64M -XX:InitialCodeCacheSize=64M"
    warn
fi

# Check THP
echo ""
echo "  -- Transparent Huge Pages --"
if echo "$ALL_FLAGS" | grep -q "UseTransparentHugePages"; then
    echo -e "  ${GREEN}[OK]${NC} -XX:+UseTransparentHugePages"
    optimal
elif echo "$ALL_FLAGS" | grep -q "UseLargePages"; then
    echo -e "  ${GREEN}[OK]${NC} -XX:+UseLargePages"
    optimal
else
    echo -e "  ${YELLOW}[WARN]${NC} No huge page flag detected"
    echo "        Recommendation: -XX:+UseTransparentHugePages"
    warn
fi

# Check thread stack size
echo ""
echo "  -- Thread Stack Size --"
if echo "$ALL_FLAGS" | grep -q "ThreadStackSize\|Xss"; then
    STACK_SIZE=$(echo "$ALL_FLAGS" | grep -oE "ThreadStackSize=[0-9]+" | head -1 || true)
    if [ -z "$STACK_SIZE" ]; then
        STACK_SIZE=$(echo "$ALL_FLAGS" | grep -oE "Xss[0-9]+[kmgKMG]?" | head -1 || true)
    fi
    echo "  Stack size: $STACK_SIZE"
else
    echo -e "  ${YELLOW}[WARN]${NC} Default stack size (2MB on aarch64, vs 1MB on x86)"
    echo "        For many-threaded apps: -XX:ThreadStackSize=1024"
    echo "        Or switch THP to madvise: echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled"
    warn
fi

# Check OmitStackTraceInFastThrow
echo ""
echo "  -- Exception Optimization --"
if echo "$ALL_FLAGS" | grep -q "OmitStackTraceInFastThrow"; then
    echo -e "  ${GREEN}[OK]${NC} OmitStackTraceInFastThrow configured"
    optimal
else
    echo -e "  ${YELLOW}[INFO]${NC} OmitStackTraceInFastThrow not explicitly set"
    echo "        Exception stack traces cost up to 2x more on Graviton vs x86"
    echo "        If using exceptions for control flow: -XX:+OmitStackTraceInFastThrow"
fi

echo ""

# ---- THP System Check ----
echo "[4/5] System-level THP check..."
if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
    THP_STATUS=$(cat /sys/kernel/mm/transparent_hugepage/enabled | sed 's/.*\[\([a-z]*\)\].*/\1/')
    if [ "$THP_STATUS" = "always" ]; then
        echo -e "  ${GREEN}[OK]${NC} System THP: always"
        optimal
    elif [ "$THP_STATUS" = "madvise" ]; then
        echo -e "  ${GREEN}[OK]${NC} System THP: madvise (fine-grained, good with -XX:+UseTransparentHugePages)"
        optimal
    else
        echo -e "  ${YELLOW}[WARN]${NC} System THP: $THP_STATUS"
        echo "        Recommendation: echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled"
        warn
    fi
else
    echo -e "  ${YELLOW}[WARN]${NC} THP not available"
    warn
fi
echo ""

# ---- Recommended Configuration ----
echo "[5/5] Recommended JVM configuration for Graviton..."
echo ""

if [ "$JAVA_MAJOR" -ge 17 ]; then
    echo "  For JDK 17+ on Graviton (server workloads):"
    echo ""
    echo "    java \\"
    echo "      -XX:-TieredCompilation \\"
    echo "      -XX:ReservedCodeCacheSize=64M \\"
    echo "      -XX:InitialCodeCacheSize=64M \\"
    echo "      -XX:CICompilerCount=2 \\"
    echo "      -XX:CompilationMode=high-only \\"
    echo "      -XX:+UseTransparentHugePages \\"
    echo "      -XX:+OmitStackTraceInFastThrow \\"
    echo "      -XX:ThreadStackSize=1024 \\"
    echo "      -jar app.jar"
elif [ "$JAVA_MAJOR" -ge 11 ]; then
    echo "  For JDK 11 on Graviton (server workloads):"
    echo ""
    echo "    java \\"
    echo "      -XX:-TieredCompilation \\"
    echo "      -XX:ReservedCodeCacheSize=64M \\"
    echo "      -XX:InitialCodeCacheSize=64M \\"
    echo "      -XX:+UseTransparentHugePages \\"
    echo "      -XX:+OmitStackTraceInFastThrow \\"
    echo "      -XX:ThreadStackSize=1024 \\"
    echo "      -jar app.jar"
else
    echo "  For JDK 8 on Graviton (upgrade recommended):"
    echo ""
    echo "    java \\"
    echo "      -XX:+UseTransparentHugePages \\"
    echo "      -XX:+UnlockDiagnosticVMOptions \\"
    echo "      -XX:+UseAESCTRIntrinsics \\"
    echo "      -jar app.jar"
fi

echo ""
echo "  For profiling/flamegraph support, add:"
echo "    -XX:+PreserveFramePointer"
echo "    -agentpath:/usr/lib64/libperf-jvmti.so"
echo ""

# ---- Summary ----
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Analysis Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}Optimal: $OPTIMAL${NC}"
echo -e "  ${YELLOW}Warnings: $WARNINGS${NC}"
echo -e "  ${RED}Issues:   $ISSUES${NC}"
echo ""

if [ $ISSUES -eq 0 ] && [ $WARNINGS -le 2 ]; then
    echo -e "${GREEN}  JVM is well-configured for Graviton.${NC}"
elif [ $ISSUES -eq 0 ]; then
    echo -e "${YELLOW}  JVM has optimization opportunities. Review recommendations above.${NC}"
else
    echo -e "${RED}  JVM configuration has issues. Address recommendations above.${NC}"
fi
echo ""
