#!/bin/bash

# 生成 AL2023 EKS 节点用户数据脚本
# 使用方法：./generate-al2023-userdata.sh <cluster-name> <region> [output-file]

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
    exit 1
fi

echo "=== 生成 AL2023 用户数据 ==="
echo "集群名称: $CLUSTER_NAME"
echo "AWS 区域: $REGION"
echo "输出文件: $OUTPUT_FILE"
echo ""

# 检查 AWS CLI
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI 未安装"
    exit 1
fi

# 获取集群信息
echo "[1/3] 获取集群信息..."
CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --output json 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ 无法获取集群信息，请检查:"
    echo "  1. 集群名称是否正确"
    echo "  2. AWS CLI 配置是否正确"
    echo "  3. 是否有权限访问该集群"
    exit 1
fi

API_SERVER=$(echo $CLUSTER_INFO | jq -r '.cluster.endpoint')
CA_CERT=$(echo $CLUSTER_INFO | jq -r '.cluster.certificateAuthority.data')
CIDR=$(echo $CLUSTER_INFO | jq -r '.cluster.kubernetesNetworkConfig.serviceIpv4Cidr')

echo "  API Server: $API_SERVER"
echo "  Service CIDR: $CIDR"
echo "  CA Cert: ${CA_CERT:0:20}..."
echo ""

# 生成用户数据
echo "[2/3] 生成用户数据文件..."
cat > $OUTPUT_FILE <<EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="//"

--//
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
# 自定义初始化脚本（可选）
# 在这里添加你需要的系统配置

# 示例：安装常用工具
yum install -y htop jq wget curl

# 示例：配置系统参数
# sysctl -w net.ipv4.ip_forward=1

--//
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
    flags:
      - --node-labels=node.kubernetes.io/lifecycle=normal
      # 添加更多标签（可选）
      # - --node-labels=workload-type=general

--//--
EOF

echo "✅ 用户数据已生成: $OUTPUT_FILE"
echo ""

# 生成 Base64 编码版本（用于启动模板）
echo "[3/3] 生成 Base64 编码版本..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    cat $OUTPUT_FILE | base64 > ${OUTPUT_FILE%.txt}-base64.txt
else
    # Linux
    cat $OUTPUT_FILE | base64 -w 0 > ${OUTPUT_FILE%.txt}-base64.txt
fi

echo "✅ Base64 编码已生成: ${OUTPUT_FILE%.txt}-base64.txt"
echo ""

# 显示使用说明
echo "=== 使用说明 ==="
echo ""
echo "1. 查看生成的用户数据:"
echo "   cat $OUTPUT_FILE"
echo ""
echo "2. 用于 EC2 启动模板:"
echo "   使用文件: ${OUTPUT_FILE%.txt}-base64.txt"
echo ""
echo "   aws ec2 create-launch-template-version \\"
echo "     --launch-template-name my-template \\"
echo "     --version-description \"AL2023 with custom config\" \\"
echo "     --source-version 1 \\"
echo "     --launch-template-data file://launch-template-data.json"
echo ""
echo "   其中 launch-template-data.json 包含:"
echo "   {"
echo "     \"ImageId\": \"ami-xxxxx\","
echo "     \"UserData\": \"$(cat ${OUTPUT_FILE%.txt}-base64.txt)\""
echo "   }"
echo ""
echo "3. 用于 eksctl 节点组:"
echo "   在 nodegroup.yaml 中使用:"
echo ""
echo "   preBootstrapCommands:"
echo "     - yum install -y htop jq"
echo ""
echo "   (eksctl 会自动处理 NodeConfig 部分)"
echo ""
echo "4. 自定义用户数据:"
echo "   编辑 $OUTPUT_FILE"
echo "   然后重新生成 Base64:"
echo ""
echo "   # macOS"
echo "   cat $OUTPUT_FILE | base64 > ${OUTPUT_FILE%.txt}-base64.txt"
echo ""
echo "   # Linux"
echo "   cat $OUTPUT_FILE | base64 -w 0 > ${OUTPUT_FILE%.txt}-base64.txt"
echo ""
echo "=== 常见自定义选项 ==="
echo ""
echo "1. 调整最大 Pod 数 (默认 110):"
echo "   修改: maxPods: 110"
echo ""
echo "2. 添加节点标签:"
echo "   在 flags 下添加:"
echo "   - --node-labels=key=value"
echo ""
echo "3. 添加节点污点:"
echo "   在 flags 下添加:"
echo "   - --register-with-taints=key=value:NoSchedule"
echo ""
echo "4. 自定义 kubelet 参数:"
echo "   在 config 下添加更多配置"
echo ""
echo "完整 NodeConfig 文档:"
echo "https://awslabs.github.io/amazon-eks-ami/nodeadm/"
