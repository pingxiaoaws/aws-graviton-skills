# Manual Graviton Compatibility Analysis

When AWS Porting Advisor cannot run (Python < 3.10, Docker unavailable, etc.), use this manual checklist.

## Quick Decision Tree

```
Can you build an ARM64 Docker image?
├─ YES → Try building it! (Fastest validation)
│   └─ Builds successfully?
│       ├─ YES → 90% done, proceed to testing
│       └─ NO → Read error, follow fixes below
│
└─ NO → Follow manual analysis below
```

---

## Step 1: Inventory Your Dependencies

### Python Projects

```bash
# Find all requirements files
find . -name "requirements*.txt" -o -name "setup.py" -o -name "pyproject.toml"

# Extract unique package names
cat requirements.txt | grep -v "^#" | cut -d'=' -f1 | sort -u
```

**Check against compatibility list below**

### Node.js Projects

```bash
# Find package.json files
find . -name "package.json"

# Extract dependencies
cat package.json | jq '.dependencies, .devDependencies'
```

**Good news:** 99% of npm packages are pure JavaScript → ARM64 compatible ✅

### Go Projects

```bash
# Find go.mod
find . -name "go.mod"
```

**Check for:**
- CGO dependencies (need recompilation)
- Architecture-specific imports (`//go:build amd64`)

### Java Projects

```bash
# Find Maven/Gradle files
find . -name "pom.xml" -o -name "build.gradle"
```

**Check for:**
- Native libraries (JNI)
- Architecture-specific JARs

---

## Step 2: Base Image Compatibility

### ✅ Known ARM64-Compatible Base Images

```dockerfile
# Official images that support ARM64
FROM python:3.8-slim      # ✅ All Python versions
FROM python:3.11-alpine   # ✅ Alpine variants
FROM node:16              # ✅ All Node.js versions
FROM node:20-slim         # ✅ Slim variants
FROM golang:1.21          # ✅ All Go versions
FROM openjdk:17           # ✅ All OpenJDK versions
FROM amazoncorretto:17    # ✅ Amazon Corretto
FROM ubuntu:22.04         # ✅ Ubuntu 20.04+
FROM debian:bullseye      # ✅ Debian 10+
FROM alpine:3.18          # ✅ All Alpine versions
FROM nginx:latest         # ✅ Official nginx
FROM redis:7              # ✅ Official redis
```

### ⚠️ Check These Carefully

```dockerfile
FROM custom/proprietary-image  # Contact vendor
FROM company/internal-image    # Check build process
FROM someuser/unofficial       # May not have ARM64 build
```

**How to check:**
```bash
# Check if image has ARM64 manifest
docker manifest inspect python:3.11-slim | grep "architecture.*arm64"

# Or try pulling
docker pull --platform linux/arm64 python:3.11-slim
```

---

## Step 3: Python Package Compatibility

### ✅ Tier 1: Pure Python (100% Compatible)

No compilation needed, works everywhere:

```
aiohttp, aioboto3, aiobotocore
boto3, botocore
click, typer
cryptography (recent versions)
fastapi, uvicorn, starlette
httpx, requests, urllib3
openai, anthropic
pandas >= 2.0.0
pydantic
python-dotenv
pyjwt
tenacity, retry
tiktoken
```

### ✅ Tier 2: ARM64 Wheels Available

Pre-built binaries exist:

```
numpy >= 2.0.0        # Earlier versions may need source build
pillow >= 8.3.0       # Earlier versions may need source build
scipy >= 1.7.0        # May need apt packages: libopenblas-dev
transformers >= 4.0   # HuggingFace
torch >= 2.0          # Use ARM64 wheel from pytorch.org
opencv-python >= 4.5  # ARM64 wheels available
grpcio               # ARM64 wheels available
psycopg2-binary      # ARM64 wheels available
```

### ⚠️ Tier 3: May Need Source Build

These might require compilation:

```
tensorflow < 2.9     # Upgrade to >= 2.9 for ARM64 support
dlib                 # Needs cmake, may be slow
pycocotools          # Needs source build
some-old-package     # Check PyPI for wheels
```

**How to check if wheel exists:**
```bash
# Visit PyPI page
https://pypi.org/project/PACKAGE_NAME/#files

# Look for files named:
# PACKAGE-VERSION-cp311-cp311-manylinux_2_17_aarch64.whl
# The "aarch64" indicates ARM64 support
```

### ❌ Tier 4: Problematic

```
x86-only-library     # No ARM64 version exists
legacy-package       # Unmaintained, no ARM64 support
```

**Solutions:**
1. Find alternative package
2. Contact maintainer for ARM64 support
3. Fork and build ARM64 version yourself
4. Keep this component on x86 (hybrid approach)

---

## Step 4: Node.js Package Compatibility

### ✅ Good News

**99% of npm packages are compatible** because:
- Most are pure JavaScript
- Node.js itself fully supports ARM64
- Binary addons usually have ARM64 builds

### ⚠️ Check These

**Packages with native addons:**
```json
{
  "sharp": "^0.30.0",      // ✅ Has ARM64 prebuilds
  "bcrypt": "^5.0.0",      // ✅ Has ARM64 prebuilds
  "sqlite3": "^5.0.0",     // ✅ Has ARM64 prebuilds
  "canvas": "^2.9.0",      // ⚠️ May need cairo libs
  "node-sass": "*"         // ❌ Deprecated, use dart-sass
}
```

**How to verify:**
```bash
# After npm install on ARM64, check for errors
npm install --verbose

# Rebuild native modules
npm rebuild

# Test import
node -e "require('sharp')"
```

---

## Step 5: System Dependencies

Some packages need OS-level libraries:

### Python Examples

```dockerfile
# For pillow (image processing)
RUN apt-get update && apt-get install -y \
    libjpeg-dev \
    zlib1g-dev

# For opencv
RUN apt-get install -y \
    libopencv-dev \
    libgl1

# For scientific packages
RUN apt-get install -y \
    libopenblas-dev \
    liblapack-dev
```

### Node.js Examples

```dockerfile
# For canvas
RUN apt-get install -y \
    libcairo2-dev \
    libpango1.0-dev \
    libjpeg-dev \
    libgif-dev

# For sharp
RUN apt-get install -y \
    libvips-dev
```

---

## Step 6: Build a Test Matrix

Create a simple test:

```bash
#!/bin/bash
# test-compatibility.sh

echo "Testing ARM64 compatibility..."

# Test 1: Base image
docker pull --platform linux/arm64 python:3.11-slim && echo "✅ Base image OK" || echo "❌ Base image FAIL"

# Test 2: Simple build
cat > Dockerfile.test <<EOF
FROM --platform=linux/arm64 python:3.11-slim
RUN pip install boto3 requests
EOF

docker build --platform linux/arm64 -f Dockerfile.test -t test:arm64 . && echo "✅ Simple build OK" || echo "❌ Simple build FAIL"

# Test 3: Your dependencies
cat > Dockerfile.test2 <<EOF
FROM --platform=linux/arm64 python:3.11-slim
COPY requirements.txt .
RUN pip install -r requirements.txt
EOF

docker build --platform linux/arm64 -f Dockerfile.test2 -t test2:arm64 . && echo "✅ Full deps OK" || echo "❌ Full deps FAIL"

# Test 4: Import test
docker run --rm test2:arm64 python -c "import numpy, pandas" && echo "✅ Imports OK" || echo "❌ Imports FAIL"
```

---

## Step 7: Document Your Findings

Create a simple compatibility report:

```markdown
# ARM64 Compatibility Report

**Date:** 2026-02-05
**Project:** my-project

## Base Image
- Current: python:3.11-slim
- ARM64 Support: ✅ YES

## Dependencies

### Pure Python (No Issues)
- boto3, fastapi, requests, pydantic

### Binary Packages
| Package | Version | ARM64 Wheel | Status |
|---------|---------|-------------|--------|
| numpy | 2.0.0 | ✅ Yes | OK |
| pillow | 11.1.0 | ✅ Yes | OK |
| torch | 2.1.0 | ⚠️ Need specific wheel | Need to test |

### Problematic
- None identified

## Build Test
- ✅ Docker build succeeded
- ✅ Import tests passed
- ⏱️ Build time: 5 minutes

## Recommendation
**Proceed with migration** - No blockers identified

## Next Steps
1. Test torch wheel installation
2. Build ARM64 image in dev
3. Run integration tests
```

---

## Quick Compatibility Checks

### Python Package

```bash
# Check if package has ARM64 wheel
pip download --platform manylinux2014_aarch64 --only-binary=:all: PACKAGE_NAME

# If succeeds → ARM64 wheel exists ✅
# If fails → May need source build ⚠️
```

### Docker Image

```bash
# Check multi-arch manifest
docker manifest inspect IMAGE_NAME | grep -A 5 "arm64"

# If found → ARM64 supported ✅
# If not → Need alternative image ⚠️
```

### npm Package

```bash
# Install and see if it works
npm install PACKAGE_NAME
# Usually works! Node ecosystem is great for ARM64
```

---

## Common Patterns

### Pattern 1: "Everything is Pure Python"

```
Status: ✅ EASY (1-2 hours)
Action: Just build ARM64 image, it'll work
Risk: Very low
```

### Pattern 2: "Modern Dependencies (2022+)"

```
Status: ✅ STRAIGHTFORWARD (2-4 hours)
Action: Build ARM64, maybe update 1-2 package versions
Risk: Low
```

### Pattern 3: "ML/Data Science Stack"

```
Status: ⚠️ MODERATE (4-8 hours)
Action: Test PyTorch/TensorFlow carefully, update NumPy/Pandas
Risk: Medium (test thoroughly)
```

### Pattern 4: "Legacy Code with Old Deps"

```
Status: ⚠️ CHALLENGING (8-16 hours)
Action: Update dependencies first, then migrate
Risk: Medium-High (consider refactoring)
```

### Pattern 5: "Custom Native Extensions"

```
Status: ❌ COMPLEX (16+ hours)
Action: Recompile for ARM64, may need code changes
Risk: High (consider alternatives)
```

---

## Decision Matrix

| If you have... | Then... | Time | Risk |
|----------------|---------|------|------|
| Pure Python/Node | Just migrate | 1-2h | 🟢 Low |
| Modern packages (2022+) | Update versions, migrate | 2-4h | 🟢 Low |
| NumPy/Pandas/SciPy | Check versions, test | 4-6h | 🟡 Medium |
| PyTorch/TensorFlow | Extensive testing needed | 8-12h | 🟡 Medium |
| Custom C extensions | Recompile, test thoroughly | 16h+ | 🔴 High |
| Proprietary x86 libs | Find alternatives or stay x86 | N/A | 🔴 High |

---

## When to Stay on x86

Consider keeping x86 if:

1. **Proprietary x86-only dependencies** with no alternative
2. **Massive refactor required** (> 40 hours effort)
3. **No cost pressure** (small workload, budget not constrained)
4. **Tight deadline** (migration risk not worth it)
5. **Legacy system** being replaced soon anyway

**Hybrid approach:** Migrate 80% to ARM64, keep 20% on x86

---

## Summary Checklist

- [ ] Inventoried all dependencies
- [ ] Checked base image ARM64 support
- [ ] Verified Python packages have ARM64 wheels (or are pure Python)
- [ ] Verified Node packages (usually automatic)
- [ ] Identified system dependencies needed
- [ ] Built test ARM64 image
- [ ] Ran import tests
- [ ] Documented findings
- [ ] Made go/no-go decision

**If all checks pass → Proceed to build and test phase!**

---

## Next Steps

After manual analysis:
1. Read [build-and-test.md](build-and-test.md) for validation steps
2. Use `test-arm64-build.sh` script for automated testing
3. Generate migration plan with `generate-plan.sh`
