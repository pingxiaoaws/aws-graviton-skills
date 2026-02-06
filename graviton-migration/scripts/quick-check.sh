#!/bin/bash
# quick-check.sh - Fast compatibility check for Graviton migration
# Usage: ./quick-check.sh [PROJECT_PATH]

set -e

PROJECT_PATH=${1:-.}
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Quick Graviton Compatibility Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Project: $PROJECT_PATH"
echo ""

cd "$PROJECT_PATH"

# Find Dockerfiles
echo "🔍 Finding Dockerfiles..."
DOCKERFILES=$(find . -name "Dockerfile*" -type f 2>/dev/null)

if [ -z "$DOCKERFILES" ]; then
    echo -e "${YELLOW}⚠️  No Dockerfiles found${NC}"
else
    echo -e "${GREEN}✅ Found $(echo "$DOCKERFILES" | wc -l) Dockerfile(s)${NC}"
    echo "$DOCKERFILES" | while read -r df; do
        echo "   - $df"
        
        # Check base image
        BASE=$(grep "^FROM" "$df" | head -1 | awk '{print $2}')
        if [ -n "$BASE" ]; then
            echo "     Base: $BASE"
            
            # Check if common official image
            if echo "$BASE" | grep -qE "^(python|node|golang|openjdk|ubuntu|debian|alpine|amazonlinux):"; then
                echo -e "     ${GREEN}✅ Official image (likely ARM64 compatible)${NC}"
            else
                echo -e "     ${YELLOW}⚠️  Verify ARM64 support${NC}"
            fi
        fi
    done
fi

echo ""

# Find Python requirements
echo "🐍 Checking Python dependencies..."
REQ_FILES=$(find . -name "requirements*.txt" -o -name "pyproject.toml" | grep -v venv | grep -v node_modules 2>/dev/null)

if [ -z "$REQ_FILES" ]; then
    echo -e "${YELLOW}⚠️  No Python requirements found${NC}"
else
    echo -e "${GREEN}✅ Found Python dependencies${NC}"
    
    # Extract and check common problematic packages
    ALL_PACKAGES=$(cat $REQ_FILES | grep -v "^#" | grep -v "^$" | cut -d'=' -f1 | cut -d'>' -f1 | cut -d'<' -f1 | cut -d'[' -f1 | sort -u)
    
    # Check for known issues
    ISSUES=0
    
    echo "$ALL_PACKAGES" | while read -r pkg; do
        case "$pkg" in
            numpy)
                echo -e "   ${GREEN}✅ numpy${NC} (ensure >= 2.0.0)"
                ;;
            pandas)
                echo -e "   ${GREEN}✅ pandas${NC} (ensure >= 2.0.0)"
                ;;
            torch|pytorch)
                echo -e "   ${YELLOW}⚠️  torch${NC} (use: pip install torch --index-url https://download.pytorch.org/whl/cpu)"
                ;;
            tensorflow)
                echo -e "   ${YELLOW}⚠️  tensorflow${NC} (ensure >= 2.9.0)"
                ;;
            pillow)
                echo -e "   ${GREEN}✅ pillow${NC} (ensure >= 8.3.0)"
                ;;
            "node-sass")
                echo -e "   ${RED}❌ node-sass${NC} (use dart-sass instead)"
                ;;
        esac
    done
fi

echo ""

# Find Node.js dependencies
echo "📦 Checking Node.js dependencies..."
PKG_JSON=$(find . -name "package.json" -type f | grep -v node_modules | head -1)

if [ -z "$PKG_JSON" ]; then
    echo -e "${YELLOW}⚠️  No package.json found${NC}"
else
    echo -e "${GREEN}✅ Found package.json${NC}"
    echo "   Most npm packages are ARM64 compatible ✅"
    
    # Check for problematic packages
    if grep -q "node-sass" "$PKG_JSON"; then
        echo -e "   ${RED}❌ node-sass found${NC} - use dart-sass instead"
    fi
fi

echo ""

# Check for Lambda
echo "⚡ Checking for Lambda functions..."
LAMBDA_FILES=$(find . -name "*.ts" -o -name "*.js" | xargs grep -l "Architecture\\.X86_64" 2>/dev/null || true)

if [ -n "$LAMBDA_FILES" ]; then
    echo -e "${YELLOW}⚠️  Found Lambda with X86_64 architecture${NC}"
    echo "$LAMBDA_FILES" | while read -r file; do
        echo "   - $file"
        echo "     Change: Architecture.X86_64 → Architecture.ARM_64"
    done
else
    echo -e "${GREEN}✅ No X86 Lambda found (or already ARM64)${NC}"
fi

echo ""

# Check for CDK/Terraform
echo "☁️  Checking infrastructure code..."
if find . -name "*.ts" -o -name "*.tf" | xargs grep -l "Fargate\|ECS" &>/dev/null; then
    echo -e "${GREEN}✅ Found ECS/Fargate code${NC}"
    echo "   Add runtimePlatform: { cpuArchitecture: ARM64 }"
else
    echo -e "${YELLOW}⚠️  No ECS/Fargate detected${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Quick Assessment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Calculate score
SCORE=0
if [ -n "$DOCKERFILES" ]; then
    ((SCORE++))
fi
if [ -n "$REQ_FILES" ] || [ -n "$PKG_JSON" ]; then
    ((SCORE++))
fi

if [ $SCORE -ge 2 ]; then
    echo -e "${GREEN}✅ Project looks ARM64-ready${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Test ARM64 build: ./scripts/test-arm64-build.sh -t test:arm64"
    echo "  2. Review: cat references/manual-analysis.md"
    echo "  3. Deploy to dev environment"
elif [ $SCORE -ge 1 ]; then
    echo -e "${YELLOW}⚠️  Some compatibility work needed${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Read: references/manual-analysis.md"
    echo "  2. Update dependency versions"
    echo "  3. Test ARM64 build"
else
    echo -e "${YELLOW}⚠️  Unable to assess (no Dockerfiles/dependencies found)${NC}"
    echo ""
    echo "This may not be a containerized project."
fi

echo ""
