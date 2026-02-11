#!/bin/bash
set -e

# EKS AL2 to AL2023 自动迁移脚本 (Karpenter)
# 使用方法：./migrate-karpenter.sh <cluster-name> <ec2nodeclass-name>

CLUSTER_NAME="${1:-my-cluster}"
NODECLASS_NAME="${2:-default}"

echo "=== EKS AL2 to AL2023 迁移脚本 (Karpenter) ==="
echo "集群名称: $CLUSTER_NAME"
echo "EC2NodeClass: $NODECLASS_NAME"
echo ""

# 依赖检查
for cmd in kubectl jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ $cmd 未安装"
        exit 1
    fi
done

# 检查 EC2NodeClass 是否存在
if ! kubectl get ec2nodeclass "$NODECLASS_NAME" &> /dev/null; then
    echo "❌ EC2NodeClass '$NODECLASS_NAME' 不存在"
    echo "可用的 EC2NodeClass:"
    kubectl get ec2nodeclass -o name 2>/dev/null || echo "  (无)"
    exit 1
fi

# 1. 备份现有配置
echo "[1/4] 备份现有配置..."
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
kubectl get ec2nodeclass "$NODECLASS_NAME" -o yaml > "ec2nodeclass-backup-${BACKUP_DATE}.yaml"
kubectl get nodepool -o yaml > "nodepool-backup-${BACKUP_DATE}.yaml"
echo "✅ 备份已保存:"
echo "   ec2nodeclass-backup-${BACKUP_DATE}.yaml"
echo "   nodepool-backup-${BACKUP_DATE}.yaml"
echo ""

# 2. 显示当前 AMI 配置
echo "[2/4] 当前 AMI 配置:"
CURRENT_AMI=$(kubectl get ec2nodeclass "$NODECLASS_NAME" -o jsonpath='{.spec.amiSelectorTerms}')
echo "$CURRENT_AMI" | jq .
echo ""

# 检查是否已经是 AL2023
if echo "$CURRENT_AMI" | grep -q "al2023"; then
    echo "⚠️  EC2NodeClass 已经配置为 AL2023"
    read -p "仍然继续? (yes/no) " -r
    echo
    if [[ ! $REPLY =~ ^yes$ ]]; then
        echo "取消迁移"
        exit 0
    fi
fi

# 3. 更新 EC2NodeClass
read -p "确认更新到 AL2023? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "取消迁移"
    exit 0
fi

echo "[3/4] 更新 EC2NodeClass 到 AL2023..."

# 注意: 如果有自定义 userData，需要同步更新为 AL2023 格式 (MIME + NodeConfig)
# AL2 的 bootstrap.sh 格式在 AL2023 上不工作
HAS_USERDATA=$(kubectl get ec2nodeclass "$NODECLASS_NAME" -o jsonpath='{.spec.userData}')
if [ -n "$HAS_USERDATA" ]; then
    echo ""
    echo "⚠️  检测到自定义 userData"
    echo "   AL2023 使用 MIME + NodeConfig 格式，与 AL2 的 bootstrap.sh 不兼容"
    echo "   请确认 userData 已更新为 AL2023 格式后再继续"
    echo "   参考: SKILL.md 中的 'AL2023 用户数据格式' 章节"
    echo ""
    read -p "userData 已更新为 AL2023 格式? (yes/no) " -r
    echo
    if [[ ! $REPLY =~ ^yes$ ]]; then
        echo "请先更新 userData 后再运行此脚本"
        echo "回滚: kubectl apply -f ec2nodeclass-backup-${BACKUP_DATE}.yaml"
        exit 0
    fi
fi

kubectl patch ec2nodeclass "$NODECLASS_NAME" --type='json' -p='[
  {"op": "replace", "path": "/spec/amiSelectorTerms/0/alias", "value": "al2023@latest"}
]'
echo "✅ EC2NodeClass 已更新"
echo ""

# 4. 等待 drift 检测
echo "[4/4] Karpenter drift 检测..."
echo "Karpenter 会自动检测配置变更并逐步替换节点"
echo ""
echo "可通过 NodePool disruption budgets 控制滚动速度:"
echo "  spec.disruption.budgets[].nodes: '2'  # 每次最多替换 2 个节点"
echo ""
echo "监控命令："
echo "  kubectl get nodes -o wide -w"
echo "  kubectl logs -f -n karpenter -l app.kubernetes.io/name=karpenter"
echo "  kubectl get events --sort-by='.lastTimestamp' | grep -i karpenter"
echo ""

read -p "开始监控节点更新? (yes/no) " -r
echo
if [[ $REPLY =~ ^yes$ ]]; then
    echo "按 Ctrl+C 停止监控"
    watch -n 10 'kubectl get nodes -o custom-columns=NAME:.metadata.name,OS:.status.nodeInfo.osImage,VERSION:.status.nodeInfo.kernelVersion,STATUS:.status.conditions[-1:].type'
fi

echo ""
echo "=== 迁移配置完成 ==="
echo ""
echo "回滚方法:"
echo "  kubectl apply -f ec2nodeclass-backup-${BACKUP_DATE}.yaml"
