#!/bin/bash
# tune-system.sh - Apply recommended kernel/OS tuning for Graviton performance
# Usage: ./tune-system.sh [--dry-run | --apply]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MODE="dry-run"

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Apply recommended system tuning for Graviton performance."
    echo ""
    echo "OPTIONS:"
    echo "    --dry-run     Show what would change without applying (default)"
    echo "    --apply       Apply all recommended changes"
    echo "    --network     Apply network tuning only"
    echo "    --memory      Apply memory tuning only"
    echo "    --limits      Apply file descriptor limits only"
    echo "    -h, --help    Show this help"
    echo ""
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)  MODE="dry-run"; shift ;;
        --apply)    MODE="apply"; shift ;;
        --network)  MODE="apply-network"; shift ;;
        --memory)   MODE="apply-memory"; shift ;;
        --limits)   MODE="apply-limits"; shift ;;
        -h|--help)  show_help; exit 0 ;;
        *)          echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Graviton System Tuning"
if [ "$MODE" = "dry-run" ]; then
    echo -e "  Mode: ${YELLOW}DRY-RUN (no changes will be made)${NC}"
else
    echo -e "  Mode: ${GREEN}APPLY${NC}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CHANGES=0

apply_sysctl() {
    local param=$1
    local value=$2
    local description=$3

    CURRENT=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
    if [ "$CURRENT" = "$value" ]; then
        echo -e "  ${GREEN}[OK]${NC} $param = $value ($description)"
        return
    fi

    CHANGES=$((CHANGES + 1))
    if [ "$MODE" = "dry-run" ]; then
        echo -e "  ${YELLOW}[CHANGE]${NC} $param: $CURRENT -> $value ($description)"
    else
        sudo sysctl -w "$param=$value" > /dev/null 2>&1
        echo -e "  ${GREEN}[APPLIED]${NC} $param = $value ($description)"
    fi
}

apply_thp() {
    local value=$1
    local description=$2

    if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
        CURRENT=$(cat /sys/kernel/mm/transparent_hugepage/enabled | sed 's/.*\[\([a-z]*\)\].*/\1/')
        if [ "$CURRENT" = "$value" ]; then
            echo -e "  ${GREEN}[OK]${NC} THP = $value ($description)"
            return
        fi

        CHANGES=$((CHANGES + 1))
        if [ "$MODE" = "dry-run" ]; then
            echo -e "  ${YELLOW}[CHANGE]${NC} THP: $CURRENT -> $value ($description)"
        else
            echo "$value" | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null
            echo -e "  ${GREEN}[APPLIED]${NC} THP = $value ($description)"
        fi
    else
        echo -e "  ${YELLOW}[SKIP]${NC} THP not available on this system"
    fi
}

# ---- Network Tuning ----
if [ "$MODE" = "dry-run" ] || [ "$MODE" = "apply" ] || [ "$MODE" = "apply-network" ]; then
    echo "[Network Tuning]"
    apply_sysctl "net.ipv4.ip_local_port_range" "1024 65535" "Expand ephemeral port range"
    apply_sysctl "net.ipv4.tcp_tw_reuse" "1" "Reuse TIME_WAIT sockets"
    apply_sysctl "net.core.somaxconn" "65535" "Max socket listen backlog"
    apply_sysctl "net.core.netdev_max_backlog" "5000" "Network device backlog"
    apply_sysctl "net.ipv4.tcp_max_syn_backlog" "65535" "Max SYN backlog"
    echo ""
fi

# ---- Memory Tuning ----
if [ "$MODE" = "dry-run" ] || [ "$MODE" = "apply" ] || [ "$MODE" = "apply-memory" ]; then
    echo "[Memory Tuning]"
    apply_thp "always" "Enable transparent huge pages"
    apply_sysctl "vm.swappiness" "10" "Reduce swap aggressiveness"
    apply_sysctl "vm.dirty_ratio" "40" "Max dirty memory before writes"
    apply_sysctl "vm.dirty_background_ratio" "10" "Background writeback threshold"
    echo ""
fi

# ---- File Descriptor Limits ----
if [ "$MODE" = "dry-run" ] || [ "$MODE" = "apply" ] || [ "$MODE" = "apply-limits" ]; then
    echo "[File Descriptor Limits]"
    apply_sysctl "fs.file-max" "2097152" "System-wide max open files"
    apply_sysctl "fs.nr_open" "2097152" "Per-process max open files"

    # Check limits.conf
    if [ -f /etc/security/limits.conf ]; then
        if grep -q "nofile" /etc/security/limits.conf; then
            echo -e "  ${GREEN}[OK]${NC} /etc/security/limits.conf has nofile entries"
        else
            CHANGES=$((CHANGES + 1))
            if [ "$MODE" = "dry-run" ]; then
                echo -e "  ${YELLOW}[CHANGE]${NC} /etc/security/limits.conf: add nofile entries"
                echo "        Will add: * soft nofile 65535"
                echo "        Will add: * hard nofile 65535"
            else
                echo "* soft nofile 65535" | sudo tee -a /etc/security/limits.conf > /dev/null
                echo "* hard nofile 65535" | sudo tee -a /etc/security/limits.conf > /dev/null
                echo -e "  ${GREEN}[APPLIED]${NC} Added nofile entries to /etc/security/limits.conf"
            fi
        fi
    fi
    echo ""
fi

# ---- Persistent Configuration ----
if [ "$MODE" = "apply" ]; then
    echo "[Persistent Configuration]"
    SYSCTL_FILE="/etc/sysctl.d/99-graviton-tuning.conf"
    if [ -f "$SYSCTL_FILE" ]; then
        echo -e "  ${GREEN}[OK]${NC} $SYSCTL_FILE already exists"
    else
        cat <<'SYSCTL_EOF' | sudo tee "$SYSCTL_FILE" > /dev/null
# Graviton Performance Tuning
# Generated by graviton-performance-tuning skill

# Network tuning
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 65535

# Memory tuning
vm.swappiness = 10
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10

# File descriptor limits
fs.file-max = 2097152
fs.nr_open = 2097152
SYSCTL_EOF
        echo -e "  ${GREEN}[APPLIED]${NC} Created $SYSCTL_FILE for persistence across reboots"
    fi
    echo ""
fi

# ---- Summary ----
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$MODE" = "dry-run" ]; then
    if [ $CHANGES -eq 0 ]; then
        echo -e "  ${GREEN}System is already optimally configured!${NC}"
    else
        echo -e "  ${YELLOW}$CHANGES change(s) would be applied.${NC}"
        echo ""
        echo "  To apply changes, run:"
        echo "    $0 --apply"
    fi
else
    if [ $CHANGES -eq 0 ]; then
        echo -e "  ${GREEN}System was already optimally configured!${NC}"
    else
        echo -e "  ${GREEN}$CHANGES change(s) applied successfully.${NC}"
    fi
fi
echo ""
