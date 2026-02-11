#!/bin/bash
# profile-workload.sh - Performance profiling wrapper for Graviton workloads
# Usage: ./profile-workload.sh --pid <PID> --duration 30
#        ./profile-workload.sh --command "./my-app" --duration 60

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PID=""
COMMAND=""
DURATION=30
OUTPUT_DIR="./perf-results"
MODE="oncpu"

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Profile workloads on Graviton instances."
    echo ""
    echo "OPTIONS:"
    echo "    --pid PID            Process ID to profile"
    echo "    --command CMD        Command to run and profile"
    echo "    --duration SECS      Profiling duration in seconds (default: 30)"
    echo "    --output DIR         Output directory (default: ./perf-results)"
    echo "    --mode MODE          Profiling mode: oncpu, offcpu, pmu (default: oncpu)"
    echo "    -h, --help           Show this help"
    echo ""
    echo "MODES:"
    echo "    oncpu    On-CPU profiling (where is CPU time spent)"
    echo "    offcpu   Off-CPU profiling (where are threads blocked)"
    echo "    pmu      PMU counter analysis (cache misses, branch misses, IPC)"
    echo ""
    echo "EXAMPLES:"
    echo "    $0 --pid 1234 --duration 30"
    echo "    $0 --command './my-app --serve' --duration 60"
    echo "    $0 --pid 1234 --mode pmu --duration 10"
    echo ""
}

while [ $# -gt 0 ]; do
    case "$1" in
        --pid)      PID="$2"; shift 2 ;;
        --command)  COMMAND="$2"; shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        --output)   OUTPUT_DIR="$2"; shift 2 ;;
        --mode)     MODE="$2"; shift 2 ;;
        -h|--help)  show_help; exit 0 ;;
        *)          echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "$PID" ] && [ -z "$COMMAND" ]; then
    echo "Error: Specify --pid or --command"
    echo ""
    show_help
    exit 1
fi

# Check dependencies
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Graviton Workload Profiler"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "[1/4] Checking dependencies..."

HAS_PERF=false
HAS_FLAMEGRAPH=false

if command -v perf &> /dev/null; then
    echo -e "  ${GREEN}[OK]${NC} perf: $(perf version 2>&1 | head -1)"
    HAS_PERF=true
else
    echo -e "  ${RED}[MISSING]${NC} perf"
    echo "    Install: sudo yum install -y perf  # AL2/AL2023"
    echo "    Install: sudo apt install -y linux-tools-common linux-tools-$(uname -r)  # Ubuntu"
fi

if command -v flamegraph.pl &> /dev/null || [ -f /usr/local/bin/flamegraph.pl ]; then
    echo -e "  ${GREEN}[OK]${NC} flamegraph.pl"
    HAS_FLAMEGRAPH=true
elif command -v stackcollapse-perf.pl &> /dev/null; then
    echo -e "  ${GREEN}[OK]${NC} FlameGraph tools"
    HAS_FLAMEGRAPH=true
else
    echo -e "  ${YELLOW}[WARN]${NC} FlameGraph tools not found"
    echo "    Install: git clone https://github.com/brendangregg/FlameGraph"
    echo "    Then: export PATH=\$PATH:/path/to/FlameGraph"
fi

if command -v aperf &> /dev/null; then
    echo -e "  ${GREEN}[OK]${NC} AWS APerf: $(aperf --version 2>&1 | head -1)"
else
    echo "  AWS APerf: not installed (optional)"
    echo "    Install: https://github.com/aws/aperf"
fi

echo ""

if [ "$HAS_PERF" = false ]; then
    echo -e "${RED}Error: perf is required for profiling.${NC}"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "[2/4] Configuration..."
echo "  Mode:     $MODE"
echo "  Duration: ${DURATION}s"
echo "  Output:   $OUTPUT_DIR/"
if [ -n "$PID" ]; then
    echo "  Target:   PID $PID"
    # Verify PID exists
    if ! kill -0 "$PID" 2>/dev/null; then
        echo -e "${RED}Error: PID $PID not found${NC}"
        exit 1
    fi
    PROC_NAME=$(cat /proc/$PID/comm 2>/dev/null || echo "unknown")
    echo "  Process:  $PROC_NAME"
fi
if [ -n "$COMMAND" ]; then
    echo "  Command:  $COMMAND"
fi
echo ""

# ---- On-CPU Profiling ----
if [ "$MODE" = "oncpu" ]; then
    echo "[3/4] Recording on-CPU profile (${DURATION}s)..."

    PERF_DATA="$OUTPUT_DIR/perf_oncpu_$TIMESTAMP.data"
    FLAMEGRAPH_SVG="$OUTPUT_DIR/flamegraph_oncpu_$TIMESTAMP.svg"

    if [ -n "$PID" ]; then
        sudo perf record -F 99 -p "$PID" -g -o "$PERF_DATA" -- sleep "$DURATION"
    else
        sudo perf record -F 99 -g -o "$PERF_DATA" -- $COMMAND &
        PERF_PID=$!
        sleep "$DURATION"
        sudo kill -INT "$PERF_PID" 2>/dev/null || true
        wait "$PERF_PID" 2>/dev/null || true
    fi

    echo ""
    echo "[4/4] Generating reports..."

    # Text report
    REPORT_FILE="$OUTPUT_DIR/perf_report_$TIMESTAMP.txt"
    sudo perf report -i "$PERF_DATA" --stdio --no-children > "$REPORT_FILE" 2>/dev/null || true
    echo -e "  ${GREEN}[OK]${NC} Text report: $REPORT_FILE"

    # Flamegraph
    if [ "$HAS_FLAMEGRAPH" = true ]; then
        sudo perf script -i "$PERF_DATA" 2>/dev/null | stackcollapse-perf.pl 2>/dev/null | flamegraph.pl > "$FLAMEGRAPH_SVG" 2>/dev/null || true
        if [ -s "$FLAMEGRAPH_SVG" ]; then
            echo -e "  ${GREEN}[OK]${NC} Flamegraph: $FLAMEGRAPH_SVG"
        else
            echo -e "  ${YELLOW}[WARN]${NC} Flamegraph generation failed"
        fi
    fi

    # Show top functions
    echo ""
    echo "  Top CPU consumers:"
    sudo perf report -i "$PERF_DATA" --stdio --no-children 2>/dev/null | grep -E "^[[:space:]]*[0-9]" | head -15 || true

# ---- Off-CPU Profiling ----
elif [ "$MODE" = "offcpu" ]; then
    echo "[3/4] Recording off-CPU profile (${DURATION}s)..."
    echo "  Looking for: lock contention, I/O waits, scheduler delays"
    echo ""

    PERF_DATA="$OUTPUT_DIR/perf_offcpu_$TIMESTAMP.data"

    if [ -n "$PID" ]; then
        sudo perf record -e sched:sched_switch -p "$PID" -g -o "$PERF_DATA" -- sleep "$DURATION" 2>/dev/null || {
            echo -e "  ${YELLOW}[WARN]${NC} sched:sched_switch not available, using software events"
            sudo perf record -e cpu-clock -p "$PID" -g -o "$PERF_DATA" -- sleep "$DURATION"
        }
    else
        sudo perf record -e sched:sched_switch -ag -o "$PERF_DATA" -- sleep "$DURATION" 2>/dev/null || {
            echo -e "  ${YELLOW}[WARN]${NC} sched:sched_switch not available, using software events"
            sudo perf record -e cpu-clock -ag -o "$PERF_DATA" -- sleep "$DURATION"
        }
    fi

    echo ""
    echo "[4/4] Analyzing off-CPU events..."

    REPORT_FILE="$OUTPUT_DIR/perf_offcpu_report_$TIMESTAMP.txt"
    sudo perf report -i "$PERF_DATA" --stdio --no-children > "$REPORT_FILE" 2>/dev/null || true
    echo -e "  ${GREEN}[OK]${NC} Report: $REPORT_FILE"

    echo ""
    echo "  Key patterns to look for:"
    echo "    - lock/mutex/futex   -> Lock contention (consider LSE atomics)"
    echo "    - read/write/epoll   -> I/O wait"
    echo "    - work_pending       -> Involuntary switch (ignore)"
    echo ""

    # Show top off-CPU functions
    echo "  Top off-CPU functions:"
    sudo perf report -i "$PERF_DATA" --stdio --no-children 2>/dev/null | grep -E "^[[:space:]]*[0-9]" | head -10 || true

# ---- PMU Counter Analysis ----
elif [ "$MODE" = "pmu" ]; then
    echo "[3/4] Running PMU counter analysis (${DURATION}s)..."
    echo "  Note: Full PMU access may require large instances (e.g., c7g.16xlarge)"
    echo ""

    PMU_FILE="$OUTPUT_DIR/pmu_counters_$TIMESTAMP.txt"

    {
        echo "=== PMU Counter Analysis ==="
        echo "Date: $(date)"
        echo "Duration: ${DURATION}s"
        echo ""

        if [ -n "$PID" ]; then
            TARGET="-p $PID"
        else
            TARGET="-a"
        fi

        echo "--- Basic Counters ---"
        sudo perf stat -e cycles,instructions,cache-references,cache-misses,branch-instructions,branch-misses $TARGET -- sleep "$DURATION" 2>&1 || true

        echo ""
        echo "--- L1 Cache ---"
        sudo perf stat -e L1-dcache-loads,L1-dcache-load-misses,L1-icache-load-misses $TARGET -- sleep "$DURATION" 2>&1 || true

        echo ""
        echo "--- TLB ---"
        sudo perf stat -e dTLB-loads,dTLB-load-misses,iTLB-loads,iTLB-load-misses $TARGET -- sleep "$DURATION" 2>&1 || true

    } > "$PMU_FILE" 2>&1

    echo ""
    echo "[4/4] PMU analysis complete"
    echo -e "  ${GREEN}[OK]${NC} Report: $PMU_FILE"
    echo ""

    # Display key results
    echo "  Key metrics:"
    cat "$PMU_FILE" | grep -E "instructions|cycles|cache-misses|branch-misses" | head -10

    echo ""
    echo "  Interpretation guide:"
    echo "    IPC > 2.0         -> Good performance"
    echo "    IPC < 1.0         -> Likely memory-bound or branch-heavy"
    echo "    branch-mpki > 10  -> Branch prediction issues"
    echo "    L1-dcache-mpki > 20 -> Data cache pressure"
    echo "    L1-icache-mpki > 20 -> Instruction cache pressure (try -flto, -Os)"

else
    echo -e "${RED}Error: Unknown mode '$MODE'. Use: oncpu, offcpu, pmu${NC}"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Profiling Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Output directory: $OUTPUT_DIR/"
echo ""
echo "  Next steps:"
echo "    - Review the report for hot functions"
echo "    - Check for lock contention (LSE atomics?)"
echo "    - Look for cache misses (data layout?)"
echo "    - Verify compiler flags: ./scripts/check-binary-optimization.sh"
echo ""
