#!/bin/bash

# 生成 AL2023 EKS 节点用户数据脚本
# 使用方法：./generate-al2023-userdata.sh <cluster-name> [region] [output-file]

set -e

CLUSTER_NAME="${1}"
REGION="${2:-us-west-2}"
OUTPUT_FILE="${3:-al2023-userdata.txt}"

if [ -z "$CLUSTER_NAME" ]; then
    echo "用法: $0 <cluster-name> [region] [output-file]"
    echo ""
    echo "示例:"
    echo "  $0 my-cluster us-west-2"
    echo "  $0 my-cluster us-west-2 custom-userdata.txt"
    echo ""
    echo "注意: 仅以下场景需要手动提供集群元数据:"
    echo "  - 托管节点组 + 启动模板（指定自定义 AMI）"
    echo "  - 自管理节点组"
    echo ""
    echo "以下场景不需要（EKS/Karpenter 自动处理）:"
    echo "  - 托管节点组（无启动模板）"
    echo "  - 托管节点组 + 启动模板（未指定 AMI）"
    echo "  - Karpenter"
    exit 1
fi

echo "=== 生成 AL2023 用户数据 ==="
echo "集群名称: $CLUSTER_NAME"
echo "AWS 区域: $REGION"
echo "输出文件: $OUTPUT_FILE"
echo ""

# 检查依赖
for cmd in aws jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ $cmd 未安装"
        exit 1
    fi
done

# 获取集群信息
echo "[1/3] 获取集群信息..."
if ! CLUSTER_INFO=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --output json 2>&1); then
    echo "❌ 无法获取集群信息:"
    echo "$CLUSTER_INFO"
    echo ""
    echo "请检查:"
    echo "  1. 集群名称是否正确"
    echo "  2. AWS CLI 配置是否正确"
    echo "  3. 是否有权限访问该集群"
    exit 1
fi

API_SERVER=$(echo "$CLUSTER_INFO" | jq -r '.cluster.endpoint')
CA_CERT=$(echo "$CLUSTER_INFO" | jq -r '.cluster.certificateAuthority.data')
CIDR=$(echo "$CLUSTER_INFO" | jq -r '.cluster.kubernetesNetworkConfig.serviceIpv4Cidr')

echo "  API Server: $API_SERVER"
echo "  Service CIDR: $CIDR"
echo "  CA Cert: ${CA_CERT:0:20}..."
echo ""

# 生成用户数据
echo "[2/3] 生成用户数据文件..."
cat > "$OUTPUT_FILE" <<EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

# 自定义初始化脚本（可选）
# 注意: AL2023 不再支持 amazon-linux-extras
# 使用 dnf/yum 安装所需软件包
yum install -y htop jq

--BOUNDARY
Content-Type: application/node.eks.aws

---
apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  cluster:
    name: $CLUSTER_NAME
    apiServerEndpoint: $API_SERVER
    certificateAuthority: $CA_CERT
    cidr: $CIDR
  kubelet:
    config:
      maxPods: 110
      clusterDNS:
        - $(echo "$CIDR" | sed 's/\.[0-9]*\/[0-9]*/\.10/')
    flags:
      - --node-labels=node.kubernetes.io/lifecycle=normal

--BOUNDARY--
EOF

echo "✅ 用户数据已生成: $OUTPUT_FILE"
echo ""

# 生成 Base64 编码版本
echo "[3/3] 生成 Base64 编码版本..."
BASE64_FILE="${OUTPUT_FILE%.txt}-base64.txt"
if [[ "$OSTYPE" == "darwin"* ]]; then
    base64 -i "$OUTPUT_FILE" -o "$BASE64_FILE"
else
    base64 -w 0 "$OUTPUT_FILE" > "$BASE64_FILE"
fi

echo "✅ Base64 编码已生成: $BASE64_FILE"
echo ""

echo "=== 使用说明 ==="
echo ""
echo "1. 编辑 $OUTPUT_FILE 添加自定义配置后，重新生成 Base64:"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "   base64 -i $OUTPUT_FILE -o $BASE64_FILE"
else
    echo "   base64 -w 0 $OUTPUT_FILE > $BASE64_FILE"
fi
echo ""
echo "2. 在启动模板中使用 Base64 编码的用户数据"
echo ""
echo "3. 常见自定义选项:"
echo "   - maxPods: 根据实例类型调整"
echo "   - --node-labels: 添加节点标签"
echo "   - --register-with-taints: 添加节点污点"
echo ""
echo "完整 NodeConfig 文档: https://awslabs.github.io/amazon-eks-ami/nodeadm/"
