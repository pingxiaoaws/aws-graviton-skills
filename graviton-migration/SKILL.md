---
name: graviton-migration-v2
description: Migrate AWS workloads from x86 to Graviton (ARM64) processors. Use when converting ECS Fargate/EC2, Lambda, or container workloads to ARM64 for 20-40% cost savings and improved performance. Includes manual analysis when Porting Advisor unavailable, build validation scripts, real-world migration plans, and comprehensive troubleshooting. Covers both automated tool-based analysis and practical build-first approaches.
---

# Graviton Migration Skill (Enhanced)

Migrate AWS workloads from x86 to ARM64 Graviton processors for significant cost savings (20-40%) and performance improvements.

## What's New in V2

V2 **keeps all original Porting Advisor functionality** and adds:

- ✅ **Porting Advisor wrapper** - Easier to use, checks requirements
- ✅ **Manual analysis workflow** - Fallback when Porting Advisor unavailable
- ✅ **Build-first validation** - Quick compatibility check
- ✅ **Environment detection** - Optimizes for native vs cross-build
- ✅ **Real-world case study** - Complete ECS migration example
- ✅ **Practical troubleshooting** - Based on actual issues encountered
- ✅ **All original scripts** - graviton-migration.sh and helpers preserved

---

## Quick Start

### Method 1: Automated Analysis with Porting Advisor (RECOMMENDED) ⭐

```bash
# This is the PREFERRED and most comprehensive approach
./scripts/analyze-project.sh /path/to/project

# Or use the original script directly:
./scripts/graviton-migration.sh

# Or run Porting Advisor directly (if installed):
python3 ~/porting-advisor-for-graviton/src/porting-advisor.py /path/to/project
```

**Why use Porting Advisor:**
- Most comprehensive analysis
- Detects architecture-specific code
- Identifies library compatibility issues
- Generates detailed HTML report
- Official AWS tool

### Method 2: Manual Analysis (Fallback when tools unavailable)

```bash
# Check what you're running on
uname -m
# aarch64 = Already on Graviton! Native builds will be fast
# x86_64 = Need cross-compilation or use Graviton instance

# Quick dependency check
./scripts/quick-check.sh /path/to/project

# Read manual analysis guide
cat references/manual-analysis.md
```

### Method 3: Build-First Approach (Fastest validation)

```bash
# Just try building ARM64 images
./scripts/test-arm64-build.sh your-dockerfile

# If it builds and runs, you're 90% done!
```

---

## Migration Workflow

### Step 1: Environment Check

Run the environment detector:
```bash
./scripts/detect-environment.sh
```

**Output tells you:**
- Current architecture (ARM64 or x86_64)
- Docker buildx availability
- Python version (for Porting Advisor)
- Recommended approach

### Step 2: Compatibility Analysis

**Choose your path based on Step 1:**

#### Path A: AWS Porting Advisor (RECOMMENDED) ⭐

**This is the most comprehensive approach and should be your first choice.**

```bash
# Option 1: Use our wrapper script (easiest)
./scripts/analyze-project.sh /path/to/project

# Option 2: Use original script
./scripts/graviton-migration.sh

# Option 3: Docker (if Python < 3.10)
docker run --rm -v $(pwd):/src \
  public.ecr.aws/aws-graviton-guide/porting-advisor \
  /src --output report.html

# Option 4: Direct Python (if Porting Advisor installed)
git clone https://github.com/aws/porting-advisor-for-graviton
cd porting-advisor-for-graviton
python3 src/porting-advisor.py /path/to/your/project
```

**What Porting Advisor provides:**
- ✅ Architecture-specific code detection
- ✅ Library compatibility analysis
- ✅ Detailed HTML report with recommendations
- ✅ Official AWS support
- ✅ Regularly updated compatibility database

**See also:** `references/porting-advisor-quickstart.md` for detailed usage

#### Path B: Manual Analysis (Fallback when tools unavailable)
See [references/manual-analysis.md](references/manual-analysis.md) for:
- Dependency compatibility checklist
- Common ARM64-compatible packages
- Known problematic packages
- Mitigation strategies

#### Path C: Build-First (Fastest)
```bash
# Just build it and see what breaks
./scripts/test-arm64-build.sh path/to/Dockerfile

# This often reveals issues faster than static analysis
```

### Step 3: Build and Test ARM64 Images

Use the included build validation script:
```bash
./scripts/test-arm64-build.sh \
  --dockerfile path/to/Dockerfile \
  --image-name my-app-arm64 \
  --test-import "import numpy, pandas, torch"
```

**What it does:**
- Builds ARM64 image
- Validates architecture (aarch64)
- Tests package imports
- Reports build time
- Saves build log

### Step 4: Generate Migration Plan

Based on analysis results:
```bash
./scripts/generate-plan.sh \
  --project-path /path/to/project \
  --output migration-plan.md
```

### Step 5: Phased Migration

Follow generated plan (typically):
1. **Week 1:** Lambda functions (lowest risk)
2. **Week 2:** Simple batch jobs
3. **Week 3:** API services (canary deployment)
4. **Week 4:** Complex workloads (extensive testing)

---

## Key Concepts

### Native vs Cross-Build

**If you're on Graviton (aarch64):**
```bash
# Native builds are FAST (no emulation)
docker build --platform linux/arm64 -t myapp:arm64 .
# Typical: 2-5 minutes
```

**If you're on x86_64:**
```bash
# Cross-builds use QEMU emulation (SLOWER)
docker buildx build --platform linux/arm64 --load -t myapp:arm64 .
# Typical: 10-30 minutes (5-10x slower)

# Tip: Consider using a Graviton EC2 instance for builds!
```

### ARM64 Compatibility Tiers

**Tier 1: Zero Changes Needed (✅ 70% of workloads)**
- Pure Python code
- Node.js applications
- Go binaries (with GOARCH=arm64)
- Java applications (with Corretto or OpenJDK)
- Official Docker images (python, node, alpine, etc.)

**Tier 2: Minor Adjustments (⚠️ 25% of workloads)**
- Update package versions (e.g., numpy >= 2.0)
- Change PyTorch wheel source
- Rebuild native extensions
- Update Dockerfile FROM statements

**Tier 3: Significant Work (❌ 5% of workloads)**
- x86 inline assembly code
- Proprietary x86-only libraries
- Legacy dependencies without ARM64 support

---

## Real-World Case Study

### ECS Fargate Migration (aftersales-graph-on-aws)

**Project:** Document processing pipeline with PyTorch + docling  
**Components:** API Service, Processor, Ingestion, Lambda functions  
**Result:** 26-40% cost savings, 0 functional regressions

**Full case study:** [references/case-study-ecs-fargate.md](references/case-study-ecs-fargate.md)

**Key lessons:**
1. Build ARM64 images first - catches 90% of issues
2. Test critical path (document processing) extensively
3. Lambda migration is trivial (just change architecture flag)
4. Use canary deployments for production services
5. Keep x86 parallel until full validation

---

## Common Scenarios

### Scenario 1: ECS Fargate Python App

**Challenge:** Migrate Python 3.11 app with numpy, pandas  
**Solution:**
```dockerfile
# Change FROM line
FROM --platform=linux/arm64 python:3.11-slim

# Add to CDK
runtimePlatform: {
  cpuArchitecture: ecs.CpuArchitecture.ARM64,
}
```
**Time:** 1-2 hours  
**Savings:** 20-25%

### Scenario 2: Lambda Functions

**Challenge:** Python Lambda with boto3, requests  
**Solution:**
```typescript
// In CDK, change:
architecture: Architecture.X86_64
// To:
architecture: Architecture.ARM_64
```
**Time:** 5-10 minutes  
**Savings:** 20% + 20% faster

### Scenario 3: ML Workload with PyTorch

**Challenge:** PyTorch + transformers on ECS  
**Solution:**
```dockerfile
# Use ARM64 PyTorch wheel
RUN pip install torch --index-url https://download.pytorch.org/whl/cpu

# Test extensively
RUN python -c "import torch; print(torch.__version__)"
```
**Time:** 4-8 hours (testing critical)  
**Savings:** 30-40%

---

## Troubleshooting

### Issue: "No matching manifest for linux/arm64"

**Cause:** Base image doesn't support ARM64  
**Solution:** Find alternative image or use multi-arch base

Common alternatives:
- `python:3.x` → Official, supports ARM64 ✅
- `ubuntu:22.04` → Supports ARM64 ✅
- `alpine:3.x` → Supports ARM64 ✅
- Proprietary images → Check with vendor

### Issue: Python package missing ARM64 wheel

**Cause:** Package doesn't provide pre-built ARM64 binary  
**Solution:**
```bash
# Option 1: Build from source
pip install --no-binary :all: package-name

# Option 2: Update to newer version
pip install package-name --upgrade

# Option 3: Find alternative package
```

**Common fixes:**
- `numpy < 2.0` → Upgrade to `>= 2.0.0`
- `pillow < 8.3` → Upgrade to `>= 8.3.0`
- `scipy` → Usually works, may need build deps

### Issue: Build is extremely slow

**Cause:** Cross-compiling with QEMU emulation  
**Solutions:**
```bash
# Option 1: Use Graviton instance for builds
# Launch c7g.xlarge, install Docker, build natively

# Option 2: Use AWS CodeBuild with ARM_CONTAINER
# BuildSpec:
# compute-type: ARM_CONTAINER

# Option 3: Build in CI/CD on ARM runners
# GitHub Actions: runs-on: ubuntu-24.04-arm64
```

### Issue: "Illegal instruction" at runtime

**Cause:** Binary compiled for wrong architecture  
**Solutions:**
1. Verify Dockerfile has `--platform=linux/arm64`
2. Clear Docker cache: `docker builder prune -a`
3. Rebuild with explicit platform flag
4. Check for precompiled x86 binaries in image

**Full troubleshooting guide:** [references/troubleshooting.md](references/troubleshooting.md)

---

## Cost Calculator

### Quick Estimate

**ECS Fargate:**
- x86: $0.04048/vCPU/hr, $0.004445/GB/hr
- ARM64: $0.032384/vCPU/hr, $0.003556/GB/hr
- **Savings: ~20%**

**Lambda:**
- x86: $0.0000166667/GB-sec
- ARM64: $0.0000133334/GB-sec
- **Savings: ~20%**

**EC2 (c7g vs c6i):**
- c6i.xlarge (x86): $0.17/hr
- c7g.xlarge (ARM): $0.1445/hr
- **Savings: ~15%**

**Use the cost estimator:**
```bash
./scripts/estimate-savings.sh \
  --current-cost 1000 \
  --service ecs-fargate
```

---

## Best Practices

### 1. Test Early, Test Often
```bash
# Build ARM64 image on day 1
# Don't wait for complete analysis
docker buildx build --platform linux/arm64 ...
```

### 2. Migrate in Phases
```
Low risk first: Lambda → Batch jobs → API services → ML workloads
```

### 3. Keep Rollback Path
```bash
# Blue-Green deployment
# Keep x86 task definition active during migration
```

### 4. Monitor Closely
```bash
# Watch for:
- Error rate changes
- Latency increases
- Memory usage patterns
- CPU utilization
```

### 5. Document Findings
```bash
# Note any package version changes
# Record build time differences
# Track cost savings
```

---

## Scripts Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `detect-environment.sh` | Check current setup | `./scripts/detect-environment.sh` |
| `quick-check.sh` | Fast dependency scan | `./scripts/quick-check.sh /project` |
| `test-arm64-build.sh` | Build and validate image | `./scripts/test-arm64-build.sh Dockerfile` |
| `generate-plan.sh` | Create migration plan | `./scripts/generate-plan.sh --project /path` |
| `estimate-savings.sh` | Calculate cost savings | `./scripts/estimate-savings.sh --cost 1000` |

---

## References

- [Manual Analysis Guide](references/manual-analysis.md) - When Porting Advisor unavailable
- [Build and Test Guide](references/build-and-test.md) - ARM64 image validation
- [Troubleshooting Guide](references/troubleshooting.md) - Common issues and solutions
- [ECS Case Study](references/case-study-ecs-fargate.md) - Real-world migration example
- [Package Compatibility](references/package-compatibility.md) - Known ARM64 support status

---

## Contributing

Found an issue or improvement? This skill was enhanced based on real-world migration experience.

**Common enhancements:**
- Add more case studies
- Expand package compatibility list
- Improve automation scripts
- Add cloud-specific guides (EKS, ECS, Lambda, etc.)

---

## Version History

**v2.0 (2026-02-05):**
- ✅ Added manual analysis workflow
- ✅ Added build-first approach
- ✅ Added environment detection
- ✅ Added real-world case study
- ✅ Added practical troubleshooting
- ✅ Added automation scripts
- ✅ Improved for scenarios where Porting Advisor unavailable

**v1.0:**
- Initial version focused on Porting Advisor

---

**Pro Tip:** Start with Lambda migration - it's the fastest way to prove value and build confidence before tackling larger workloads!
