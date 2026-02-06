# Graviton Migration - Quick Start Guide

Get started with AWS Graviton migration in 5 minutes.

## Installation (One-time setup)

```bash
# Add to your shell profile for easy access
echo 'alias graviton-migration="$HOME/.claude/skills/graviton-migration/graviton-migration.sh"' >> ~/.zshrc
source ~/.zshrc

# Setup tools (installs Porting Advisor)
graviton-migration setup
```

## 5-Minute Migration Check

### 1. Scan Your Codebase (2 min)

```bash
cd /path/to/your/project
graviton-migration scan .
```

**Output:** `porting-advisor-report.html`

### 2. Analyze Results (1 min)

```bash
graviton-migration analyze porting-advisor-report.html
```

**You'll see:**
- ✅ Compatible packages
- ⚠️ Issues to fix (with specific commands)
- 📊 Severity breakdown
- 🎯 Recommended actions

### 3. Calculate Savings (1 min)

```bash
# Replace with your current instance type
graviton-migration cost-compare --current m5.xlarge --target m6g.xlarge --count 10
```

**You'll see:**
- 💰 Monthly/yearly savings
- 📈 Price-performance improvement
- 📊 Cost breakdown

### 4. Get Migration Plan (1 min)

```bash
graviton-migration plan --instance-type m6g.xlarge
```

**You'll see:**
- ✅ Step-by-step checklist
- 📋 Tasks for each phase
- 🚀 Deployment strategies

## Real-World Example

### Scenario: Python Flask API on m5.xlarge

```bash
# Step 1: Scan
cd ~/projects/flask-api
graviton-migration scan .

# Output shows:
# ✗ numpy 1.19.0 - Upgrade to 1.21.0+ for ARM64 wheels
# ✗ pillow 8.0.0 - Upgrade to 8.3.0+ for ARM64 support
# ✓ flask 2.0.1 - Compatible

# Step 2: Fix issues
pip install --upgrade numpy pillow

# Step 3: Test locally with ARM64 Docker
docker run --platform=linux/arm64 -v ./:/app python:3.11 python /app/app.py

# Step 4: Scan again to verify
graviton-migration scan . verified-report.html
graviton-migration analyze verified-report.html

# Step 5: Calculate savings (10 instances)
graviton-migration cost-compare --current m5.xlarge --target m6g.xlarge --count 10
# Shows: $300/month savings (20%)

# Step 6: Deploy!
# Update your IaC to use m6g.xlarge
# Deploy using blue-green or canary strategy
```

## Common Scenarios

### Scenario 1: No Issues Found ✅

```
✓ GOOD NEWS: No compatibility issues detected!
  Your codebase appears ready for Graviton migration.
```

**Next steps:**
1. Launch Graviton instance (m6g, c6g, r6g)
2. Deploy your application
3. Run integration tests
4. Monitor performance

### Scenario 2: Minor Issues Found ⚠️

```
⚠ Found 3 compatibility issue(s)
  🔴 High:   2 (blocking issues)
  🟠 Medium: 1 (recommended fixes)
```

**Example issues and fixes:**

**Issue:** Python package `numpy 1.19.0` - Missing ARM64 wheel
```bash
pip install --upgrade numpy  # Upgrades to 1.21.0+ with ARM64 support
```

**Issue:** Java dependency `leveldbjni-all` - Not supported on ARM64
```xml
<!-- Replace in pom.xml -->
<dependency>
    <groupId>org.rocksdb</groupId>
    <artifactId>rocksdbjni</artifactId>
    <version>7.9.2</version>
</dependency>
```

**Issue:** Docker base image `ubuntu:18.04` - Use recent version
```dockerfile
FROM ubuntu:22.04  # Or use ARM64-specific tag
```

### Scenario 3: Code Changes Required 🔧

**Issue:** Inline assembly detected in C code

```c
// Before (x86-only)
__asm__("movq %rax, %rbx");

// After (multi-architecture)
#ifdef __x86_64__
    __asm__("movq %rax, %rbx");
#elif __aarch64__
    __asm__("mov x0, x1");
#endif
```

## Testing Checklist

Before production deployment:

```bash
✅ Run graviton-migration scan → No high-priority issues
✅ Update all dependencies to ARM64-compatible versions
✅ Build application on Graviton instance
✅ Run full test suite → All tests pass
✅ Performance test → Meets or exceeds baseline
✅ Load test → Handles expected traffic
✅ Monitor for 24-48 hours in staging
✅ Update Infrastructure as Code
✅ Plan rollback strategy
```

## Deployment Strategies

### Strategy 1: Blue-Green (Recommended for production)

```bash
# 1. Launch Graviton instances in parallel (Green)
# 2. Deploy application to Green
# 3. Test Green thoroughly
# 4. Switch traffic to Green
# 5. Monitor for 24 hours
# 6. Terminate Blue instances
```

### Strategy 2: Canary (For risk-averse deployments)

```bash
# 1. Route 5% traffic to Graviton → Monitor 24h
# 2. Route 25% traffic → Monitor 24h
# 3. Route 50% traffic → Monitor 24h
# 4. Route 100% traffic → Complete migration
```

### Strategy 3: In-Place (For dev/test environments)

```bash
# 1. Stop instance
# 2. Change instance type to Graviton equivalent
# 3. Update architecture-specific configs
# 4. Start instance
# 5. Verify functionality
```

## Cost Savings Examples

| Current | Graviton | Count | Monthly Savings* |
|---------|----------|-------|------------------|
| t3.medium | t4g.medium | 10 | $62 |
| m5.large | m6g.large | 10 | $150 |
| m5.xlarge | m6g.xlarge | 10 | $300 |
| c5.2xlarge | c6g.2xlarge | 10 | $510 |
| r5.4xlarge | r6g.4xlarge | 10 | $1,600 |

*Based on us-east-1 on-demand pricing, ~20% savings

## Troubleshooting

### Issue: "Docker not found"
```bash
# Install Docker or use Python mode
graviton-migration setup  # Will auto-detect and use Python
```

### Issue: "Application crashes on Graviton"
```bash
# Check CloudWatch logs for errors
# Common causes:
# - Architecture-specific code
# - Missing ARM64 libraries
# - Incorrect binary architecture

# Solution: Recompile with ARM64 target
```

### Issue: "Performance worse than x86"
```bash
# Check compiler flags
# Enable architecture-specific optimizations
# Example for GCC/Clang:
-march=armv8.2-a+fp16+rcpc+dotprod+crypto
```

## Need Help?

1. **Check documentation:** `cat skill.md`
2. **AWS re:Post:** https://repost.aws/
3. **GitHub Issues:** https://github.com/aws/porting-advisor-for-graviton/issues

## Next Steps

After successful migration:
1. ✅ Document your migration process
2. ✅ Share learnings with your team
3. ✅ Plan migration for remaining workloads
4. ✅ Enjoy 20-40% cost savings! 🎉

---

**Ready to migrate?** Run: `graviton-migration scan /path/to/code`
