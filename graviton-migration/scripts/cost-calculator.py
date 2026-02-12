#!/usr/bin/env python3
"""
AWS Graviton Migration - Cost Calculator
Calculates cost savings when migrating from x86 to Graviton instances
"""

import sys
import json
from decimal import Decimal

# Pricing data (us-east-1, on-demand, per hour)
# Source: AWS EC2 Pricing as of 2025
INSTANCE_PRICING = {
    # General Purpose - x86
    "m5.large": {"vcpu": 2, "memory": 8, "price": 0.096, "arch": "x86"},
    "m5.xlarge": {"vcpu": 4, "memory": 16, "price": 0.192, "arch": "x86"},
    "m5.2xlarge": {"vcpu": 8, "memory": 32, "price": 0.384, "arch": "x86"},
    "m5.4xlarge": {"vcpu": 16, "memory": 64, "price": 0.768, "arch": "x86"},
    "m5.8xlarge": {"vcpu": 32, "memory": 128, "price": 1.536, "arch": "x86"},
    "m5.12xlarge": {"vcpu": 48, "memory": 192, "price": 2.304, "arch": "x86"},
    "m5.16xlarge": {"vcpu": 64, "memory": 256, "price": 3.072, "arch": "x86"},
    "m5.24xlarge": {"vcpu": 96, "memory": 384, "price": 4.608, "arch": "x86"},
    # General Purpose - Graviton2
    "m6g.large": {"vcpu": 2, "memory": 8, "price": 0.077, "arch": "arm64"},
    "m6g.xlarge": {"vcpu": 4, "memory": 16, "price": 0.154, "arch": "arm64"},
    "m6g.2xlarge": {"vcpu": 8, "memory": 32, "price": 0.308, "arch": "arm64"},
    "m6g.4xlarge": {"vcpu": 16, "memory": 64, "price": 0.616, "arch": "arm64"},
    "m6g.8xlarge": {"vcpu": 32, "memory": 128, "price": 1.232, "arch": "arm64"},
    "m6g.12xlarge": {"vcpu": 48, "memory": 192, "price": 1.848, "arch": "arm64"},
    "m6g.16xlarge": {"vcpu": 64, "memory": 256, "price": 2.464, "arch": "arm64"},
    # General Purpose - Graviton3
    "m7g.large": {"vcpu": 2, "memory": 8, "price": 0.081, "arch": "arm64"},
    "m7g.xlarge": {"vcpu": 4, "memory": 16, "price": 0.163, "arch": "arm64"},
    "m7g.2xlarge": {"vcpu": 8, "memory": 32, "price": 0.326, "arch": "arm64"},
    "m7g.4xlarge": {"vcpu": 16, "memory": 64, "price": 0.652, "arch": "arm64"},
    "m7g.8xlarge": {"vcpu": 32, "memory": 128, "price": 1.304, "arch": "arm64"},
    "m7g.12xlarge": {"vcpu": 48, "memory": 192, "price": 1.956, "arch": "arm64"},
    "m7g.16xlarge": {"vcpu": 64, "memory": 256, "price": 2.608, "arch": "arm64"},
    # Compute Optimized - x86
    "c5.large": {"vcpu": 2, "memory": 4, "price": 0.085, "arch": "x86"},
    "c5.xlarge": {"vcpu": 4, "memory": 8, "price": 0.170, "arch": "x86"},
    "c5.2xlarge": {"vcpu": 8, "memory": 16, "price": 0.340, "arch": "x86"},
    "c5.4xlarge": {"vcpu": 16, "memory": 32, "price": 0.680, "arch": "x86"},
    "c5.9xlarge": {"vcpu": 36, "memory": 72, "price": 1.530, "arch": "x86"},
    "c5.12xlarge": {"vcpu": 48, "memory": 96, "price": 2.040, "arch": "x86"},
    "c5.18xlarge": {"vcpu": 72, "memory": 144, "price": 3.060, "arch": "x86"},
    # Compute Optimized - Graviton2
    "c6g.large": {"vcpu": 2, "memory": 4, "price": 0.068, "arch": "arm64"},
    "c6g.xlarge": {"vcpu": 4, "memory": 8, "price": 0.136, "arch": "arm64"},
    "c6g.2xlarge": {"vcpu": 8, "memory": 16, "price": 0.272, "arch": "arm64"},
    "c6g.4xlarge": {"vcpu": 16, "memory": 32, "price": 0.544, "arch": "arm64"},
    "c6g.8xlarge": {"vcpu": 32, "memory": 64, "price": 1.088, "arch": "arm64"},
    "c6g.12xlarge": {"vcpu": 48, "memory": 96, "price": 1.632, "arch": "arm64"},
    "c6g.16xlarge": {"vcpu": 64, "memory": 128, "price": 2.176, "arch": "arm64"},
    # Compute Optimized - Graviton3
    "c7g.large": {"vcpu": 2, "memory": 4, "price": 0.072, "arch": "arm64"},
    "c7g.xlarge": {"vcpu": 4, "memory": 8, "price": 0.145, "arch": "arm64"},
    "c7g.2xlarge": {"vcpu": 8, "memory": 16, "price": 0.289, "arch": "arm64"},
    "c7g.4xlarge": {"vcpu": 16, "memory": 32, "price": 0.578, "arch": "arm64"},
    "c7g.8xlarge": {"vcpu": 32, "memory": 64, "price": 1.156, "arch": "arm64"},
    "c7g.12xlarge": {"vcpu": 48, "memory": 96, "price": 1.734, "arch": "arm64"},
    "c7g.16xlarge": {"vcpu": 64, "memory": 128, "price": 2.312, "arch": "arm64"},
    # Memory Optimized - x86
    "r5.large": {"vcpu": 2, "memory": 16, "price": 0.126, "arch": "x86"},
    "r5.xlarge": {"vcpu": 4, "memory": 32, "price": 0.252, "arch": "x86"},
    "r5.2xlarge": {"vcpu": 8, "memory": 64, "price": 0.504, "arch": "x86"},
    "r5.4xlarge": {"vcpu": 16, "memory": 128, "price": 1.008, "arch": "x86"},
    "r5.8xlarge": {"vcpu": 32, "memory": 256, "price": 2.016, "arch": "x86"},
    "r5.12xlarge": {"vcpu": 48, "memory": 384, "price": 3.024, "arch": "x86"},
    "r5.16xlarge": {"vcpu": 64, "memory": 512, "price": 4.032, "arch": "x86"},
    # Memory Optimized - Graviton2
    "r6g.large": {"vcpu": 2, "memory": 16, "price": 0.101, "arch": "arm64"},
    "r6g.xlarge": {"vcpu": 4, "memory": 32, "price": 0.202, "arch": "arm64"},
    "r6g.2xlarge": {"vcpu": 8, "memory": 64, "price": 0.403, "arch": "arm64"},
    "r6g.4xlarge": {"vcpu": 16, "memory": 128, "price": 0.806, "arch": "arm64"},
    "r6g.8xlarge": {"vcpu": 32, "memory": 256, "price": 1.613, "arch": "arm64"},
    "r6g.12xlarge": {"vcpu": 48, "memory": 384, "price": 2.419, "arch": "arm64"},
    "r6g.16xlarge": {"vcpu": 64, "memory": 512, "price": 3.226, "arch": "arm64"},
    # Memory Optimized - Graviton3
    "r7g.large": {"vcpu": 2, "memory": 16, "price": 0.106, "arch": "arm64"},
    "r7g.xlarge": {"vcpu": 4, "memory": 32, "price": 0.213, "arch": "arm64"},
    "r7g.2xlarge": {"vcpu": 8, "memory": 64, "price": 0.426, "arch": "arm64"},
    "r7g.4xlarge": {"vcpu": 16, "memory": 128, "price": 0.851, "arch": "arm64"},
    "r7g.8xlarge": {"vcpu": 32, "memory": 256, "price": 1.702, "arch": "arm64"},
    "r7g.12xlarge": {"vcpu": 48, "memory": 384, "price": 2.554, "arch": "arm64"},
    "r7g.16xlarge": {"vcpu": 64, "memory": 512, "price": 3.405, "arch": "arm64"},
    # Burstable - x86
    "t3.micro": {"vcpu": 2, "memory": 1, "price": 0.0104, "arch": "x86"},
    "t3.small": {"vcpu": 2, "memory": 2, "price": 0.0208, "arch": "x86"},
    "t3.medium": {"vcpu": 2, "memory": 4, "price": 0.0416, "arch": "x86"},
    "t3.large": {"vcpu": 2, "memory": 8, "price": 0.0832, "arch": "x86"},
    "t3.xlarge": {"vcpu": 4, "memory": 16, "price": 0.1664, "arch": "x86"},
    "t3.2xlarge": {"vcpu": 8, "memory": 32, "price": 0.3328, "arch": "x86"},
    # Burstable - Graviton2
    "t4g.micro": {"vcpu": 2, "memory": 1, "price": 0.0084, "arch": "arm64"},
    "t4g.small": {"vcpu": 2, "memory": 2, "price": 0.0168, "arch": "arm64"},
    "t4g.medium": {"vcpu": 2, "memory": 4, "price": 0.0336, "arch": "arm64"},
    "t4g.large": {"vcpu": 2, "memory": 8, "price": 0.0672, "arch": "arm64"},
    "t4g.xlarge": {"vcpu": 4, "memory": 16, "price": 0.1344, "arch": "arm64"},
    "t4g.2xlarge": {"vcpu": 8, "memory": 32, "price": 0.2688, "arch": "arm64"},
}


def find_graviton_equivalent(x86_instance):
    """Find the best Graviton equivalent for an x86 instance"""
    if x86_instance not in INSTANCE_PRICING:
        return None

    x86_spec = INSTANCE_PRICING[x86_instance]
    vcpu = x86_spec["vcpu"]
    memory = x86_spec["memory"]
    family = x86_instance.split(".")[0]  # e.g., "m5" from "m5.large"

    # Map x86 families to Graviton families
    family_map = {
        "m5": ["m7g", "m6g"],  # Prefer m7g (Graviton3)
        "m6i": ["m7g", "m6g"],
        "c5": ["c7g", "c6g"],
        "c6i": ["c7g", "c6g"],
        "r5": ["r7g", "r6g"],
        "r6i": ["r7g", "r6g"],
        "t3": ["t4g"],
        "t3a": ["t4g"],
    }

    graviton_families = family_map.get(family, ["m7g", "m6g", "c7g", "c6g", "r7g", "r6g"])

    # Find matching Graviton instance
    best_match = None
    for g_family in graviton_families:
        for inst_type, spec in INSTANCE_PRICING.items():
            if inst_type.startswith(g_family) and spec["arch"] == "arm64":
                if spec["vcpu"] == vcpu and spec["memory"] == memory:
                    if best_match is None or spec["price"] < INSTANCE_PRICING[best_match]["price"]:
                        best_match = inst_type

    return best_match


def calculate_savings(current_instance, target_instance, count=1, utilization=1.0):
    """Calculate cost savings"""
    if current_instance not in INSTANCE_PRICING or target_instance not in INSTANCE_PRICING:
        return None

    current_price = INSTANCE_PRICING[current_instance]["price"]
    target_price = INSTANCE_PRICING[target_instance]["price"]

    # Hourly cost
    current_hourly = current_price * count
    target_hourly = target_price * count
    savings_hourly = current_hourly - target_hourly

    # Daily, monthly, yearly (factoring in utilization)
    hours_per_day = 24 * utilization
    days_per_month = 30
    days_per_year = 365

    current_daily = current_hourly * hours_per_day
    target_daily = target_hourly * hours_per_day
    savings_daily = savings_hourly * hours_per_day

    current_monthly = current_daily * days_per_month
    target_monthly = target_daily * days_per_month
    savings_monthly = savings_daily * days_per_month

    current_yearly = current_daily * days_per_year
    target_yearly = target_daily * days_per_year
    savings_yearly = savings_daily * days_per_year

    savings_percent = ((current_price - target_price) / current_price) * 100

    return {
        "current_instance": current_instance,
        "target_instance": target_instance,
        "count": count,
        "utilization_percent": utilization * 100,
        "current": {
            "hourly": round(current_hourly, 4),
            "daily": round(current_daily, 2),
            "monthly": round(current_monthly, 2),
            "yearly": round(current_yearly, 2),
        },
        "target": {
            "hourly": round(target_hourly, 4),
            "daily": round(target_daily, 2),
            "monthly": round(target_monthly, 2),
            "yearly": round(target_yearly, 2),
        },
        "savings": {
            "hourly": round(savings_hourly, 4),
            "daily": round(savings_daily, 2),
            "monthly": round(savings_monthly, 2),
            "yearly": round(savings_yearly, 2),
            "percent": round(savings_percent, 2),
        },
    }


def print_cost_comparison(result):
    """Print formatted cost comparison"""
    print("\n" + "=" * 70)
    print("  AWS GRAVITON MIGRATION - COST SAVINGS CALCULATOR")
    print("=" * 70)

    print(f"\nCurrent Instance: {result['current_instance']}")
    print(f"Target Instance:  {result['target_instance']}")
    print(f"Instance Count:   {result['count']}")
    print(f"Utilization:      {result['utilization_percent']:.0f}%")

    print("\n" + "-" * 70)
    print("COST BREAKDOWN:")
    print("-" * 70)

    print(f"\nCurrent (x86) Costs:")
    print(f"  Hourly:  ${result['current']['hourly']:.4f}")
    print(f"  Daily:   ${result['current']['daily']:.2f}")
    print(f"  Monthly: ${result['current']['monthly']:.2f}")
    print(f"  Yearly:  ${result['current']['yearly']:,.2f}")

    print(f"\nTarget (Graviton) Costs:")
    print(f"  Hourly:  ${result['target']['hourly']:.4f}")
    print(f"  Daily:   ${result['target']['daily']:.2f}")
    print(f"  Monthly: ${result['target']['monthly']:.2f}")
    print(f"  Yearly:  ${result['target']['yearly']:,.2f}")

    print("\n" + "=" * 70)
    print("💰 ESTIMATED SAVINGS:")
    print("=" * 70)
    print(f"  Hourly:  ${result['savings']['hourly']:.4f}  ({result['savings']['percent']:.1f}%)")
    print(f"  Daily:   ${result['savings']['daily']:.2f}  ({result['savings']['percent']:.1f}%)")
    print(f"  Monthly: ${result['savings']['monthly']:.2f}  ({result['savings']['percent']:.1f}%)")
    print(f"  Yearly:  ${result['savings']['yearly']:,.2f}  ({result['savings']['percent']:.1f}%)")
    print("=" * 70)

    print("\nℹ️  Notes:")
    print("  • Prices are for us-east-1 region (on-demand)")
    print("  • Actual savings may vary by region")
    print("  • Reserved Instances and Savings Plans offer additional savings")
    print("  • Performance improvements may enable further downsizing")
    print("\nNext Steps:")
    print("  1. Run performance tests to validate equivalent sizing")
    print("  2. Consider Reserved Instances for 3-year commitment (up to 72% off)")
    print("  3. Use Compute Savings Plans for flexible commitments")
    print("=" * 70 + "\n")


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 cost-calculator.py <current-instance> [target-instance] [count] [utilization]")
        print("\nExamples:")
        print("  python3 cost-calculator.py m5.xlarge")
        print("  python3 cost-calculator.py m5.xlarge m6g.xlarge")
        print("  python3 cost-calculator.py c5.2xlarge c7g.2xlarge 10 0.8")
        print("\nAvailable instance types:")
        for family in ["m5", "m6g", "m7g", "c5", "c6g", "c7g", "r5", "r6g", "r7g", "t3", "t4g"]:
            instances = [k for k in INSTANCE_PRICING.keys() if k.startswith(family)]
            if instances:
                print(f"  {family}: {', '.join(sorted(instances))}")
        sys.exit(1)

    current_instance = sys.argv[1]
    target_instance = sys.argv[2] if len(sys.argv) > 2 else None
    count = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    utilization = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0

    # Validate current instance
    if current_instance not in INSTANCE_PRICING:
        print(f"Error: Unknown instance type: {current_instance}")
        print("Use one of:", ", ".join(sorted(INSTANCE_PRICING.keys())))
        sys.exit(1)

    # Auto-detect target instance if not provided
    if not target_instance:
        target_instance = find_graviton_equivalent(current_instance)
        if not target_instance:
            print(f"Error: Could not find Graviton equivalent for {current_instance}")
            sys.exit(1)
        print(f"Auto-detected target instance: {target_instance}")

    # Validate target instance
    if target_instance not in INSTANCE_PRICING:
        print(f"Error: Unknown instance type: {target_instance}")
        sys.exit(1)

    # Calculate savings
    result = calculate_savings(current_instance, target_instance, count, utilization)

    # Print results
    print_cost_comparison(result)

    # Save JSON output
    output_file = "cost-analysis.json"
    with open(output_file, "w") as f:
        json.dump(result, f, indent=2)
    print(f"Detailed analysis saved to: {output_file}\n")


if __name__ == "__main__":
    main()
