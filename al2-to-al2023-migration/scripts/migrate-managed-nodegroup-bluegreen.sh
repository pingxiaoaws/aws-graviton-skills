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

# 检查 eksctl
if ! command -v eksctl &> /dev/null; then
    echo "❌ eksctl 未安装，请先安装: https://eksctl.io/"
    exit 1
fi

# 检查 kubectl
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl 未安装"
    exit 1
fi

# 确认操作
read -p "确认开始迁移? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "取消迁移"
    exit 0
fi

# 1. 创建新节点组
echo "[1/6] 创建 AL2023 节点组..."
echo "提示: 你可能需要调整以下参数:"
echo "  --node-type: 实例类型"
echo "  --nodes: 节点数量"
echo "  --nodes-min/max: 扩展范围"
echo ""

# 获取旧节点组的配置
OLD_NG_INFO=$(aws eks describe-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $OLD_NG \
    --region $REGION \
    --output json)

INSTANCE_TYPE=$(echo $OLD_NG_INFO | jq -r '.nodegroup.instanceTypes[0]')
DESIRED_SIZE=$(echo $OLD_NG_INFO | jq -r '.nodegroup.scalingConfig.desiredSize')
MIN_SIZE=$(echo $OLD_NG_INFO | jq -r '.nodegroup.scalingConfig.minSize')
MAX_SIZE=$(echo $OLD_NG_INFO | jq -r '.nodegroup.scalingConfig.maxSize')

echo "检测到旧节点组配置:"
echo "  实例类型: $INSTANCE_TYPE"
echo "  节点数量: $DESIRED_SIZE (min: $MIN_SIZE, max: $MAX_SIZE)"
echo ""

eksctl create nodegroup \
  --cluster $CLUSTER_NAME \
  --name $NEW_NG \
  --node-ami-family AmazonLinux2023 \
  --node-type $INSTANCE_TYPE \
  --nodes $DESIRED_SIZE \
  --nodes-min $MIN_SIZE \
  --nodes-max $MAX_SIZE \
  --region $REGION

echo "✅ 新节点组已创建"
echo ""

# 2. 等待节点就绪
echo "[2/6] 等待新节点就绪..."
kubectl wait --for=condition=Ready nodes -l eks.amazonaws.com/nodegroup=$NEW_NG --timeout=10m
echo "✅ 新节点已就绪"
echo ""

# 3. 验证新节点
echo "[3/6] 验证新节点..."
NEW_NODES=$(kubectl get nodes -l eks.amazonaws.com/nodegroup=$NEW_NG --no-headers | wc -l)
echo "新节点数量: $NEW_NODES"
kubectl get nodes -l eks.amazonaws.com/nodegroup=$NEW_NG -o wide
echo ""

# 4. 标记旧节点
echo "[4/6] 标记旧节点为不可调度..."
for node in $(kubectl get nodes -l eks.amazonaws.com/nodegroup=$OLD_NG -o name); do
  echo "  标记 ${node#node/}"
  kubectl taint nodes ${node#node/} old-node=true:NoSchedule 2>/dev/null || true
done
echo "✅ 旧节点已标记"
echo ""

# 5. 迁移工作负载
echo "[5/6] 开始迁移工作负载..."
echo "这个过程会逐个 drain 旧节点，请耐心等待"
echo ""

for node in $(kubectl get nodes -l eks.amazonaws.com/nodegroup=$OLD_NG -o name); do
  NODE_NAME=${node#node/}
  echo "正在 drain $NODE_NAME..."

  kubectl drain $NODE_NAME \
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
kubectl get nodes -o custom-columns=NAME:.metadata.name,OS:.status.nodeInfo.osImage,STATUS:.status.conditions[3].type
echo ""

OLD_PODS=$(kubectl get pods --all-namespaces -o wide | grep -c $OLD_NG || true)
if [ $OLD_PODS -eq 0 ]; then
  echo "✅ 所有 Pod 已成功迁移到新节点"
else
  echo "⚠️  仍有 $OLD_PODS 个 Pod 在旧节点上，请检查："
  kubectl get pods --all-namespaces -o wide | grep $OLD_NG || true
  echo ""
  echo "如果这些是 DaemonSet Pod，可以忽略"
fi

echo ""
echo "Pod 分布情况:"
kubectl get pods --all-namespaces -o wide --no-headers | awk '{print $8}' | sort | uniq -c
echo ""

# 7. 清理旧节点组（可选）
echo "=== 清理旧节点组 ==="
echo "旧节点组: $OLD_NG"
echo "⚠️  删除后无法恢复！"
echo ""
read -p "确认删除旧节点组? (输入 'yes' 确认) " -r
echo

if [[ $REPLY == "yes" ]]; then
  echo "删除旧节点组 $OLD_NG..."
  eksctl delete nodegroup \
    --cluster $CLUSTER_NAME \
    --name $OLD_NG \
    --region $REGION \
    --drain=false

  echo "✅ 迁移完成！旧节点组已删除"
else
  echo "保留旧节点组。稍后可以手动删除："
  echo ""
  echo "  eksctl delete nodegroup \\"
  echo "    --cluster $CLUSTER_NAME \\"
  echo "    --name $OLD_NG \\"
  echo "    --region $REGION"
  echo ""
  echo "或者通过 AWS Console 删除"
fi

echo ""
echo "=== 迁移流程完成 ==="
echo ""
echo "后续步骤："
echo "1. 监控应用运行状态"
echo "2. 检查日志和监控指标"
echo "3. 验证所有功能正常"
echo "4. 如果保留了旧节点组，确认无问题后再删除"
