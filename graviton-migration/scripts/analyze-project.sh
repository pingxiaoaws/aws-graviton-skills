#!/bin/bash
# analyze-project.sh - Wrapper for Porting Advisor analysis
# This is the PREFERRED method for Graviton migration

set -e

PROJECT_PATH=${1:-.}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔬 AWS Porting Advisor for Graviton"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "This is the RECOMMENDED approach for Graviton migration"
echo ""

# Check if Python 3.10+ available
PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2 | cut -d'.' -f1,2)
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d'.' -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d'.' -f2)

if [ "$PYTHON_MAJOR" -ge 3 ] && [ "$PYTHON_MINOR" -ge 10 ]; then
    echo "✅ Python $PYTHON_VERSION detected (compatible)"
    echo ""
    
    # Check if porting-advisor-for-graviton is installed
    if command -v porting-advisor &> /dev/null; then
        echo "✅ Porting Advisor CLI found"
        echo ""
        echo "Running analysis on: $PROJECT_PATH"
        porting-advisor "$PROJECT_PATH" --output report.html
        echo ""
        echo "✅ Analysis complete! Open report.html to view results."
    elif [ -d "$HOME/porting-advisor-for-graviton" ]; then
        echo "✅ Porting Advisor source found"
        echo ""
        echo "Running analysis on: $PROJECT_PATH"
        python3 "$HOME/porting-advisor-for-graviton/src/porting-advisor.py" "$PROJECT_PATH"
    else
        echo "⚠️  Porting Advisor not installed"
        echo ""
        echo "Install it:"
        echo "  git clone https://github.com/aws/porting-advisor-for-graviton.git"
        echo "  cd porting-advisor-for-graviton"
        echo "  python3 src/porting-advisor.py /path/to/your/project"
        echo ""
        echo "Or use the original script:"
        echo "  ./scripts/graviton-migration.sh"
        exit 1
    fi
else
    echo "⚠️  Python $PYTHON_VERSION detected (Porting Advisor needs 3.10+)"
    echo ""
    echo "Options:"
    echo ""
    echo "Option 1: Use Docker version (if Docker available)"
    echo "  docker run --rm -v \$(pwd):/src \\"
    echo "    public.ecr.aws/aws-graviton-guide/porting-advisor \\"
    echo "    /src --output report.html"
    echo ""
    echo "Option 2: Upgrade Python to 3.10+"
    echo "  (varies by OS)"
    echo ""
    echo "Option 3: Use manual analysis (no tools needed)"
    echo "  ./scripts/quick-check.sh $PROJECT_PATH"
    echo "  cat references/manual-analysis.md"
    echo ""
    echo "Option 4: Use build-first approach"
    echo "  ./scripts/test-arm64-build.sh -t myapp:arm64"
    echo ""
    exit 1
fi
