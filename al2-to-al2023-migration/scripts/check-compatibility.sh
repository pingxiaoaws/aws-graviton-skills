#!/bin/bash

# EKS AL2 to AL2023 兼容性检查脚本
# 使用方法：./check-compatibility.sh

set -e

echo "=== EKS AL2 to AL2023 兼容性检查 ==="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查结果计数
PASSED=0
WARNINGS=0
FAILED=0

# 1. 检查 Kubernetes 版本
echo "[1/6] 检查 Kubernetes 版本..."
K8S_VERSION=$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}' | sed 's/v//')
K8S_MAJOR=$(echo $K8S_VERSION | cut -d. -f1)
K8S_MINOR=$(echo $K8S_VERSION | cut -d. -f2)

if [ "$K8S_MINOR" -ge 23 ]; then
    echo -e "${GREEN}✅ Kubernetes 版本: v$K8S_VERSION (支持 AL2023)${NC}"
    ((PASSED++))
else
    echo -e "${RED}❌ Kubernetes 版本: v$K8S_VERSION (建议升级到 1.23+)${NC}"
    ((FAILED++))
fi
echo ""

# 2. 检查 VPC CNI 版本
echo "[2/6] 检查 VPC CNI 版本..."
CNI_VERSION=$(kubectl describe daemonset aws-node -n kube-system 2>/dev/null | grep "Image:" | grep amazon-k8s-cni | awk -F: '{print $3}')
if [ -z "$CNI_VERSION" ]; then
    echo -e "${YELLOW}⚠️  无法检测 VPC CNI 版本${NC}"
    ((WARNINGS++))
else
    # 简单版本比较 (假设格式为 v1.x.x)
    CNI_MINOR=$(echo $CNI_VERSION | sed 's/v//' | cut -d. -f2)
    if [ "$CNI_MINOR" -ge 16 ]; then
        echo -e "${GREEN}✅ VPC CNI 版本: $CNI_VERSION (>= v1.16.2)${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌ VPC CNI 版本: $CNI_VERSION (需要 >= v1.16.2)${NC}"
        echo "   升级命令:"
        echo "   kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/release-1.18/config/master/aws-k8s-cni.yaml"
        ((FAILED++))
    fi
fi
echo ""

# 3. 检查 Java 应用
echo "[3/6] 检查 Java 应用 cgroupv2 兼容性..."
JAVA_PODS=$(kubectl get pods --all-namespaces -o json | \
    jq -r '.items[] | select(.spec.containers[].image | test("java|jdk|jre|openjdk")) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null)

if [ -z "$JAVA_PODS" ]; then
    echo -e "${GREEN}✅ 未检测到 Java 应用${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠️  检测到 Java 应用:${NC}"
    echo "$JAVA_PODS" | head -5
    if [ $(echo "$JAVA_PODS" | wc -l) -gt 5 ]; then
        echo "   ... 还有 $(($(echo "$JAVA_PODS" | wc -l) - 5)) 个"
    fi
    echo ""
    echo "   请确保 JDK 版本支持 cgroupv2:"
    echo "   - JDK 8  >= 8u372"
    echo "   - JDK 11 >= 11.0.16"
    echo "   - JDK 15+"
    echo ""
    echo "   验证方法: kubectl exec <pod> -- java -version"
    ((WARNINGS++))
fi
echo ""

# 4. 检查 hostNetwork Pod (IMDSv2)
echo "[4/6] 检查 hostNetwork Pod (IMDSv2 要求)..."
HOSTNET_PODS=$(kubectl get pods --all-namespaces -o json | \
    jq -r '.items[] | select(.spec.hostNetwork==true) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null)

if [ -z "$HOSTNET_PODS" ]; then
    echo -e "${GREEN}✅ 未检测到 hostNetwork Pod${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠️  检测到 hostNetwork Pod (需要配置 IMDSv2 hop limit):${NC}"
    echo "$HOSTNET_PODS" | head -5
    if [ $(echo "$HOSTNET_PODS" | wc -l) -gt 5 ]; then
        echo "   ... 还有 $(($(echo "$HOSTNET_PODS" | wc -l) - 5)) 个"
    fi
    echo ""
    echo "   特别需要检查的组件:"
    echo "   - aws-load-balancer-controller"
    echo "   - cluster-autoscaler"
    echo "   - ebs-csi-driver"
    echo "   - efs-csi-driver"
    ((WARNINGS++))
fi
echo ""

# 5. 检查关键控制器版本
echo "[5/6] 检查关键控制器..."

# AWS Load Balancer Controller
ALB_VERSION=$(kubectl get deployment -n kube-system aws-load-balancer-controller -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | awk -F: '{print $2}')
if [ -z "$ALB_VERSION" ]; then
    echo -e "${GREEN}✅ 未安装 AWS Load Balancer Controller${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠️  AWS Load Balancer Controller: $ALB_VERSION${NC}"
    echo "   需要在节点启动模板中配置 IMDSv2 hop limit = 2"
    echo "   MetadataOptions: {HttpPutResponseHopLimit: 2}"
    ((WARNINGS++))
fi

# EBS CSI Driver
EBS_CSI=$(kubectl get daemonset -n kube-system ebs-csi-node 2>/dev/null)
if [ -z "$EBS_CSI" ]; then
    echo -e "${GREEN}✅ 未安装 EBS CSI Driver${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠️  检测到 EBS CSI Driver${NC}"
    echo "   确保版本 >= v1.16.0 以支持 IMDSv2"
    ((WARNINGS++))
fi
echo ""

# 6. 检查当前节点 OS
echo "[6/6] 检查当前节点 OS 分布..."
echo "节点 OS 版本:"
kubectl get nodes -o custom-columns=NAME:.metadata.name,OS:.status.nodeInfo.osImage,KERNEL:.status.nodeInfo.kernelVersion | grep -E "NAME|Amazon"
echo ""

AL2_COUNT=$(kubectl get nodes -o json | jq -r '.items[].status.nodeInfo.osImage' | grep -c "Amazon Linux 2" || true)
AL2023_COUNT=$(kubectl get nodes -o json | jq -r '.items[].status.nodeInfo.osImage' | grep -c "Amazon Linux 2023" || true)

echo "统计:"
echo "  AL2 节点: $AL2_COUNT"
echo "  AL2023 节点: $AL2023_COUNT"
echo ""

# 汇总
echo "=== 检查结果汇总 ==="
echo -e "${GREEN}通过: $PASSED${NC}"
echo -e "${YELLOW}警告: $WARNINGS${NC}"
echo -e "${RED}失败: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ 所有检查通过，可以开始迁移！${NC}"
    exit 0
elif [ $FAILED -eq 0 ]; then
    echo -e "${YELLOW}⚠️  有 $WARNINGS 个警告项，请检查后再迁移${NC}"
    exit 0
else
    echo -e "${RED}❌ 有 $FAILED 个失败项，请修复后再迁移${NC}"
    exit 1
fi
