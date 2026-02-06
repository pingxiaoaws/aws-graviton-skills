# Package Compatibility Reference

Quick reference for common package ARM64 compatibility status.

## Python Packages

### ✅ Confirmed Compatible (No Changes Needed)

#### Web Frameworks & APIs
```
fastapi          - ✅ Pure Python
uvicorn          - ✅ Pure Python  
starlette        - ✅ Pure Python
flask            - ✅ Pure Python
django           - ✅ Pure Python
aiohttp          - ✅ Pure Python
httpx            - ✅ Pure Python
requests         - ✅ Pure Python
```

#### AWS & Cloud
```
boto3            - ✅ Pure Python
botocore         - ✅ Pure Python
aioboto3         - ✅ Pure Python
aiobotocore      - ✅ Pure Python
google-cloud-*   - ✅ Pure Python (most)
azure-*          - ✅ Pure Python (most)
```

#### Data & ML (Modern Versions)
```
numpy >= 2.0.0         - ✅ ARM64 wheels
pandas >= 2.0.0        - ✅ ARM64 wheels
scipy >= 1.7.0         - ✅ ARM64 wheels
scikit-learn >= 1.0    - ✅ ARM64 wheels
torch >= 2.0           - ✅ ARM64 wheels (pytorch.org)
transformers >= 4.0    - ✅ ARM64 wheels
pillow >= 8.3.0        - ✅ ARM64 wheels
opencv-python >= 4.5   - ✅ ARM64 wheels
```

#### Utilities
```
pydantic         - ✅ Pure Python
click            - ✅ Pure Python
typer            - ✅ Pure Python
python-dotenv    - ✅ Pure Python
tenacity         - ✅ Pure Python
pyjwt            - ✅ Pure Python
cryptography     - ✅ ARM64 wheels (recent versions)
```

#### Database Clients
```
psycopg2-binary  - ✅ ARM64 wheels
pymongo          - ✅ ARM64 wheels
redis-py         - ✅ Pure Python
sqlalchemy       - ✅ Pure Python
asyncpg          - ✅ ARM64 wheels
```

#### Testing
```
pytest           - ✅ Pure Python
pytest-cov       - ✅ Pure Python
pytest-asyncio   - ✅ Pure Python
unittest         - ✅ Built-in
```

---

### ⚠️ Version-Dependent (Update if Needed)

```python
numpy < 2.0.0      # ⚠️ May need source build
                   # Fix: pip install "numpy>=2.0.0"

pillow < 8.3.0     # ⚠️ May need source build
                   # Fix: pip install "pillow>=8.3.0"

pandas < 2.0.0     # ⚠️ May need source build
                   # Fix: pip install "pandas>=2.0.0"

tensorflow < 2.9   # ❌ No ARM64 support
                   # Fix: pip install "tensorflow>=2.9.0"

torch < 1.12       # ⚠️ Limited ARM64 support
                   # Fix: pip install "torch>=2.0"
```

---

### 🔍 How to Check

#### Method 1: PyPI Files Page
```bash
# Visit:
https://pypi.org/project/PACKAGE_NAME/#files

# Look for filenames containing:
# - manylinux_2_17_aarch64
# - manylinux2014_aarch64  
# These indicate ARM64 wheels
```

#### Method 2: pip download test
```bash
# Try downloading ARM64 wheel
pip download \
  --platform manylinux2014_aarch64 \
  --only-binary=:all: \
  PACKAGE_NAME

# Success → ARM64 wheel exists ✅
# Failure → May need source build ⚠️
```

#### Method 3: Just try installing
```bash
# On ARM64 machine or Docker
docker run --rm --platform linux/arm64 python:3.11-slim \
  pip install PACKAGE_NAME

# Works → Compatible ✅
# Fails → Check error message
```

---

## Node.js Packages

### ✅ Generally Compatible

**Good news:** 99%+ of npm packages work on ARM64 because:
- Most are pure JavaScript
- Native addons usually have ARM64 prebuilds
- Node.js ecosystem embraced ARM64 early

### ⚠️ Packages with Native Addons

```json
{
  "sharp": "^0.30.0",          // ✅ ARM64 prebuilds
  "bcrypt": "^5.0.0",          // ✅ ARM64 prebuilds
  "sqlite3": "^5.0.0",         // ✅ ARM64 prebuilds
  "canvas": "^2.9.0",          // ⚠️ Needs system libs
  "node-gyp": "*",             // ⚠️ May need rebuild
  "node-sass": "*",            // ❌ Deprecated, use dart-sass
  "fsevents": "*",             // ✅ macOS-only, ignored on Linux
}
```

### How to Handle

```bash
# After npm install on ARM64
npm rebuild

# If specific package fails
npm rebuild PACKAGE_NAME

# Check for prebuild
npm install --verbose 2>&1 | grep "prebuild"
```

---

## Go Packages

### ✅ Generally Excellent ARM64 Support

**Why:** Go cross-compiles easily, ARM64 is first-class target

### Build for ARM64

```bash
# Cross-compile from x86
GOOS=linux GOARCH=arm64 go build -o app-arm64

# Or in Docker
FROM --platform=linux/arm64 golang:1.21 AS builder
WORKDIR /app
COPY . .
RUN go build -o app
```

### ⚠️ Check CGO Dependencies

```bash
# Find CGO usage
grep -r "import \"C\"" .

# CGO needs cross-compilation toolchain
# Or build natively on ARM64
```

---

## Java Packages

### ✅ Excellent ARM64 Support

**Why:** JVM is architecture-independent (mostly)

### Recommended JDKs for ARM64

```
Amazon Corretto 8/11/17/21  - ✅ Optimized for Graviton
OpenJDK 11/17/21            - ✅ Full support
Eclipse Temurin             - ✅ Full support
```

### Docker Example

```dockerfile
FROM --platform=linux/arm64 amazoncorretto:17-alpine

WORKDIR /app
COPY target/myapp.jar .

CMD ["java", "-jar", "myapp.jar"]
```

### ⚠️ Check Native Libraries

```java
// JNI-based libraries may need ARM64 versions
// Example: RocksDB, LevelDB
<dependency>
    <groupId>org.rocksdb</groupId>
    <artifactId>rocksdbjni</artifactId>
    <version>7.9.2</version>  <!-- Has ARM64 support -->
</dependency>
```

---

## System Libraries (apt/yum)

### Ubuntu/Debian ARM64 repos

All standard packages available:
```bash
apt-get update
apt-get install -y \
    build-essential \
    libpq-dev \
    libssl-dev \
    libffi-dev \
    libjpeg-dev \
    zlib1g-dev \
    libopenblas-dev
# All have ARM64 versions ✅
```

### Amazon Linux 2023 ARM64

```bash
yum install -y \
    gcc \
    python3-devel \
    openssl-devel \
    postgresql-devel
# All have ARM64 versions ✅
```

---

## Quick Compatibility Test Script

```bash
#!/bin/bash
# quick-compat-check.sh PACKAGE_NAME

PACKAGE=$1

echo "Checking $PACKAGE for ARM64 compatibility..."

# Check PyPI
echo ""
echo "📦 Checking PyPI..."
PYPI_URL="https://pypi.org/pypi/$PACKAGE/json"
ARM64_WHEELS=$(curl -s "$PYPI_URL" | jq -r '.urls[].filename' | grep -i aarch64 | wc -l)

if [ "$ARM64_WHEELS" -gt 0 ]; then
    echo -e "${GREEN}✅ Found $ARM64_WHEELS ARM64 wheel(s)${NC}"
else
    echo -e "${YELLOW}⚠️  No ARM64 wheels found (may be pure Python or need source build)${NC}"
fi

# Check if pure Python
IS_PURE=$(curl -s "$PYPI_URL" | jq -r '.info.requires_python')
echo "🐍 Requires Python: $IS_PURE"

# Try download test
echo ""
echo "🧪 Testing wheel download..."
pip download --platform manylinux2014_aarch64 --only-binary=:all: "$PACKAGE" &> /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ ARM64 wheel download successful${NC}"
    rm -f *.whl
else
    echo -e "${YELLOW}⚠️  No pre-built ARM64 wheel available${NC}"
    echo "    (Package may be pure Python or require source build)"
fi
```

---

## Real-World Package Test Results

From aftersales-graph-on-aws migration:

| Package | Version | Result | Notes |
|---------|---------|--------|-------|
| boto3 | 1.37.1 | ✅ | Pure Python |
| openai | latest | ✅ | Pure Python |
| fastapi | latest | ✅ | Pure Python |
| uvicorn | latest | ✅ | Pure Python |
| numpy | 2.0.0 | ✅ | ARM64 wheel |
| pandas | 2.0.0 | ✅ | ARM64 wheel |
| torch | 2.1+ | ✅ | pytorch.org ARM64 wheel |
| transformers | 4.48.3 | ✅ | ARM64 wheel |
| pillow | 11.1.0 | ✅ | ARM64 wheel |
| docling | 2.28.4 | ✅ | Complex deps, but worked! |
| graspologic | 3.4.1 | ✅ | Worked in container |
| networkx | latest | ✅ | Pure Python |
| opensearch-py | 2.8.0 | ✅ | Pure Python |
| gremlinpython | latest | ✅ | Pure Python |

**Success rate:** 100% of tested packages ✅

---

## When You Find Incompatibility

### Step 1: Check for Updates
```bash
# Often newer versions have ARM64 support
pip install --upgrade PACKAGE_NAME
```

### Step 2: Check for Alternatives
```bash
# Example: If old-ml-lib doesn't work
# Look for: new-ml-lib, alternative-lib
```

### Step 3: Build from Source
```bash
# Install build dependencies
apt-get install -y build-essential python3-dev

# Force source build
pip install --no-binary :all: PACKAGE_NAME
```

### Step 4: Contact Maintainer
```bash
# Open GitHub issue
"Hi! Would you consider providing ARM64 wheels?
AWS Graviton adoption is growing rapidly.
Happy to test pre-releases!"
```

### Step 5: Hybrid Approach
```
Keep problematic component on x86
Migrate everything else to ARM64
→ Still get 80%+ of cost savings
```

---

**Pro Tip:** Most "incompatible" packages just need a version update. Try upgrading before giving up!
