#!/bin/bash

# EKS AL2 to AL2023 兼容性检查脚本
# 使用方法：./check-compatibility.sh

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

pass()  { PASSED=$((PASSED + 1)); }
warn()  { WARNINGS=$((WARNINGS + 1)); }
fail()  { FAILED=$((FAILED + 1)); }

# 前置依赖检查
for cmd in kubectl jq aws; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}❌ $cmd 未安装，请先安装${NC}"
        exit 1
    fi
done

# 1. 检查 Kubernetes 版本
echo "[1/7] 检查 Kubernetes 版本..."
K8S_VERSION=$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion' | sed 's/v//')
if [ -z "$K8S_VERSION" ] || [ "$K8S_VERSION" = "null" ]; then
    echo -e "${RED}❌ 无法获取 Kubernetes 版本，请检查 kubectl 连接${NC}"
    fail
else
    K8S_MINOR=$(echo "$K8S_VERSION" | cut -d. -f2)
    if [ "$K8S_MINOR" -ge 33 ]; then
        echo -e "${RED}❌ Kubernetes 版本: v$K8S_VERSION (1.33+ 已不再提供 AL2 AMI，会自动使用 AL2023)${NC}"
        fail
    elif [ "$K8S_MINOR" -ge 23 ]; then
        echo -e "${GREEN}✅ Kubernetes 版本: v$K8S_VERSION (支持 AL2023)${NC}"
        pass
    else
        echo -e "${RED}❌ Kubernetes 版本: v$K8S_VERSION (建议升级到 1.23+)${NC}"
        fail
    fi
fi
echo ""

# 2. 检查 VPC CNI 版本
echo "[2/7] 检查 VPC CNI 版本..."
CNI_IMAGE=$(kubectl get daemonset aws-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
CNI_VERSION=$(echo "$CNI_IMAGE" | awk -F: '{print $NF}')
if [ -z "$CNI_VERSION" ] || [ "$CNI_VERSION" = "$CNI_IMAGE" ]; then
    echo -e "${YELLOW}⚠️  无法检测 VPC CNI 版本${NC}"
    warn
else
    CNI_MINOR=$(echo "$CNI_VERSION" | sed 's/v//' | cut -d. -f2)
    CNI_PATCH=$(echo "$CNI_VERSION" | sed 's/v//' | cut -d. -f3 | cut -d- -f1)
    if [ "$CNI_MINOR" -gt 16 ] || { [ "$CNI_MINOR" -eq 16 ] && [ "$CNI_PATCH" -ge 2 ]; }; then
        echo -e "${GREEN}✅ VPC CNI 版本: $CNI_VERSION (>= v1.16.2)${NC}"
        pass
    else
        echo -e "${RED}❌ VPC CNI 版本: $CNI_VERSION (需要 >= v1.16.2)${NC}"
        echo "   升级方式: EKS 控制台 → Add-ons → VPC CNI → 更新版本"
        echo "   或: aws eks update-addon --cluster-name <cluster> --addon-name vpc-cni --addon-version <version>"
        fail
    fi
fi
echo ""

# 3. 检查 Java 应用
echo "[3/7] 检查 Java 应用 cgroupv2 兼容性..."
JAVA_PODS=$(kubectl get pods --all-namespaces -o json 2>/dev/null | \
    jq -r '.items[] | select(.spec.containers[].image | test("java|jdk|jre|openjdk|corretto|zulu|temurin")) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null)

if [ -z "$JAVA_PODS" ]; then
    echo -e "${GREEN}✅ 未检测到 Java 应用（基于镜像名匹配）${NC}"
    pass
else
    echo -e "${YELLOW}⚠️  检测到可能的 Java 应用:${NC}"
    echo "$JAVA_PODS" | head -5
    JAVA_COUNT=$(echo "$JAVA_PODS" | wc -l | tr -d ' ')
    if [ "$JAVA_COUNT" -gt 5 ]; then
        echo "   ... 还有 $((JAVA_COUNT - 5)) 个"
    fi
    echo ""
    echo "   AL2023 使用 cgroupv2，旧版 JDK 不兼容会导致 OOM"
    echo "   必须满足以下最低版本:"
    echo "   - JDK 8  >= 8u372"
    echo "   - JDK 11 >= 11.0.16"
    echo "   - JDK 15+"
    echo ""
    echo "   验证: kubectl exec <pod> -- java -version"
    warn
fi
echo ""

# 4. 检查 hostNetwork Pod (IMDSv2)
echo "[4/7] 检查 hostNetwork Pod (IMDSv2 要求)..."
HOSTNET_PODS=$(kubectl get pods --all-namespaces -o json 2>/dev/null | \
    jq -r '.items[] | select(.spec.hostNetwork==true) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null)

if [ -z "$HOSTNET_PODS" ]; then
    echo -e "${GREEN}✅ 未检测到 hostNetwork Pod${NC}"
    pass
else
    echo -e "${YELLOW}⚠️  检测到 hostNetwork Pod (需要配置 IMDSv2 hop limit = 2):${NC}"
    echo "$HOSTNET_PODS" | head -5
    HN_COUNT=$(echo "$HOSTNET_PODS" | wc -l | tr -d ' ')
    if [ "$HN_COUNT" -gt 5 ]; then
        echo "   ... 还有 $((HN_COUNT - 5)) 个"
    fi
    echo ""
    echo "   需要检查的组件及替代方案:"
    echo "   - aws-load-balancer-controller → 通过 --aws-region, --aws-vpc-id 显式指定"
    echo "   - cluster-autoscaler → 使用 IRSA 或 EKS Pod Identity"
    echo "   - ebs-csi-driver → v1.45+ 使用 --metadata-sources=k8s"
    echo "   - efs-csi-driver → 使用 IRSA 或 EKS Pod Identity"
    echo ""
    echo "   推荐: 使用 EKS Pod Identity 替代 IMDS 依赖"
    warn
fi
echo ""

# 5. 检查关键控制器版本
echo "[5/7] 检查关键控制器..."

# AWS Load Balancer Controller
ALB_VERSION=$(kubectl get deployment -n kube-system aws-load-balancer-controller -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | awk -F: '{print $2}')
if [ -z "$ALB_VERSION" ]; then
    echo "  AWS Load Balancer Controller: 未安装"
else
    echo -e "${YELLOW}⚠️  AWS Load Balancer Controller: $ALB_VERSION${NC}"
    echo "   方案 1 (推荐): 通过 Helm values 显式指定 region 和 vpcId"
    echo "   方案 2: 启动模板设置 HttpPutResponseHopLimit = 2"
    warn
fi

# EBS CSI Driver
EBS_CSI_VERSION=$(kubectl get daemonset -n kube-system ebs-csi-node -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | awk -F: '{print $2}')
if [ -z "$EBS_CSI_VERSION" ]; then
    echo "  EBS CSI Driver: 未安装"
else
    echo -e "${YELLOW}⚠️  EBS CSI Driver: $EBS_CSI_VERSION${NC}"
    echo "   v1.45+ 支持 --metadata-sources=k8s 避免 IMDS 依赖"
    warn
fi

# Cluster Autoscaler
CA_VERSION=$(kubectl get deployment -n kube-system cluster-autoscaler -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | awk -F: '{print $2}')
if [ -z "$CA_VERSION" ]; then
    echo "  Cluster Autoscaler: 未安装"
else
    echo -e "${YELLOW}⚠️  Cluster Autoscaler: $CA_VERSION${NC}"
    echo "   确保使用 IRSA 或 EKS Pod Identity"
    warn
fi
echo ""

# 6. 检查 GPU/Neuron 工作负载
echo "[6/7] 检查 GPU/Neuron 工作负载..."
GPU_PODS=$(kubectl get pods --all-namespaces -o json 2>/dev/null | \
    jq -r '.items[] | select(.spec.containers[].resources.limits["nvidia.com/gpu"] != null) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null)
NEURON_PODS=$(kubectl get pods --all-namespaces -o json 2>/dev/null | \
    jq -r '.items[] | select(.spec.containers[].resources.limits["aws.amazon.com/neuron"] != null or .spec.containers[].resources.limits["aws.amazon.com/neuroncore"] != null) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null)

if [ -z "$GPU_PODS" ] && [ -z "$NEURON_PODS" ]; then
    echo -e "${GREEN}✅ 未检测到 GPU/Neuron 工作负载${NC}"
    pass
else
    if [ -n "$GPU_PODS" ]; then
        echo -e "${YELLOW}⚠️  检测到 NVIDIA GPU 工作负载:${NC}"
        echo "$GPU_PODS" | head -3
        echo ""
        echo "   注意: AL2023 使用 R580 驱动 (CUDA 13)，AL2 使用 R570 (CUDA 12)"
        echo "   如果容器镜像基于 CUDA 12，需要升级到 CUDA 13 或设置 NVIDIA_DISABLE_REQUIRE=1"
        warn
    fi
    if [ -n "$NEURON_PODS" ]; then
        echo -e "${YELLOW}⚠️  检测到 AWS Neuron 工作负载:${NC}"
        echo "$NEURON_PODS" | head -3
        echo ""
        echo "   Neuron 运行时 (aws-neuronx-runtime-lib) 从 2.20 起不再支持 AL2"
        echo "   需要使用容器化部署 (基于 AL2023/Ubuntu 的容器镜像)"
        warn
    fi
fi
echo ""

# 7. 检查当前节点 OS
echo "[7/7] 检查当前节点 OS 分布..."
echo "节点 OS 版本:"
kubectl get nodes -o custom-columns=NAME:.metadata.name,OS:.status.nodeInfo.osImage,KERNEL:.status.nodeInfo.kernelVersion
echo ""

# 使用 jq 过滤确保精确匹配，避免 AL2023 被计入 AL2
AL2_COUNT=$(kubectl get nodes -o json 2>/dev/null | jq '[.items[].status.nodeInfo.osImage | select(test("Amazon Linux 2") and (test("2023") | not))] | length')
AL2023_COUNT=$(kubectl get nodes -o json 2>/dev/null | jq '[.items[].status.nodeInfo.osImage | select(test("Amazon Linux 2023"))] | length')
BR_COUNT=$(kubectl get nodes -o json 2>/dev/null | jq '[.items[].status.nodeInfo.osImage | select(test("Bottlerocket"))] | length')

echo "统计:"
echo "  AL2 节点: $AL2_COUNT"
echo "  AL2023 节点: $AL2023_COUNT"
echo "  Bottlerocket 节点: $BR_COUNT"
echo ""

if [ "$AL2_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✅ 没有 AL2 节点需要迁移${NC}"
    pass
else
    echo -e "${YELLOW}⚠️  有 $AL2_COUNT 个 AL2 节点需要迁移${NC}"
    warn
fi
echo ""

# 汇总
echo "=========================================="
echo "  检查结果汇总"
echo "=========================================="
echo -e "${GREEN}  通过: $PASSED${NC}"
echo -e "${YELLOW}  警告: $WARNINGS${NC}"
echo -e "${RED}  失败: $FAILED${NC}"
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
