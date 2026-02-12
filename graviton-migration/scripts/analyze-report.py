#!/usr/bin/env python3
"""
AWS Graviton Migration - Report Analyzer
Parses Porting Advisor reports and provides actionable insights
"""

import sys
import json
import re
from pathlib import Path
from html.parser import HTMLParser


class PortingAdvisorParser(HTMLParser):
    """Parse HTML report from Porting Advisor"""

    def __init__(self):
        super().__init__()
        self.issues = []
        self.current_issue = {}
        self.in_issue = False
        self.current_tag = None
        self.severity_counts = {"high": 0, "medium": 0, "low": 0, "info": 0}

    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)
        if tag == "div" and attrs_dict.get("class") == "issue":
            self.in_issue = True
            self.current_issue = {}

        if self.in_issue:
            if "severity" in attrs_dict.get("class", ""):
                self.current_issue["severity"] = attrs_dict.get("data-severity", "info")
            self.current_tag = tag

    def handle_data(self, data):
        data = data.strip()
        if self.in_issue and data:
            if self.current_tag == "h3":
                self.current_issue["title"] = data
            elif self.current_tag == "p":
                if "description" not in self.current_issue:
                    self.current_issue["description"] = data
                else:
                    self.current_issue["description"] += " " + data
            elif self.current_tag == "code":
                if "location" not in self.current_issue:
                    self.current_issue["location"] = data

    def handle_endtag(self, tag):
        if tag == "div" and self.in_issue:
            if self.current_issue:
                severity = self.current_issue.get("severity", "info")
                self.severity_counts[severity] += 1
                self.issues.append(self.current_issue)
            self.in_issue = False
            self.current_issue = {}
        self.current_tag = None


def parse_html_report(html_file):
    """Parse HTML report and extract issues"""
    try:
        with open(html_file, "r", encoding="utf-8") as f:
            html_content = f.read()

        parser = PortingAdvisorParser()
        parser.feed(html_content)
        return parser.issues, parser.severity_counts
    except Exception as e:
        print(f"Error parsing HTML report: {e}")
        return [], {}


def parse_text_report(text_content):
    """Parse plain text report"""
    issues = []
    severity_counts = {"high": 0, "medium": 0, "low": 0, "info": 0}

    # Common patterns to detect
    patterns = {
        "python_version": r"Python version (\d+\.\d+)",
        "pip_version": r"pip version (\d+\.\d+)",
        "java_version": r"Java version (\d+)",
        "go_version": r"Go version (\d+\.\d+)",
        "dependency": r"([\w\-]+)\s+(\d+\.\d+[\.\d+]*)\s+-\s+(.+)",
        "inline_asm": r"inline assembly.*?(\w+\.[ch])",
        "intrinsic": r"intrinsic.*?(\w+\.c)",
    }

    for line in text_content.split("\n"):
        line = line.strip()

        # Check for dependency issues
        if "not supported" in line.lower() or "upgrade" in line.lower():
            match = re.search(patterns["dependency"], line)
            if match:
                issues.append(
                    {
                        "type": "dependency",
                        "severity": "high" if "not supported" in line.lower() else "medium",
                        "package": match.group(1),
                        "version": match.group(2),
                        "description": match.group(3),
                    }
                )
                severity = "high" if "not supported" in line.lower() else "medium"
                severity_counts[severity] += 1

        # Check for inline assembly
        if "inline assembly" in line.lower():
            issues.append(
                {
                    "type": "inline_assembly",
                    "severity": "high",
                    "description": line,
                }
            )
            severity_counts["high"] += 1

        # Check for intrinsics
        if "intrinsic" in line.lower():
            issues.append(
                {
                    "type": "intrinsic",
                    "severity": "high",
                    "description": line,
                }
            )
            severity_counts["high"] += 1

    return issues, severity_counts


def categorize_issues(issues):
    """Categorize issues by type"""
    categories = {
        "dependencies": [],
        "code": [],
        "runtime": [],
        "compiler": [],
        "other": [],
    }

    for issue in issues:
        issue_type = issue.get("type", "other")
        title = issue.get("title", "").lower()
        desc = issue.get("description", "").lower()

        if "dependency" in issue_type or "requirement" in title or "pom.xml" in desc:
            categories["dependencies"].append(issue)
        elif "inline assembly" in desc or "intrinsic" in desc or ".c" in desc:
            categories["code"].append(issue)
        elif "python" in title or "java" in title or "go" in title:
            categories["runtime"].append(issue)
        elif "compiler" in desc or "gcc" in desc or "clang" in desc:
            categories["compiler"].append(issue)
        else:
            categories["other"].append(issue)

    return categories


def generate_recommendations(issues, categories):
    """Generate fix recommendations based on issues"""
    recommendations = []

    # Dependency issues
    if categories["dependencies"]:
        recommendations.append(
            {
                "category": "Dependencies",
                "priority": "HIGH",
                "actions": [
                    "Update all dependencies to latest versions supporting ARM64",
                    "Check package repositories for ARM64 wheel availability (Python)",
                    "Verify JAR files have ARM64 native libraries (Java)",
                    "Consider alternative packages if originals don't support ARM64",
                ],
                "commands": [
                    "pip install --upgrade package-name  # Python",
                    "mvn versions:use-latest-versions  # Java Maven",
                    "go get -u ./...  # Go",
                ],
            }
        )

    # Code issues (assembly, intrinsics)
    if categories["code"]:
        recommendations.append(
            {
                "category": "Code Changes",
                "priority": "HIGH",
                "actions": [
                    "Add architecture-specific code branches (#ifdef __aarch64__)",
                    "Replace x86 intrinsics with ARM NEON equivalents",
                    "Use compiler auto-vectorization instead of manual intrinsics",
                    "Consider portable SIMD libraries (e.g., Highway, xsimd)",
                ],
                "examples": [
                    "#ifdef __x86_64__\n  // x86 code\n#elif __aarch64__\n  // ARM64 code\n#endif",
                ],
            }
        )

    # Runtime version issues
    if categories["runtime"]:
        recommendations.append(
            {
                "category": "Runtime Versions",
                "priority": "MEDIUM",
                "actions": [
                    "Upgrade Python to 3.8+ for better ARM64 support",
                    "Use Amazon Corretto (recommended JDK for Graviton)",
                    "Upgrade Go to 1.16+ for native ARM64 support",
                ],
                "resources": [
                    "https://docs.aws.amazon.com/corretto/",
                    "https://www.python.org/downloads/",
                ],
            }
        )

    # No issues found
    if not issues:
        recommendations.append(
            {
                "category": "Ready to Migrate",
                "priority": "INFO",
                "actions": [
                    "No blocking issues detected",
                    "Proceed with testing on Graviton instance",
                    "Run comprehensive integration tests",
                    "Monitor performance metrics",
                ],
            }
        )

    return recommendations


def print_summary(issues, severity_counts, categories, recommendations):
    """Print formatted analysis summary"""
    print("\n" + "=" * 70)
    print("  AWS GRAVITON MIGRATION - COMPATIBILITY ANALYSIS")
    print("=" * 70)

    # Overall status
    total_issues = len(issues)
    if total_issues == 0:
        print("\n✓ GOOD NEWS: No compatibility issues detected!")
        print("  Your codebase appears ready for Graviton migration.")
    else:
        print(f"\n⚠ Found {total_issues} compatibility issue(s)")

    # Severity breakdown
    print("\nSEVERITY BREAKDOWN:")
    print(f"  🔴 High:   {severity_counts.get('high', 0)} (blocking issues)")
    print(f"  🟠 Medium: {severity_counts.get('medium', 0)} (recommended fixes)")
    print(f"  🟡 Low:    {severity_counts.get('low', 0)} (optional improvements)")
    print(f"  ℹ️  Info:   {severity_counts.get('info', 0)} (informational)")

    # Category breakdown
    print("\nISSUE CATEGORIES:")
    for cat_name, cat_issues in categories.items():
        if cat_issues:
            print(f"  • {cat_name.capitalize()}: {len(cat_issues)}")

    # Top issues
    if issues:
        print("\nTOP ISSUES TO ADDRESS:")
        high_priority = [i for i in issues if i.get("severity") == "high"][:5]
        for idx, issue in enumerate(high_priority, 1):
            title = issue.get("title", issue.get("description", "Unknown issue"))[:60]
            print(f"  {idx}. {title}")

    # Recommendations
    print("\n" + "-" * 70)
    print("RECOMMENDED ACTIONS:")
    print("-" * 70)
    for rec in recommendations:
        print(f"\n[{rec['priority']}] {rec['category']}")
        for action in rec.get("actions", []):
            print(f"  → {action}")

        if "commands" in rec:
            print("\n  Commands:")
            for cmd in rec["commands"]:
                print(f"    $ {cmd}")

        if "examples" in rec:
            print("\n  Example:")
            for ex in rec["examples"]:
                print("    " + ex.replace("\n", "\n    "))

    # Next steps
    print("\n" + "=" * 70)
    print("NEXT STEPS:")
    print("=" * 70)
    print("1. Address high-priority issues first")
    print("2. Update dependencies to ARM64-compatible versions")
    print("3. Test application on Graviton instance (m6g/c6g/r6g)")
    print("4. Run performance benchmarks")
    print("5. Monitor for runtime issues")
    print("\nUse: /graviton-migration plan  to generate detailed migration plan")
    print("=" * 70 + "\n")


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 analyze-report.py <report-file>")
        print("  report-file: Path to Porting Advisor HTML or text report")
        sys.exit(1)

    report_file = sys.argv[1]

    if not Path(report_file).exists():
        print(f"Error: Report file not found: {report_file}")
        sys.exit(1)

    print(f"Analyzing report: {report_file}")

    # Determine file type and parse accordingly
    if report_file.endswith(".html"):
        issues, severity_counts = parse_html_report(report_file)
    else:
        with open(report_file, "r") as f:
            content = f.read()
        issues, severity_counts = parse_text_report(content)

    # Categorize issues
    categories = categorize_issues(issues)

    # Generate recommendations
    recommendations = generate_recommendations(issues, categories)

    # Print summary
    print_summary(issues, severity_counts, categories, recommendations)

    # Save JSON report
    output_json = report_file.replace(".html", "").replace(".txt", "") + "-analysis.json"
    analysis = {
        "total_issues": len(issues),
        "severity_counts": severity_counts,
        "categories": {k: len(v) for k, v in categories.items()},
        "issues": issues,
        "recommendations": recommendations,
    }

    with open(output_json, "w") as f:
        json.dump(analysis, f, indent=2)

    print(f"Detailed analysis saved to: {output_json}")


if __name__ == "__main__":
    main()
