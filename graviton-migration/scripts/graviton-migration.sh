#!/bin/bash
set -e

# AWS Graviton Migration Skill - Main Entry Point
# This script provides an interactive interface for Graviton migration tasks

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SKILL_DIR/scripts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print banner
print_banner() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        AWS Graviton Migration Assistant                   ║"
    echo "║        Migrate x86 workloads to ARM64 Graviton             ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Print usage
print_usage() {
    cat << EOF
Usage: $0 <command> [options]

Commands:
  scan <path>                    Run Porting Advisor on codebase
  analyze <report>               Analyze Porting Advisor report
  plan [options]                 Generate migration plan
  cost-compare [options]         Compare instance costs
  setup                          Install required tools
  help                           Show this help message

Examples:
  $0 scan /path/to/code
  $0 analyze porting-advisor-report.html
  $0 plan --instance-type m6g.xlarge
  $0 cost-compare --current m5.xlarge --target m6g.xlarge

For detailed documentation, see: $SKILL_DIR/skill.md
EOF
}

# Check prerequisites
check_prerequisites() {
    local missing=()

    if ! command -v docker &> /dev/null && ! command -v python3 &> /dev/null; then
        missing+=("docker or python3")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠ Missing prerequisites: ${missing[*]}${NC}"
        echo "Run: $0 setup"
        return 1
    fi
    return 0
}

# Setup/install required tools
cmd_setup() {
    echo -e "${BLUE}Setting up Graviton migration tools...${NC}"

    # Check Docker
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}✓ Docker found${NC}"
        echo "Pulling Porting Advisor image..."
        docker pull public.ecr.aws/graviton/porting-advisor:latest
    else
        echo -e "${YELLOW}⚠ Docker not found${NC}"

        # Try Python setup
        if command -v python3 &> /dev/null; then
            echo -e "${GREEN}✓ Python3 found, setting up Porting Advisor...${NC}"
            PA_DIR="$HOME/.local/share/porting-advisor"

            if [ ! -d "$PA_DIR" ]; then
                mkdir -p "$PA_DIR"
                cd "$PA_DIR"
                git clone https://github.com/aws/porting-advisor-for-graviton.git .
                python3 -m venv venv
                source venv/bin/activate
                pip3 install -r requirements.txt
            else
                echo -e "${GREEN}✓ Porting Advisor already installed${NC}"
            fi
        else
            echo -e "${RED}✗ Neither Docker nor Python3 found!${NC}"
            echo "Please install one of:"
            echo "  • Docker: https://docs.docker.com/get-docker/"
            echo "  • Python 3.10+: https://www.python.org/downloads/"
            exit 1
        fi
    fi

    echo -e "${GREEN}✓ Setup complete!${NC}"
}

# Run Porting Advisor scan
cmd_scan() {
    local target_path="${1:-.}"
    local output_file="${2:-porting-advisor-report.html}"

    if [ ! -d "$target_path" ] && [ ! -f "$target_path" ]; then
        echo -e "${RED}✗ Path not found: $target_path${NC}"
        exit 1
    fi

    echo -e "${BLUE}Running Porting Advisor scan on: $target_path${NC}"
    bash "$SCRIPTS_DIR/run-porting-advisor.sh" "$target_path" "$output_file"

    if [ -f "$output_file" ]; then
        echo ""
        echo -e "${GREEN}✓ Scan complete!${NC}"
        echo -e "Report: ${BLUE}$output_file${NC}"
        echo ""
        echo "Next step: $0 analyze $output_file"
    fi
}

# Analyze Porting Advisor report
cmd_analyze() {
    local report_file="$1"

    if [ -z "$report_file" ]; then
        echo -e "${RED}✗ Report file required${NC}"
        echo "Usage: $0 analyze <report-file>"
        exit 1
    fi

    if [ ! -f "$report_file" ]; then
        echo -e "${RED}✗ Report not found: $report_file${NC}"
        exit 1
    fi

    echo -e "${BLUE}Analyzing report: $report_file${NC}"
    python3 "$SCRIPTS_DIR/analyze-report.py" "$report_file"
}

# Generate migration plan
cmd_plan() {
    local instance_type="${INSTANCE_TYPE:-m6g.xlarge}"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --instance-type)
                instance_type="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    echo -e "${BLUE}Generating migration plan for: $instance_type${NC}"
    echo ""

    cat << 'PLAN'
╔════════════════════════════════════════════════════════════╗
║           AWS GRAVITON MIGRATION PLAN                      ║
╚════════════════════════════════════════════════════════════╝

STEP 1: LEARNING AND EXPLORING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
□ Task 1.1: Review Graviton documentation
  - AWS Graviton Getting Started: https://github.com/aws/aws-graviton-getting-started
  - Watch re:Invent deep dive sessions

□ Task 1.2: Inventory your software stack
  Run: graviton-migration scan /path/to/code

  Check:
  - Operating system version (prefer recent)
  - Container images (multi-arch support)
  - All libraries, frameworks, runtimes
  - Build tools (compilers, CI/CD)
  - Monitoring/security agents

STEP 2: PLAN YOUR WORKLOAD TRANSITION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
□ Task 2.1: Set up Graviton environment
  - Launch ARM64 AMI or create golden AMI
  - For containers: Add Graviton nodes to ECS/EKS cluster

□ Task 2.2: Build applications
  - Interpreted languages (Java, Python, Node.js): Run as-is
  - Compiled languages (C/C++, Go, Rust): Recompile for ARM64
  - Containers: Build multi-arch images

STEP 3: TEST AND OPTIMIZE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
□ Task 3.1: Run test suite
  - Execute all unit and functional tests
  - Resolve any architecture-specific issues

□ Task 3.2: Performance testing
  - Benchmark CPU, memory, I/O
  - Compare with x86 baseline
  - Optimize using compiler flags

STEP 4: INFRASTRUCTURE AND DEPLOYMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
□ Task 4.1: Update Infrastructure as Code
  - Update instance types in templates
  - Ensure AMI IDs are correct (ARM64)

□ Task 4.2: Deploy to production
  Strategy options:
  - Blue-Green: Parallel stack, switch traffic
  - Canary: Gradual traffic shift (5% → 25% → 50% → 100%)
  - In-place: Stop, change instance type, start

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NEXT COMMANDS:
  graviton-migration scan /path/to/code
  graviton-migration cost-compare --current m5.xlarge --target m6g.xlarge
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PLAN
}

# Cost comparison
cmd_cost_compare() {
    local current=""
    local target=""
    local count="1"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --current)
                current="$2"
                shift 2
                ;;
            --target)
                target="$2"
                shift 2
                ;;
            --count)
                count="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ -z "$current" ] || [ -z "$target" ]; then
        echo -e "${RED}✗ Missing required options${NC}"
        echo "Usage: $0 cost-compare --current <type> --target <type> [--count <num>]"
        echo "Example: $0 cost-compare --current m5.xlarge --target m6g.xlarge"
        exit 1
    fi

    echo -e "${BLUE}Calculating cost savings...${NC}"
    python3 "$SCRIPTS_DIR/cost-calculator.py" --current "$current" --target "$target" --count "$count"
}

# Main command dispatcher
main() {
    print_banner

    if [ $# -eq 0 ]; then
        print_usage
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
        scan)
            check_prerequisites || exit 1
            cmd_scan "$@"
            ;;
        analyze)
            cmd_analyze "$@"
            ;;
        plan)
            cmd_plan "$@"
            ;;
        cost-compare)
            cmd_cost_compare "$@"
            ;;
        setup)
            cmd_setup
            ;;
        help|--help|-h)
            print_usage
            ;;
        *)
            echo -e "${RED}✗ Unknown command: $command${NC}"
            echo ""
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
