#!/bin/bash
set -e

# EKS AL2 to AL2023 蓝绿迁移脚本 (托管节点组)
# 使用方法：./migrate-managed-nodegroup-bluegreen.sh <cluster-name> <old-nodegroup> <new-nodegroup> <region>

CLUSTER_NAME="${1:-my-cluster}"
OLD_NG="${2:-al2-ng}"
NEW_NG="${3:-al2023-ng}"
REGION="${4:-us-west-2}"

echo "=== EKS AL2 to AL2023 蓝绿迁移脚本 ==="
echo "集群名称: $CLUSTER_NAME"
echo "旧节点组: $OLD_NG"
echo "新节点组: $NEW_NG"
echo "AWS 区域: $REGION"
echo ""

# 依赖检查
for cmd in kubectl eksctl aws jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ $cmd 未安装"
        [ "$cmd" = "eksctl" ] && echo "   安装: https://eksctl.io/"
        exit 1
    fi
done

# 检查旧节点组是否存在
if ! aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$OLD_NG" --region "$REGION" &> /dev/null; then
    echo "❌ 节点组 '$OLD_NG' 不存在，请检查名称和区域"
    exit 1
fi

# 确认操作
read -p "确认开始迁移? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "取消迁移"
    exit 0
fi

# 1. 获取旧节点组配置
echo "[1/6] 获取旧节点组配置..."
OLD_NG_INFO=$(aws eks describe-nodegroup \
    --cluster-name "$CLUSTER_NAME" \
    --nodegroup-name "$OLD_NG" \
    --region "$REGION" \
    --output json)

INSTANCE_TYPE=$(echo "$OLD_NG_INFO" | jq -r '.nodegroup.instanceTypes[0]')
DESIRED_SIZE=$(echo "$OLD_NG_INFO" | jq -r '.nodegroup.scalingConfig.desiredSize')
MIN_SIZE=$(echo "$OLD_NG_INFO" | jq -r '.nodegroup.scalingConfig.minSize')
MAX_SIZE=$(echo "$OLD_NG_INFO" | jq -r '.nodegroup.scalingConfig.maxSize')

echo "旧节点组配置:"
echo "  实例类型: $INSTANCE_TYPE"
echo "  节点数量: $DESIRED_SIZE (min: $MIN_SIZE, max: $MAX_SIZE)"
echo ""

# 2. 创建新节点组
echo "[2/6] 创建 AL2023 节点组..."
eksctl create nodegroup \
  --cluster "$CLUSTER_NAME" \
  --name "$NEW_NG" \
  --node-ami-family AmazonLinux2023 \
  --node-type "$INSTANCE_TYPE" \
  --nodes "$DESIRED_SIZE" \
  --nodes-min "$MIN_SIZE" \
  --nodes-max "$MAX_SIZE" \
  --region "$REGION"

echo "✅ 新节点组已创建"
echo ""

# 3. 等待节点就绪
echo "[3/6] 等待新节点就绪..."
kubectl wait --for=condition=Ready nodes -l "eks.amazonaws.com/nodegroup=$NEW_NG" --timeout=10m
echo "✅ 新节点已就绪"
echo ""

echo "验证新节点:"
kubectl get nodes -l "eks.amazonaws.com/nodegroup=$NEW_NG" -o custom-columns=NAME:.metadata.name,OS:.status.nodeInfo.osImage,STATUS:.status.conditions[-1:].type
echo ""

# 4. 标记旧节点
echo "[4/6] 标记旧节点为不可调度..."
for node in $(kubectl get nodes -l "eks.amazonaws.com/nodegroup=$OLD_NG" -o name); do
  echo "  标记 ${node#node/}"
  kubectl taint nodes "${node#node/}" old-node=true:NoSchedule 2>/dev/null || true
done
echo "✅ 旧节点已标记"
echo ""

# 5. 迁移工作负载
echo "[5/6] 开始迁移工作负载 (逐个 drain 旧节点)..."
echo ""

for node in $(kubectl get nodes -l "eks.amazonaws.com/nodegroup=$OLD_NG" -o name); do
  NODE_NAME=${node#node/}
  echo "正在 drain $NODE_NAME..."

  kubectl drain "$NODE_NAME" \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --force \
    --grace-period=300 \
    --timeout=10m

  echo "✅ $NODE_NAME drain 完成，等待 Pod 重新调度..."
  sleep 30
done

echo "✅ 所有旧节点已 drain"
echo ""

# 6. 验证迁移结果
echo "[6/6] 验证迁移结果..."
echo ""
echo "节点状态:"
kubectl get nodes -o custom-columns=NAME:.metadata.name,OS:.status.nodeInfo.osImage,STATUS:.status.conditions[-1:].type
echo ""

echo "Pod 分布:"
kubectl get pods --all-namespaces -o wide --no-headers | awk '{print $8}' | sort | uniq -c | sort -rn
echo ""

# 检查旧节点上是否还有非 DaemonSet Pod
OLD_NON_DS_PODS=0
for node in $(kubectl get nodes -l "eks.amazonaws.com/nodegroup=$OLD_NG" -o jsonpath='{.items[*].metadata.name}'); do
    COUNT=$(kubectl get pods --all-namespaces --field-selector "spec.nodeName=$node" -o json 2>/dev/null | \
        jq '[.items[] | select(.metadata.ownerReferences[0].kind != "DaemonSet")] | length')
    OLD_NON_DS_PODS=$((OLD_NON_DS_PODS + COUNT))
done

if [ "$OLD_NON_DS_PODS" -eq 0 ]; then
    echo "✅ 所有非 DaemonSet Pod 已成功迁移到新节点"
else
    echo "⚠️  仍有 $OLD_NON_DS_PODS 个非 DaemonSet Pod 在旧节点上，请检查"
fi
echo ""

# 清理旧节点组
echo "=== 清理旧节点组 ==="
echo "旧节点组: $OLD_NG"
echo "⚠️  删除后无法恢复！建议观察一段时间确认无问题后再删除"
echo ""
read -p "确认删除旧节点组? (输入 'yes' 确认) " -r
echo

if [[ $REPLY == "yes" ]]; then
    echo "删除旧节点组 $OLD_NG..."
    eksctl delete nodegroup \
        --cluster "$CLUSTER_NAME" \
        --name "$OLD_NG" \
        --region "$REGION" \
        --drain=false
    echo "✅ 迁移完成！旧节点组已删除"
else
    echo "保留旧节点组。确认无问题后手动删除:"
    echo ""
    echo "  eksctl delete nodegroup \\"
    echo "    --cluster $CLUSTER_NAME \\"
    echo "    --name $OLD_NG \\"
    echo "    --region $REGION"
fi

echo ""
echo "=== 迁移流程完成 ==="
echo ""
echo "后续步骤:"
echo "1. 监控应用运行状态和日志"
echo "2. 检查 Pod 重启次数是否异常"
echo "3. 验证 Service / Ingress 连通性"
echo "4. 如果保留了旧节点组，确认无问题后再删除"
