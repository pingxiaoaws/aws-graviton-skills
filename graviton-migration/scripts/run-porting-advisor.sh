#!/bin/bash
set -e

# AWS Graviton Porting Advisor Runner
# This script runs the Porting Advisor tool on a given codebase

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PATH="${1:-.}"
OUTPUT_FILE="${2:-porting-advisor-report.html}"
OUTPUT_FORMAT="${3:-html}"

echo "=== AWS Graviton Porting Advisor Runner ==="
echo "Repository: $REPO_PATH"
echo "Output: $OUTPUT_FILE"
echo "Format: $OUTPUT_FORMAT"
echo ""

# Check if Docker is available
if command -v docker &> /dev/null; then
    echo "✓ Docker found, using container mode"

    # Pull latest Porting Advisor image
    echo "Pulling latest Porting Advisor image..."
    docker pull public.ecr.aws/graviton/porting-advisor:latest

    # Run Porting Advisor in container
    echo "Running compatibility scan..."
    if [ "$OUTPUT_FORMAT" == "html" ]; then
        docker run --rm \
            -v "$(realpath "$REPO_PATH"):/repo" \
            -v "$(pwd):/output" \
            public.ecr.aws/graviton/porting-advisor:latest \
            /repo --output "/output/$OUTPUT_FILE"
    else
        docker run --rm \
            -v "$(realpath "$REPO_PATH"):/repo" \
            public.ecr.aws/graviton/porting-advisor:latest \
            /repo --output-format "$OUTPUT_FORMAT"
    fi

    echo ""
    echo "✓ Scan complete!"
    [ -f "$OUTPUT_FILE" ] && echo "Report saved to: $OUTPUT_FILE"

elif command -v python3 &> /dev/null; then
    echo "✓ Python3 found, using script mode"

    # Check if Porting Advisor is installed
    PA_DIR="$HOME/.local/share/porting-advisor"
    if [ ! -d "$PA_DIR" ]; then
        echo "Installing Porting Advisor..."
        mkdir -p "$PA_DIR"
        cd "$PA_DIR"

        # Clone repository
        git clone https://github.com/aws/porting-advisor-for-graviton.git .

        # Install dependencies
        python3 -m venv venv
        source venv/bin/activate
        pip3 install -r requirements.txt
    fi

    # Run Porting Advisor
    echo "Running compatibility scan..."
    cd "$PA_DIR"
    source venv/bin/activate

    if [ "$OUTPUT_FORMAT" == "html" ]; then
        python3 src/porting-advisor.py "$REPO_PATH" --output "$OUTPUT_FILE"
    else
        python3 src/porting-advisor.py "$REPO_PATH" --output-format "$OUTPUT_FORMAT"
    fi

    echo ""
    echo "✓ Scan complete!"
    [ -f "$OUTPUT_FILE" ] && echo "Report saved to: $OUTPUT_FILE"

else
    echo "✗ Neither Docker nor Python3 found!"
    echo ""
    echo "Please install one of the following:"
    echo "  • Docker: https://docs.docker.com/get-docker/"
    echo "  • Python 3.10+: https://www.python.org/downloads/"
    exit 1
fi

echo ""
echo "Next steps:"
echo "  1. Review the report: $OUTPUT_FILE"
echo "  2. Use: /graviton-migration analyze $OUTPUT_FILE"
echo "  3. Generate migration plan"
