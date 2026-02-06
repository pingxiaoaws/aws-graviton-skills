#!/bin/bash
# test-arm64-build.sh - Build and validate ARM64 Docker images
# Usage: ./test-arm64-build.sh [OPTIONS]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DOCKERFILE="Dockerfile"
IMAGE_NAME=""
CONTEXT="."
TEST_IMPORTS=""
VERBOSE=false
QUICK_TEST=false

# Help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Build and validate ARM64 Docker images for Graviton migration.

OPTIONS:
    -f, --dockerfile PATH       Dockerfile path (default: Dockerfile)
    -t, --tag NAME              Image name/tag (required)
    -c, --context PATH          Build context (default: .)
    --test-import MODULES       Python modules to test importing (comma-separated)
    --quick                     Skip detailed validation
    -v, --verbose               Verbose output
    -h, --help                  Show this help

EXAMPLES:
    # Basic build
    $0 -t myapp:arm64-test

    # With custom Dockerfile
    $0 -f docker/Dockerfile.prod -t myapp:arm64

    # Test Python imports
    $0 -t processor:arm64 --test-import "torch,transformers,docling"

    # Quick test (just build + arch check)
    $0 -t api:arm64 --quick

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--dockerfile)
            DOCKERFILE="$2"
            shift 2
            ;;
        -t|--tag)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -c|--context)
            CONTEXT="$2"
            shift 2
            ;;
        --test-import)
            TEST_IMPORTS="$2"
            shift 2
            ;;
        --quick)
            QUICK_TEST=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required params
if [ -z "$IMAGE_NAME" ]; then
    echo -e "${RED}Error: Image name required (-t)${NC}"
    show_help
    exit 1
fi

if [ ! -f "$DOCKERFILE" ]; then
    echo -e "${RED}Error: Dockerfile not found: $DOCKERFILE${NC}"
    exit 1
fi

# Detect environment
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    echo -e "${GREEN}✅ Running on ARM64 (native build)${NC}"
    BUILD_CMD="docker build"
    PLATFORM_ARG=""
else
    echo -e "${YELLOW}⚠️  Running on x86_64 (cross-build with emulation)${NC}"
    echo -e "${YELLOW}   This will be slower. Consider using Graviton instance.${NC}"
    BUILD_CMD="docker buildx build"
    PLATFORM_ARG="--platform linux/arm64 --load"
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/arm64-build-${TIMESTAMP}.log"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏗️  ARM64 Build Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Dockerfile: $DOCKERFILE"
echo "Image:      $IMAGE_NAME"
echo "Context:    $CONTEXT"
echo "Log:        $LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Build
echo "📦 Step 1/5: Building ARM64 image..."
START_TIME=$(date +%s)

if [ "$VERBOSE" = true ]; then
    $BUILD_CMD $PLATFORM_ARG \
        -f "$DOCKERFILE" \
        -t "$IMAGE_NAME" \
        "$CONTEXT" 2>&1 | tee "$LOG_FILE"
else
    $BUILD_CMD $PLATFORM_ARG \
        -f "$DOCKERFILE" \
        -t "$IMAGE_NAME" \
        "$CONTEXT" > "$LOG_FILE" 2>&1
fi

if [ $? -eq 0 ]; then
    END_TIME=$(date +%s)
    BUILD_TIME=$((END_TIME - START_TIME))
    echo -e "${GREEN}✅ Build succeeded (${BUILD_TIME}s)${NC}"
else
    echo -e "${RED}❌ Build failed${NC}"
    echo ""
    echo "Last 20 lines of build log:"
    tail -20 "$LOG_FILE"
    echo ""
    echo "Full log: $LOG_FILE"
    exit 1
fi

# Step 2: Validate architecture
echo ""
echo "🔍 Step 2/5: Validating architecture..."
DETECTED_ARCH=$(docker run --rm --platform linux/arm64 "$IMAGE_NAME" uname -m 2>/dev/null || echo "failed")

if [ "$DETECTED_ARCH" = "aarch64" ]; then
    echo -e "${GREEN}✅ Architecture verified: aarch64 (ARM64)${NC}"
elif [ "$DETECTED_ARCH" = "arm64" ]; then
    echo -e "${GREEN}✅ Architecture verified: arm64 (ARM64)${NC}"
else
    echo -e "${RED}❌ Architecture mismatch: $DETECTED_ARCH${NC}"
    echo -e "${RED}   Expected: aarch64 or arm64${NC}"
    exit 1
fi

if [ "$QUICK_TEST" = true ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}✅ Quick test PASSED${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Image ready: $IMAGE_NAME"
    echo "Build time:  ${BUILD_TIME}s"
    echo "Log file:    $LOG_FILE"
    echo ""
    exit 0
fi

# Step 3: Check runtime
echo ""
echo "🧪 Step 3/5: Testing runtime..."

# Detect runtime
RUNTIME=$(docker run --rm --platform linux/arm64 "$IMAGE_NAME" sh -c "which python python3 node java go 2>/dev/null | head -1" || echo "")

if [ -n "$RUNTIME" ]; then
    RUNTIME_NAME=$(basename "$RUNTIME")
    echo -e "${GREEN}✅ Runtime detected: $RUNTIME_NAME${NC}"
    
    # Get version
    case "$RUNTIME_NAME" in
        python|python3)
            VERSION=$(docker run --rm --platform linux/arm64 "$IMAGE_NAME" python --version 2>&1)
            echo "   $VERSION"
            ;;
        node)
            VERSION=$(docker run --rm --platform linux/arm64 "$IMAGE_NAME" node --version 2>&1)
            echo "   Node.js $VERSION"
            ;;
        java)
            VERSION=$(docker run --rm --platform linux/arm64 "$IMAGE_NAME" java -version 2>&1 | head -1)
            echo "   $VERSION"
            ;;
        go)
            VERSION=$(docker run --rm --platform linux/arm64 "$IMAGE_NAME" go version 2>&1)
            echo "   $VERSION"
            ;;
    esac
else
    echo -e "${YELLOW}⚠️  No runtime detected (static binary?)${NC}"
fi

# Step 4: Test imports (if specified)
if [ -n "$TEST_IMPORTS" ]; then
    echo ""
    echo "📚 Step 4/5: Testing package imports..."
    
    IFS=',' read -ra MODULES <<< "$TEST_IMPORTS"
    FAILED_IMPORTS=()
    
    for MODULE in "${MODULES[@]}"; do
        MODULE=$(echo "$MODULE" | xargs) # Trim whitespace
        
        if docker run --rm --platform linux/arm64 "$IMAGE_NAME" python -c "import $MODULE" 2>/dev/null; then
            echo -e "   ${GREEN}✅ $MODULE${NC}"
        else
            echo -e "   ${RED}❌ $MODULE${NC}"
            FAILED_IMPORTS+=("$MODULE")
        fi
    done
    
    if [ ${#FAILED_IMPORTS[@]} -gt 0 ]; then
        echo ""
        echo -e "${RED}❌ Failed imports: ${FAILED_IMPORTS[*]}${NC}"
        exit 1
    fi
else
    echo ""
    echo "📚 Step 4/5: Skipped (no imports specified)"
fi

# Step 5: Basic functionality test
echo ""
echo "🚀 Step 5/5: Basic functionality test..."

# Try to start container (short-lived test)
if timeout 5 docker run --rm --platform linux/arm64 "$IMAGE_NAME" sh -c "echo 'Container start OK'" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Container starts successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Could not verify container startup (may be normal for some images)${NC}"
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ ARM64 Build Test PASSED${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📦 Image:      $IMAGE_NAME"
echo "🏗️  Built in:   ${BUILD_TIME}s"
echo "💻 Arch:       aarch64 (ARM64)"
if [ -n "$RUNTIME" ]; then
    echo "🔧 Runtime:    $RUNTIME_NAME"
fi
echo "📝 Log:        $LOG_FILE"
echo ""
echo "🚀 Next steps:"
echo "   1. Test with real workload:"
echo "      docker run --rm --platform linux/arm64 $IMAGE_NAME ..."
echo ""
echo "   2. Push to registry:"
echo "      docker push $IMAGE_NAME"
echo ""
echo "   3. Deploy to dev environment"
echo ""
