# AWS Graviton Skills

Collection of Clawdbot skills for AWS Graviton migration and optimization.

## Skills

### graviton-migration-v2

Migrate AWS workloads from x86 to Graviton (ARM64) processors for 20-40% cost savings and improved performance.

**Features:**
- ✅ Automated analysis with AWS Porting Advisor
- ✅ Manual analysis workflow (fallback when tools unavailable)
- ✅ Build-first validation approach
- ✅ Environment detection (native vs cross-build)
- ✅ Real-world case studies and troubleshooting
- ✅ Complete migration scripts

**Supports:**
- ECS Fargate
- Lambda functions
- EC2 instances
- Container workloads

**Cost Savings:** 20-40% depending on workload type

For detailed documentation, see [graviton-migration/SKILL.md](./graviton-migration/SKILL.md)

## Installation

Copy the skill directory to your Clawdbot skills folder:

```bash
cp -r graviton-migration ~/.clawdbot/skills/
```

Or if using global Clawdbot installation:

```bash
cp -r graviton-migration /path/to/clawdbot/skills/
```

## Usage

The skill is automatically available when Clawdbot loads. Simply ask:

```
"Help me migrate my ECS service to Graviton"
"Analyze this project for ARM64 compatibility"
"Generate a Graviton migration plan"
```

## Contributing

Contributions welcome! Please submit PRs or open issues.

## License

See individual skill directories for license information.
