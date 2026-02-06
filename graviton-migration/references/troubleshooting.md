# Graviton Migration Troubleshooting Guide

Common issues and solutions when migrating to ARM64.

---

## Build Issues

### Issue: "no matching manifest for linux/arm64"

**Full error:**
```
ERROR: failed to solve: python:3.11-slim: no match for platform in manifest
```

**Cause:** Base image doesn't have ARM64 build

**Solutions:**

```bash
# Option 1: Check if image supports ARM64
docker manifest inspect python:3.11-slim | grep -A 5 arm64
# If found → Image supports ARM64, try pulling again

# Option 2: Use alternative base image
# Instead of: FROM custom/image
# Use: FROM python:3.11-slim (official images support ARM64)

# Option 3: Find multi-arch alternative
# Check Docker Hub for "Architectures" section
# Or try: amazonlinux:2023, ubuntu:22.04, alpine:3.18
```

**Prevention:**
Always use official images when possible:
- ✅ `python:*`
- ✅ `node:*`
- ✅ `golang:*`
- ✅ `openjdk:*`
- ✅ `ubuntu:*`
- ✅ `alpine:*`

---

### Issue: Python package fails to install (no ARM64 wheel)

**Error:**
```
ERROR: Could not find a version that satisfies the requirement old-package==1.0
```

**Or:**
```
Building wheel for package (setup.py) ... error
ERROR: Failed building wheel for package
```

**Diagnosis:**

```bash
# Check if ARM64 wheel exists
pip download --platform manylinux2014_aarch64 --only-binary=:all: package-name

# Check package age
pip show package-name | grep Version
# Old packages (pre-2020) less likely to have ARM64 wheels
```

**Solutions:**

```bash
# Solution 1: Update to newer version
pip install "package-name>=2.0"  # Try latest

# Solution 2: Build from source (install build deps first)
apt-get install -y build-essential python3-dev
pip install --no-binary :all: package-name

# Solution 3: Use alternative package
# Example: old-cv-lib → opencv-python
# Example: old-ml-lib → scikit-learn

# Solution 4: Check package-specific ARM64 instructions
# PyTorch example:
pip install torch --index-url https://download.pytorch.org/whl/cpu
```

**Common Fixes:**

```python
# NumPy
numpy<2.0  → numpy>=2.0.0   # Has ARM64 wheels

# Pillow  
pillow<8.3 → pillow>=8.3.0  # Has ARM64 wheels

# Pandas
pandas<2.0 → pandas>=2.0.0  # Has ARM64 wheels

# TensorFlow
tensorflow<2.9 → tensorflow>=2.9.0  # ARM64 support

# PyTorch (special case)
pip install torch --index-url https://download.pytorch.org/whl/cpu
```

---

### Issue: Build is extremely slow (QEMU emulation)

**Symptom:**
```
Building on x86_64, targeting ARM64
Build takes 20-30 minutes (normally 2-3 minutes)
```

**Cause:** Docker buildx using QEMU emulation for cross-compilation

**Solutions:**

```bash
# Option 1: Use Graviton instance (BEST)
# Launch c7g.xlarge
aws ec2 run-instances --instance-type c7g.xlarge ...
# Build natively → 5-10x faster

# Option 2: Use AWS CodeBuild with ARM_CONTAINER
# buildspec.yml
version: 0.2
phases:
  build:
    commands:
      - docker build -t myapp:arm64 .
compute-type: ARM_CONTAINER

# Option 3: Use GitHub Actions ARM64 runners
# .github/workflows/build.yml
jobs:
  build:
    runs-on: ubuntu-24.04-arm64  # ARM64 runner
    steps:
      - uses: actions/checkout@v3
      - run: docker build -t myapp:arm64 .

# Option 4: Cache layers aggressively
# buildspec.yml
- docker buildx build --cache-from type=registry,ref=myapp:cache \
    --cache-to type=registry,ref=myapp:cache \
    --platform linux/arm64 ...
```

**Cost Comparison:**
- Build on x86 laptop: Free, 20-30 min
- c7g.xlarge for 1 hour: $0.14, 5 min build
- **Time is money!** Use Graviton for builds.

---

### Issue: "Illegal instruction" or "Exec format error"

**Error:**
```
standard_init_linux.go:228: exec user process caused: exec format error
```

**Or:**
```
Illegal instruction (core dumped)
```

**Cause:** Running x86 binary on ARM64 (or vice versa)

**Diagnosis:**

```bash
# Check what architecture binary is
docker run --rm myapp:arm64 uname -m
# Should show: aarch64 or arm64

# Check what platform image is
docker image inspect myapp:arm64 | jq '.[0].Architecture'
# Should show: arm64
```

**Solutions:**

```bash
# Solution 1: Ensure Dockerfile specifies platform
FROM --platform=linux/arm64 python:3.11-slim

# Solution 2: Rebuild with explicit platform
docker buildx build --platform linux/arm64 --load -t myapp:arm64 .

# Solution 3: Clear Docker build cache
docker builder prune -a
# Then rebuild

# Solution 4: Check for precompiled x86 binaries in image
# Some Dockerfiles download x86 binaries:
RUN wget https://example.com/app-x86.bin  # ❌ Wrong!
# Fix: Download ARM64 version or compile from source
```

**Prevention:**
```dockerfile
# Always specify platform
FROM --platform=linux/arm64 python:3.11-slim

# When downloading binaries, get ARM64 version
ARG TARGETARCH
RUN wget https://example.com/app-${TARGETARCH}.bin

# Or detect at runtime
RUN if [ "$(uname -m)" = "aarch64" ]; then \
      wget https://example.com/app-arm64.bin; \
    else \
      wget https://example.com/app-x86.bin; \
    fi
```

---

### Issue: System library missing

**Error:**
```
ImportError: libGL.so.1: cannot open shared object file
```

**Or:**
```
OSError: libopenblas.so.0: cannot open shared object file
```

**Cause:** Python package needs system library not installed in image

**Solutions:**

```dockerfile
# For OpenCV (libGL)
RUN apt-get update && apt-get install -y \
    libgl1 \
    libglib2.0-0

# For NumPy/SciPy (BLAS)
RUN apt-get install -y \
    libopenblas-dev \
    liblapack-dev

# For Pillow (image libs)
RUN apt-get install -y \
    libjpeg-dev \
    zlib1g-dev \
    libpng-dev

# For audio processing
RUN apt-get install -y \
    libsndfile1 \
    ffmpeg

# For database clients
RUN apt-get install -y \
    libpq-dev \
    libmysqlclient-dev
```

**Common Package → Library Mappings:**

| Package | System Library |
|---------|----------------|
| opencv-python | libgl1, libglib2.0-0 |
| numpy, scipy | libopenblas-dev |
| pillow | libjpeg-dev, zlib1g-dev |
| psycopg2 | libpq-dev |
| mysqlclient | libmysqlclient-dev |
| lxml | libxml2-dev, libxslt-dev |
| cffi | libffi-dev |

---

## Runtime Issues

### Issue: Application crashes with "Segmentation fault"

**Symptom:**
```
Container exits with code 139
Logs show: Segmentation fault (core dumped)
```

**Causes & Solutions:**

```bash
# Cause 1: Incompatible native extension
# Solution: Rebuild package from source
pip install --force-reinstall --no-binary :all: problematic-package

# Cause 2: Memory issue
# Solution: Increase task memory
# CDK example:
memoryLimitMiB: 8192  # Increase from 4096

# Cause 3: Bad interaction between packages
# Solution: Update all packages to latest versions
pip install --upgrade -r requirements.txt

# Cause 4: Actual bug in ARM64 version
# Solution: Report to package maintainer, consider alternative
```

---

### Issue: Performance worse than x86

**Symptom:**
```
ARM64 version slower than x86 version
```

**Diagnosis:**

```bash
# Check if actually running on ARM64
docker run --rm myapp:arm64 uname -m
# Should be: aarch64

# Check CPU usage
docker stats

# Check for x86 emulation (QEMU)
docker run --rm myapp:arm64 cat /proc/1/maps | grep qemu
# Should be empty! If QEMU found, you're emulating x86 on ARM64
```

**Common Causes:**

```bash
# Cause 1: Running x86 binary via QEMU emulation
# Solution: Rebuild image correctly for ARM64

# Cause 2: Not using ARM64-optimized libraries
# Example: Using generic BLAS instead of OpenBLAS
apt-get install -y libopenblas-dev

# Cause 3: Wrong vCPU/memory ratio
# Graviton performs best with memory-balanced workloads
# Bad:  2 vCPU, 16 GB (too much memory)
# Good: 4 vCPU, 8 GB (balanced)

# Cause 4: Inefficient Dockerfile layers
# Solution: Combine RUN commands, use multi-stage builds
```

---

### Issue: Lambda "Invalid entrypoint" or import errors

**Error:**
```
Unable to import module 'lambda_function': No module named 'package'
```

**Cause:** Lambda package built on x86, deployed to ARM64

**Solution:**

```bash
# Install packages on ARM64 system
# Option 1: Use Docker
docker run --rm --platform linux/arm64 -v $(pwd):/var/task \
  public.ecr.aws/lambda/python:3.11 \
  pip install -r requirements.txt -t .

# Option 2: Use EC2 ARM64 instance
ssh ec2-user@graviton-instance
pip install -r requirements.txt -t python/

# Option 3: Use AWS SAM with ARM64
# template.yaml
Resources:
  MyFunction:
    Type: AWS::Serverless::Function
    Properties:
      Architectures:
        - arm64
      Runtime: python3.11

# Then: sam build --use-container
```

---

## ECS/Fargate Issues

### Issue: Task fails to start (CannotPullContainerError)

**Error:**
```
CannotPullContainerError: API error (404): manifest for xxx:arm64 not found
```

**Solutions:**

```bash
# Solution 1: Verify image exists in ECR
aws ecr describe-images --repository-name myapp --image-ids imageTag=arm64

# Solution 2: Check image manifest
docker manifest inspect <ECR_URI>/myapp:arm64 | grep arm64
# Should find arm64 architecture

# Solution 3: Retag and push
docker tag myapp:arm64 <ECR_URI>/myapp:arm64
docker push <ECR_URI>/myapp:arm64

# Solution 4: Check ECR permissions
aws ecr get-login-password | docker login --username AWS --password-stdin <ECR_URI>
```

---

### Issue: Task starts but immediately exits

**Error:**
```
Task stopped at: <timestamp>
StopCode: EssentialContainerExited
```

**Diagnosis:**

```bash
# Check CloudWatch logs
aws logs tail /ecs/myapp --follow

# Run container locally to debug
docker run --rm --platform linux/arm64 myapp:arm64

# Check entrypoint
docker inspect myapp:arm64 | jq '.[0].Config.Entrypoint'
```

**Common Causes:**

```dockerfile
# Cause 1: Wrong entrypoint command
# Fix:
CMD ["python", "app.py"]  # Not: CMD python app.py

# Cause 2: Missing environment variables
# Check ECS task definition environment vars

# Cause 3: Port mismatch
# Container exposes 8000, but task definition maps 80
# Fix: Make them match
```

---

### Issue: Task running but health check fails

**Error:**
```
Service myapp did not stabilize
Health check failing
```

**Diagnosis:**

```bash
# Test health endpoint locally
docker run --rm --platform linux/arm64 -p 8080:8080 myapp:arm64
curl http://localhost:8080/health

# Check task definition health check
aws ecs describe-task-definition --task-definition myapp
```

**Solutions:**

```bash
# Increase health check grace period
# CDK:
healthCheckGracePeriod: Duration.seconds(120)  # Increase from 60

# Adjust health check parameters
healthCheck: {
  command: ["CMD-SHELL", "curl -f http://localhost/health || exit 1"],
  interval: Duration.seconds(30),
  timeout: Duration.seconds(5),
  retries: 3,
  startPeriod: Duration.seconds(60)
}
```

---

## CDK/Terraform Issues

### Issue: CDK deploy fails (unsupported architecture)

**Error:**
```
Property 'cpuArchitecture' not supported
```

**Cause:** Using old CDK version

**Solution:**

```bash
# Update CDK
npm update aws-cdk-lib

# Ensure CDK version >= 2.80.0
# (ARM64 support added in 2.80.0)

# Verify
npm list aws-cdk-lib
```

**Correct syntax:**

```typescript
import * as ecs from 'aws-cdk-lib/aws-ecs';

const taskDef = new ecs.FargateTaskDefinition(this, 'TaskDef', {
  cpu: 2048,
  memoryLimitMiB: 4096,
  runtimePlatform: {
    cpuArchitecture: ecs.CpuArchitecture.ARM64,
    operatingSystemFamily: ecs.OperatingSystemFamily.LINUX,
  },
});
```

---

## Rollback Procedures

### Lambda Rollback

```bash
# Option 1: Redeploy with X86_64
# Change architecture in code, deploy

# Option 2: Roll back to previous version
aws lambda update-function-configuration \
  --function-name myfunction \
  --architectures x86_64

# Option 3: Use alias/version
aws lambda update-alias \
  --function-name myfunction \
  --name production \
  --function-version $PREVIOUS_VERSION
```

---

### ECS Rollback

```bash
# Option 1: Update service to use x86 task definition
aws ecs update-service \
  --cluster mycluster \
  --service myservice \
  --task-definition myapp-x86:123

# Option 2: Terraform/CDK
# Change runtimePlatform back to X86_64, apply

# Option 3: Blue-Green
# Keep x86 target group, route traffic back
```

**Time to rollback:** 5-15 minutes

---

## Prevention Checklist

Before production deployment:

- [ ] Built ARM64 image successfully
- [ ] Tested all package imports
- [ ] Ran integration tests
- [ ] Load tested in dev environment
- [ ] Compared performance with x86 baseline
- [ ] Tested health checks
- [ ] Verified logging works
- [ ] Documented rollback procedure
- [ ] Scheduled deployment during low-traffic window
- [ ] Have x86 task definition ready as backup

---

## Getting Help

### Check These Resources

1. **AWS Graviton GitHub:** https://github.com/aws/aws-graviton-getting-started
2. **Porting Advisor:** https://github.com/aws/porting-advisor-for-graviton
3. **Package-specific docs:** Check if package has ARM64 notes

### File Issues

When filing bug reports, include:

```bash
# System info
uname -a

# Docker version
docker --version

# Image architecture
docker image inspect myapp:arm64 | jq '.[0].Architecture'

# Build command used
echo "docker buildx build --platform linux/arm64 ..."

# Full error message (not truncated)

# Minimal reproduction steps
```

---

## Quick Reference: Error → Solution

| Error | Quick Fix |
|-------|-----------|
| "no matching manifest" | Use official base image |
| "illegal instruction" | Rebuild with --platform linux/arm64 |
| "library not found" | Install system dependencies |
| Build too slow | Use Graviton instance |
| Package install fails | Update package version |
| Segfault | Rebuild packages from source |
| Health check fails | Increase grace period |
| Image not found | Push to ECR, check region |

---

**Pro Tip:** Most issues are fixable in < 30 minutes. The most common cause is forgetting `--platform=linux/arm64` somewhere in the build process.
