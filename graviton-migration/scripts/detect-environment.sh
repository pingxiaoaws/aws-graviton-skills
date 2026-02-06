#!/bin/bash
# detect-environment.sh - Detect current environment for Graviton migration
# Recommends best approach based on available tools and architecture

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Graviton Migration Environment Detection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Detect architecture
ARCH=$(uname -m)
echo -n "💻 Architecture: "
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    echo -e "${GREEN}$ARCH (ARM64/Graviton)${NC}"
    ON_GRAVITON=true
else
    echo -e "${YELLOW}$ARCH (x86_64)${NC}"
    ON_GRAVITON=false
fi

# Detect OS
OS=$(uname -s)
echo "🖥️  OS:           $OS"

# Check Docker
echo -n "🐋 Docker:       "
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
    echo -e "${GREEN}✅ Installed ($DOCKER_VERSION)${NC}"
    HAS_DOCKER=true
else
    echo -e "${RED}❌ Not found${NC}"
    HAS_DOCKER=false
fi

# Check Docker Buildx
if [ "$HAS_DOCKER" = true ]; then
    echo -n "🔨 Buildx:       "
    if docker buildx version &> /dev/null; then
        BUILDX_VERSION=$(docker buildx version | cut -d' ' -f2)
        echo -e "${GREEN}✅ Available ($BUILDX_VERSION)${NC}"
        HAS_BUILDX=true
        
        # Check builders
        BUILDERS=$(docker buildx ls | grep -v "^NAME" | wc -l)
        if [ "$BUILDERS" -gt 0 ]; then
            echo "   Builders: $BUILDERS configured"
        fi
    else
        echo -e "${YELLOW}⚠️  Not available${NC}"
        HAS_BUILDX=false
    fi
fi

# Check Python
echo -n "🐍 Python:       "
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d'.' -f1)
    PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d'.' -f2)
    
    if [ "$PYTHON_MAJOR" -ge 3 ] && [ "$PYTHON_MINOR" -ge 10 ]; then
        echo -e "${GREEN}✅ $PYTHON_VERSION (Porting Advisor compatible)${NC}"
        PYTHON_OK_FOR_PA=true
    else
        echo -e "${YELLOW}⚠️  $PYTHON_VERSION (Porting Advisor needs 3.10+)${NC}"
        PYTHON_OK_FOR_PA=false
    fi
else
    echo -e "${RED}❌ Not found${NC}"
    PYTHON_OK_FOR_PA=false
fi

# Check AWS CLI
echo -n "☁️  AWS CLI:     "
if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
    echo -e "${GREEN}✅ $AWS_VERSION${NC}"
    HAS_AWS_CLI=true
else
    echo -e "${YELLOW}⚠️  Not found${NC}"
    HAS_AWS_CLI=false
fi

# Check Git
echo -n "📦 Git:          "
if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version | cut -d' ' -f3)
    echo -e "${GREEN}✅ $GIT_VERSION${NC}"
    HAS_GIT=true
else
    echo -e "${YELLOW}⚠️  Not found${NC}"
    HAS_GIT=false
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Analysis & Recommendations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Recommendation logic
if [ "$ON_GRAVITON" = true ] && [ "$HAS_DOCKER" = true ]; then
    echo -e "${GREEN}✅ OPTIMAL SETUP${NC}"
    echo ""
    echo "You're on Graviton with Docker!"
    echo ""
    echo "✨ Benefits:"
    echo "  • Native ARM64 builds (FAST)"
    echo "  • No emulation overhead"
    echo "  • Best environment for migration"
    echo ""
    echo "📝 Recommended approach:"
    echo "  1. Use regular docker build (no buildx needed)"
    echo "     $ docker build --platform linux/arm64 -t myapp:arm64 ."
    echo ""
    echo "  2. Test locally immediately"
    echo "     $ docker run --platform linux/arm64 myapp:arm64"
    echo ""
    echo "  3. Push to registry"
    echo "     $ docker push myapp:arm64"
    echo ""

elif [ "$ON_GRAVITON" = false ] && [ "$HAS_DOCKER" = true ] && [ "$HAS_BUILDX" = true ]; then
    echo -e "${YELLOW}⚠️  CROSS-BUILD SETUP${NC}"
    echo ""
    echo "You're on x86_64 with Docker + Buildx"
    echo ""
    echo "⚠️  Limitations:"
    echo "  • ARM64 builds use QEMU emulation (SLOW)"
    echo "  • Builds will take 5-10x longer"
    echo "  • Some packages may fail in emulation"
    echo ""
    echo "📝 Recommended approaches:"
    echo ""
    echo "  Option A: Use buildx (slower)"
    echo "    $ docker buildx build --platform linux/arm64 --load -t myapp:arm64 ."
    echo ""
    echo "  Option B: Use Graviton instance (faster) ⭐ RECOMMENDED"
    echo "    1. Launch c7g.xlarge EC2 instance"
    echo "    2. Install Docker"
    echo "    3. Build natively (5-10x faster)"
    echo ""
    echo "  Option C: Use AWS CodeBuild with ARM_CONTAINER"
    echo "    buildspec.yml:"
    echo "      phases:"
    echo "        build:"
    echo "          commands:"
    echo "            - docker build -t myapp:arm64 ."
    echo "      compute-type: ARM_CONTAINER"
    echo ""

elif [ "$HAS_DOCKER" = false ]; then
    echo -e "${RED}❌ DOCKER REQUIRED${NC}"
    echo ""
    echo "Docker is required for building ARM64 images."
    echo ""
    echo "📝 Installation:"
    echo ""
    echo "  Ubuntu/Debian:"
    echo "    $ curl -fsSL https://get.docker.com | sh"
    echo "    $ sudo usermod -aG docker \$USER"
    echo ""
    echo "  Amazon Linux 2023:"
    echo "    $ sudo yum install -y docker"
    echo "    $ sudo systemctl start docker"
    echo "    $ sudo usermod -aG docker ec2-user"
    echo ""
    echo "  macOS:"
    echo "    Download Docker Desktop from docker.com"
    echo ""

else
    echo -e "${YELLOW}⚠️  LIMITED SETUP${NC}"
    echo ""
    echo "Some tools are missing. Consider installing:"
    if [ "$HAS_BUILDX" = false ]; then
        echo "  • Docker Buildx (for cross-platform builds)"
    fi
    if [ "$PYTHON_OK_FOR_PA" = false ]; then
        echo "  • Python 3.10+ (for Porting Advisor)"
    fi
    echo ""
fi

# Porting Advisor recommendation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔬 Porting Advisor Availability"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$PYTHON_OK_FOR_PA" = true ] && [ "$HAS_GIT" = true ]; then
    echo -e "${GREEN}✅ Can use Porting Advisor${NC}"
    echo ""
    echo "Install and run:"
    echo "  $ git clone https://github.com/aws/porting-advisor-for-graviton"
    echo "  $ cd porting-advisor-for-graviton"
    echo "  $ python3 src/porting-advisor.py /path/to/your/code"
    echo ""
elif [ "$HAS_DOCKER" = true ]; then
    echo -e "${YELLOW}⚠️  Python < 3.10, but can use Docker version${NC}"
    echo ""
    echo "Run via Docker:"
    echo "  $ docker run --rm -v \$(pwd):/src \\"
    echo "      public.ecr.aws/aws-graviton-guide/porting-advisor \\"
    echo "      /src --output report.html"
    echo ""
    echo "(Note: Docker image may not exist, verify first)"
    echo ""
else
    echo -e "${RED}❌ Porting Advisor not available${NC}"
    echo ""
    echo "Alternative: Use manual analysis"
    echo "  $ cat references/manual-analysis.md"
    echo ""
fi

# Build-first recommendation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 Quick Start Recommendation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$HAS_DOCKER" = true ]; then
    echo "🚀 Build-First Approach (Fastest validation):"
    echo ""
    echo "Instead of running static analysis first, just try building:"
    echo ""
    if [ "$ON_GRAVITON" = true ]; then
        echo "  $ docker build --platform linux/arm64 -t test:arm64 ."
    else
        echo "  $ docker buildx build --platform linux/arm64 --load -t test:arm64 ."
    fi
    echo ""
    echo "If it builds → 90% done!"
    echo "If it fails → Error message tells you exactly what to fix"
    echo ""
    echo "Use our test script for automated validation:"
    echo "  $ ./scripts/test-arm64-build.sh -t myapp:arm64"
    echo ""
fi

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$ON_GRAVITON" = true ]; then
    echo -e "Environment Score: ${GREEN}⭐⭐⭐⭐⭐ (Excellent)${NC}"
    echo "Status: Ready for native ARM64 development"
elif [ "$HAS_DOCKER" = true ] && [ "$HAS_BUILDX" = true ]; then
    echo -e "Environment Score: ${YELLOW}⭐⭐⭐ (Good)${NC}"
    echo "Status: Can cross-build, but consider Graviton instance for speed"
elif [ "$HAS_DOCKER" = true ]; then
    echo -e "Environment Score: ${YELLOW}⭐⭐ (Fair)${NC}"
    echo "Status: Install buildx or use Graviton instance"
else
    echo -e "Environment Score: ${RED}⭐ (Needs Setup)${NC}"
    echo "Status: Install Docker first"
fi

echo ""
echo "Next steps:"
if [ "$HAS_DOCKER" = true ]; then
    echo "  1. Test ARM64 build: ./scripts/test-arm64-build.sh -t test:arm64"
    echo "  2. Read manual analysis: cat references/manual-analysis.md"
    echo "  3. Generate migration plan: ./scripts/generate-plan.sh"
else
    echo "  1. Install Docker"
    echo "  2. Re-run this script"
fi
echo ""
