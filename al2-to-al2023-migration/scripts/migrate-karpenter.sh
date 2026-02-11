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

# 1. 备份现有配置
echo "[1/4] 备份现有配置..."
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
kubectl get ec2nodeclass $NODECLASS_NAME -o yaml > "ec2nodeclass-backup-${BACKUP_DATE}.yaml"
kubectl get nodepool -o yaml > "nodepool-backup-${BACKUP_DATE}.yaml"
echo "✅ 备份已保存到当前目录"
echo ""

# 2. 显示当前 AMI 配置
echo "[2/4] 当前 AMI 配置:"
kubectl get ec2nodeclass $NODECLASS_NAME -o jsonpath='{.spec.amiSelectorTerms}' | jq .
echo ""

# 3. 更新 EC2NodeClass
read -p "确认更新到 AL2023? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "取消迁移"
    exit 0
fi

echo "[3/4] 更新 EC2NodeClass 到 AL2023..."
kubectl patch ec2nodeclass $NODECLASS_NAME --type='json' -p='[
  {"op": "replace", "path": "/spec/amiSelectorTerms/0/alias", "value": "al2023@latest"}
]'
echo "✅ EC2NodeClass 已更新"
echo ""

# 4. 等待 drift 检测
echo "[4/4] 等待 Karpenter drift 检测..."
echo "Karpenter 会自动检测配置变更并逐步替换节点"
echo "这个过程可能需要 10-30 分钟"
echo ""
echo "监控命令："
echo "  kubectl get nodes -o wide"
echo "  kubectl logs -f -n karpenter -l app.kubernetes.io/name=karpenter"
echo ""

# 可选：持续监控
read -p "开始监控节点更新? (yes/no) " -r
echo
if [[ $REPLY =~ ^yes$ ]]; then
    echo "按 Ctrl+C 停止监控"
    watch -n 10 'kubectl get nodes -o custom-columns=NAME:.metadata.name,OS:.status.nodeInfo.osImage,VERSION:.status.nodeInfo.kernelVersion,STATUS:.status.conditions[3].type'
fi

echo ""
echo "=== 迁移配置完成 ==="
echo "Karpenter 会自动完成节点替换"
echo ""
echo "验证命令："
echo "  kubectl get nodes -o wide"
echo "  kubectl get pods --all-namespaces -o wide"
echo "  kubectl get events --sort-by='.lastTimestamp' | grep -i karpenter"
