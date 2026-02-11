# EKS AL2 至 AL2023 迁移实战指南

**快速迁移 Skill - 从规划到执行**

## 概述

这是一个帮助你从 Amazon EKS AL2 节点迁移到 AL2023 节点的实战指南。本指南基于 AWS 官方文档和最佳实践，提供分步骤的操作指导。

### 关键日期时间线

| 日期 | 事件 |
|------|------|
| **2025年11月26日** | EKS 优化版 AL2 AMI 停止支持（不再发布更新） |
| **2026年3月26日** | K8s 1.32（最后支持 AL2 的版本）标准支持结束 |
| **2026年6月30日** | Amazon Linux 2 完全停止维护 |
| **2027年3月26日** | K8s 1.32 扩展支持结束 |

**关键变更**：从 **Kubernetes 1.33** 开始，Amazon EKS **完全停止提供** AL2 AMI。新建集群默认使用 AL2023 AMI，升级到 1.33 的集群在更新数据平面时会**自动更新至 AL2023**。这意味着迁移不是可选的——升级到 1.33 时会强制切换。

**两个 EOL 日期的区别**：AL2（通用操作系统）和 EKS 优化版 AL2 AMI（专用场景）的停止支持是两个独立的事项。EKS 由于集成复杂度和上游 Kubernetes 的限制（cgroupv1 维护模式），无法在 2025.11.26 后继续支持 AL2。Amazon Linux 团队将 AL2 通用支持延长到 2026.6.30 以便给客户更多迁移时间。

**现有集群行为**：现有的托管节点组可以继续使用 AL2 AMI，节点组扩缩容不受影响。但无法通过更新托管节点组功能获取新的 AL2 AMI 更新。

### 支持矩阵

| 场景 | 支持级别 | 说明 |
|------|---------|------|
| AL2023 (cgroupv2) | **完整支持** | 推荐方案 |
| Bottlerocket | **完整支持** | 推荐方案 |
| EKS AL2 AMI (2025.11.26 后) | 有限支持 | 不再发布更新，视为自定义 AMI |
| 自定义 AL2 AMI | 有限支持 | 排查能力受限 |
| AL2023 (手动改 cgroupv1) | 非官方支持 | 需先在 cgroupv2 下重现问题 |

---

## 快速决策树

```
开始迁移
├─ 使用 Karpenter?
│  ├─ 是 → 跳转到"Karpenter 迁移"章节
│  └─ 否 → 继续
├─ 使用托管节点组?
│  ├─ 是 → 跳转到"托管节点组迁移"章节
│  └─ 否 → 跳转到"自管理节点组迁移"章节
```

---

## 迁移前准备清单

### 1. 评估当前环境

```bash
# 检查当前 Kubernetes 版本
kubectl version -o json | jq '.serverVersion.gitVersion'

# 检查节点 OS 版本
kubectl get nodes -o wide

# 检查节点上的 AMI 信息
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  INSTANCE_ID=$(kubectl get node $node -o jsonpath='{.spec.providerID}' | awk -F/ '{print $NF}')
  AMI_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[].Instances[].ImageId' --output text 2>/dev/null)
  echo "$node: $INSTANCE_ID ($AMI_ID)"
done
```

或使用自动化检查脚本：
```bash
./scripts/check-compatibility.sh
```

### 2. 兼容性检查

#### 必须升级的组件

| 组件 | 最低版本 | 检查命令 |
|------|---------|---------|
| **VPC CNI** | 1.16.2 | `kubectl describe daemonset aws-node -n kube-system \| grep Image:` |
| **eksctl** | 0.176.0 | `eksctl version` |

```bash
# 升级 VPC CNI（推荐通过 EKS Add-on 管理）
aws eks update-addon --cluster-name <cluster> --addon-name vpc-cni --addon-version <latest-version>
# 或查看可用版本：
aws eks describe-addon-versions --addon-name vpc-cni --kubernetes-version <k8s-version>

# 升级 eksctl
# macOS
brew upgrade eksctl

# Linux
curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
```

#### 应用兼容性检查

**Java 应用（重要！）**：
```bash
# 检查 Pod 中的 Java 版本
kubectl exec -it <pod-name> -- java -version

# JDK 8 必须 >= jdk8u372
# JDK 11 必须 >= 11.0.16
# JDK 15+ 完全支持
```

**如果使用旧版本 Java**：
- ⚠️ cgroupv2 不兼容会导致 OOM
- 必须升级 JDK 或使用 cgroupv1（不推荐）

**IMDSv2 依赖检查**：
```bash
# 检查 Pod 是否访问节点 IMDS
kubectl get pods --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.hostNetwork==true) | "\(.metadata.namespace)/\(.metadata.name)"'

# 检查是否使用了需要 IMDS 的组件
kubectl get pods --all-namespaces | grep -E "aws-load-balancer-controller|cluster-autoscaler|ebs-csi|efs-csi"
```

#### AL2023 中移除的软件包

迁移时注意以下变化：
- **`/etc/eks/bootstrap.sh` 不再存在** — AL2023 使用 `nodeadm` 和 NodeConfig YAML 替代
- **`/etc/eks/eni-max-pods.txt` 不再存在** — 通过 NodeConfig 配置 maxPods
- **`amazon-linux-extras` 不再可用** — 使用 `dnf`/`yum` 安装软件包
- **EPEL 不再支持** — 需要寻找替代方案
- **32 位应用不再支持** — AL2023 仅支持 64 位
- 部分 AL2 源二进制包在 AL2023 中不可用，详见 [AL2 vs AL2023 比较](https://docs.aws.amazon.com/linux/al2023/ug/compare-with-al2.html)

#### nodeadm 用户数据场景

AL2023 使用 `nodeadm` 替代 `bootstrap.sh`，但**不是所有场景都需要手动修改用户数据**：

| 场景 | 是否需要手动提供集群元数据 | 说明 |
|------|------|------|
| 托管节点组（无启动模板） | **不需要** | EKS 自动处理 |
| 托管节点组 + 启动模板（未指定 AMI） | **不需要** | EKS 自动合并用户数据 |
| 托管节点组 + 启动模板（指定自定义 AMI） | **需要** | EKS 不合并用户数据 |
| 自管理节点组 | **需要** | 需要完整 NodeConfig 配置 |
| Karpenter | **不需要** | Karpenter 自动处理 |

对于需要手动配置的场景，可使用 `./scripts/generate-al2023-userdata.sh` 自动生成。

#### IMDSv2 组件依赖详情

AL2023 默认要求 IMDSv2 且 hop limit = 1。以下组件需要特别处理：

| 组件 | 是否需要 IMDS | 替代方案 |
|------|------|------|
| **AWS LB Controller** | 必须（获取 VPC ID、Region） | 通过 `--aws-region`、`--aws-vpc-id` Helm 参数显式指定 |
| **Cluster Autoscaler** | 需要（获取实例信息） | 使用 IRSA 或 EKS Pod Identity |
| **EBS CSI Driver** | 需要（节点获取实例信息） | v1.45+ 支持 `--metadata-sources=k8s` |
| **EFS CSI Driver** | 可选 | 使用 IRSA 或 EKS Pod Identity |
| **VPC CNI** | 可选 | 核心组件，通常在主机网络模式运行 |

**推荐方案**：使用 [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) 替代 IMDS 依赖，这是最安全的方式。如果必须使用 IMDS，需确保启动模板设置 `HttpPutResponseHopLimit >= 2`。

### 3. 准备测试环境

```bash
# 创建测试集群（可选）
eksctl create cluster \
  --name al2023-test \
  --region us-west-2 \
  --node-ami-family AmazonLinux2023 \
  --nodes 2 \
  --node-type t3.medium

# 或在现有集群创建测试节点组
eksctl create nodegroup \
  --cluster my-cluster \
  --name al2023-test-ng \
  --node-ami-family AmazonLinux2023 \
  --nodes 1 \
  --nodes-min 1 \
  --nodes-max 3
```

---

## 方案一：Karpenter 用户迁移（最简单）

### 特点
- ✅ 最简单的迁移方式
- ✅ 自动滚动升级
- ✅ 零停机时间

### 步骤 1：备份现有配置

```bash
# 导出现有 EC2NodeClass
kubectl get ec2nodeclass -o yaml > ec2nodeclass-backup.yaml

# 导出现有 NodePool
kubectl get nodepool -o yaml > nodepool-backup.yaml
```

### 步骤 2：更新 EC2NodeClass

```bash
# 编辑 EC2NodeClass
kubectl edit ec2nodeclass <your-nodeclass-name>
```

**关键修改**：
```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  # 修改 AMI 选择器
  amiSelectorTerms:
    - alias: al2023@latest  # 从 al2@latest 改为 al2023@latest

  # 如果有自定义 userData，需要更新格式
  userData: |
    # AL2023 使用 MIME 多部分格式和 NodeConfig
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="//"

    --//
    Content-Type: text/x-shellscript; charset="us-ascii"

    #!/bin/bash
    # 你的自定义脚本
    yum install -y htop

    --//
    Content-Type: application/node.eks.aws

    ---
    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      kubelet:
        config:
          maxPods: 110
        flags:
          - --node-labels=workload=general

    --//--
```

### 步骤 3：控制滚动升级速度（可选）

```yaml
# 在 NodePool 中配置 disruption 预算
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s

    # 控制同时升级的节点数量
    budgets:
      - nodes: "2"  # 每次最多升级 2 个节点
        schedule: "* * * * *"  # 始终有效
```

### 步骤 4：触发升级

```bash
# 应用更改后，Karpenter 会自动检测 drift
# 可以手动触发 Pod 重新调度来加速
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# 或者强制删除旧节点（谨慎）
kubectl delete node <old-al2-node>
```

### 步骤 5：验证

```bash
# 检查新节点的 OS 版本
kubectl get nodes -o custom-columns=NAME:.metadata.name,OS-IMAGE:.status.nodeInfo.osImage

# 应该看到：Amazon Linux 2023

# 检查 Pod 是否正常运行
kubectl get pods --all-namespaces --field-selector spec.nodeName=<new-node-name>
```

---

## 方案二：托管节点组迁移

### 场景 A：蓝绿部署（推荐）

**适用场景**：生产环境，需要快速回滚能力

#### 步骤 1：创建新的 AL2023 节点组

```bash
# 方法 1：使用 eksctl（最简单）
eksctl create nodegroup \
  --cluster my-cluster \
  --name al2023-ng \
  --node-ami-family AmazonLinux2023 \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 1 \
  --nodes-max 5 \
  --region us-west-2

# 方法 2：使用 AWS CLI（高级用户）
# 先创建启动模板（如果需要自定义）
aws ec2 create-launch-template \
  --launch-template-name al2023-template \
  --version-description "AL2023 for EKS" \
  --launch-template-data '{
    "InstanceType": "t3.medium",
    "ImageId": "ami-xxxxx",
    "UserData": "BASE64_ENCODED_USERDATA",
    "MetadataOptions": {
      "HttpTokens": "required",
      "HttpPutResponseHopLimit": 2
    }
  }'

# 创建托管节点组
aws eks create-nodegroup \
  --cluster-name my-cluster \
  --nodegroup-name al2023-ng \
  --subnets subnet-xxx subnet-yyy \
  --node-role arn:aws:iam::ACCOUNT:role/NodeInstanceRole \
  --launch-template name=al2023-template,version=1 \
  --scaling-config minSize=1,maxSize=5,desiredSize=3
```

#### 步骤 2：标记旧节点（防止新 Pod 调度）

```bash
# 给所有旧节点添加 taint
for node in $(kubectl get nodes -l eks.amazonaws.com/nodegroup=old-ng -o name); do
  kubectl taint nodes ${node#node/} old-node=true:NoSchedule
done
```

#### 步骤 3：迁移工作负载

```bash
# 方法 1：逐个迁移 Pod（精细控制）
kubectl get pods --all-namespaces -o wide | grep <old-node-name>
kubectl delete pod <pod-name> -n <namespace>

# 方法 2：批量 drain（自动迁移）
for node in $(kubectl get nodes -l eks.amazonaws.com/nodegroup=old-ng -o name); do
  kubectl drain ${node#node/} \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --force \
    --grace-period=300
  sleep 60  # 等待 60 秒再处理下一个节点
done
```

#### 步骤 4：验证和清理

```bash
# 验证所有 Pod 已迁移
kubectl get pods --all-namespaces -o wide | grep -v al2023-ng

# 如果没有问题，删除旧节点组
eksctl delete nodegroup \
  --cluster my-cluster \
  --name old-ng \
  --region us-west-2
```

### 场景 B：就地升级（使用启动模板）

**适用场景**：已使用自定义 AMI 的启动模板

#### 步骤 1：获取 AL2023 AMI ID

```bash
# 获取最新 AL2023 EKS 优化 AMI
aws ssm get-parameter \
  --name /aws/service/eks/optimized-ami/1.31/amazon-linux-2023/x86_64/standard/recommended/image_id \
  --region us-west-2 \
  --query "Parameter.Value" \
  --output text
```

#### 步骤 2：准备 AL2023 用户数据

**重要**：AL2023 使用不同的用户数据格式！

**AL2 格式（旧）**：
```bash
#!/bin/bash
/etc/eks/bootstrap.sh my-cluster \
  --kubelet-extra-args '--max-pods=110 --node-labels=app=myapp'
```

**AL2023 格式（新）**：
```yaml
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="//"

--//
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
# 自定义脚本
yum install -y htop jq

--//
Content-Type: application/node.eks.aws

---
apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  cluster:
    name: my-cluster
    apiServerEndpoint: https://XXXX.gr7.us-west-2.eks.amazonaws.com
    certificateAuthority: LS0tLS1CRUdJTi0tLS0t...
    cidr: 10.100.0.0/16
  kubelet:
    config:
      maxPods: 110
    flags:
      - --node-labels=app=myapp

--//--
```

**生成用户数据**：
```bash
# 获取集群信息
CLUSTER_NAME="my-cluster"
REGION="us-west-2"

API_SERVER=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.endpoint" --output text)
CA_CERT=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.certificateAuthority.data" --output text)
CIDR=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.kubernetesNetworkConfig.serviceIpv4Cidr" --output text)

# 创建用户数据文件
cat > userdata.txt <<EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="//"

--//
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
yum install -y htop jq

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
      - --node-labels=app=myapp

--//--
EOF

# Base64 编码（用于启动模板）
cat userdata.txt | base64 -w 0 > userdata-base64.txt
```

#### 步骤 3：创建新版本启动模板

```bash
# 创建新版本
aws ec2 create-launch-template-version \
  --launch-template-name my-template \
  --version-description "AL2023 migration" \
  --source-version 1 \
  --launch-template-data "{
    \"ImageId\": \"ami-0abcdef1234567890\",
    \"UserData\": \"$(cat userdata-base64.txt)\"
  }"

# 设置为默认版本
aws ec2 modify-launch-template \
  --launch-template-name my-template \
  --default-version 2
```

#### 步骤 4：更新托管节点组

```bash
# 更新节点组使用新模板版本
aws eks update-nodegroup-version \
  --cluster-name my-cluster \
  --nodegroup-name my-ng \
  --launch-template name=my-template,version=2

# 监控更新进度
aws eks describe-nodegroup \
  --cluster-name my-cluster \
  --nodegroup-name my-ng \
  --query "nodegroup.updateConfig"
```

---

## 方案三：自管理节点组迁移

### 步骤 1：创建 AL2023 节点的 Auto Scaling Group

```bash
# 1. 创建启动模板（完整配置）
cat > launch-template.json <<EOF
{
  "LaunchTemplateName": "al2023-eks-node",
  "VersionDescription": "AL2023 EKS node",
  "LaunchTemplateData": {
    "ImageId": "ami-xxxxx",
    "InstanceType": "t3.medium",
    "KeyName": "my-key",
    "SecurityGroupIds": ["sg-xxxxx"],
    "IamInstanceProfile": {
      "Arn": "arn:aws:iam::ACCOUNT:instance-profile/NodeInstanceProfile"
    },
    "UserData": "$(cat userdata-base64.txt)",
    "BlockDeviceMappings": [{
      "DeviceName": "/dev/xvda",
      "Ebs": {
        "VolumeSize": 20,
        "VolumeType": "gp3",
        "DeleteOnTermination": true
      }
    }],
    "MetadataOptions": {
      "HttpTokens": "required",
      "HttpPutResponseHopLimit": 2
    },
    "TagSpecifications": [{
      "ResourceType": "instance",
      "Tags": [
        {"Key": "Name", "Value": "eks-al2023-node"},
        {"Key": "kubernetes.io/cluster/my-cluster", "Value": "owned"}
      ]
    }]
  }
}
EOF

aws ec2 create-launch-template --cli-input-json file://launch-template.json

# 2. 创建 Auto Scaling Group
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name eks-al2023-asg \
  --launch-template LaunchTemplateName=al2023-eks-node,Version='$Latest' \
  --min-size 1 \
  --max-size 5 \
  --desired-capacity 3 \
  --vpc-zone-identifier "subnet-xxx,subnet-yyy" \
  --tags Key=Name,Value=eks-al2023-node,PropagateAtLaunch=true \
         Key=kubernetes.io/cluster/my-cluster,Value=owned,PropagateAtLaunch=true
```

### 步骤 2：验证节点加入集群

```bash
# 等待节点就绪
kubectl get nodes --watch

# 检查节点标签和污点
kubectl describe node <new-node-name>
```

### 步骤 3：迁移工作负载

```bash
# 与托管节点组相同的步骤
kubectl drain <old-node> --ignore-daemonsets --delete-emptydir-data
```

### 步骤 4：清理旧 ASG

```bash
# 减少旧 ASG 容量到 0
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name old-asg \
  --min-size 0 \
  --max-size 0 \
  --desired-capacity 0

# 验证所有节点已终止后删除
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name old-asg \
  --force-delete
```

---

## 常见问题排查

### 问题 1：Pod 无法启动 - "Container image already present"

**症状**：
```
Failed to create pod sandbox: rpc error: code = Unknown desc = failed to get sandbox image
```

**原因**：AL2023 1.31+ 将 pause 镜像预缓存到 `localhost`，如果手动挂载了 `/var/lib/containerd` 会丢失。常见于使用实例存储（NVMe）作为 containerd 数据目录的场景。

**解决方案**：
```bash
# 方案 1（推荐）：使用 nodeadm LocalStorageOptions 自动挂载实例存储
# 在 NodeConfig 中配置，nodeadm 会正确处理 pause 镜像缓存
# ---
# apiVersion: node.eks.aws/v1alpha1
# kind: NodeConfig
# spec:
#   instance:
#     localStorage:
#       strategy: RAID0  # 或 Mount
#   cluster:
#     ...

# 方案 2：手动导入 pause 镜像（在 userData 脚本中执行）
sudo ctr -n k8s.io images import /etc/eks/pause.tar

# 方案 3：修改 containerd 配置使用外部源
sudo cat >> /etc/containerd/config.toml <<EOF
[plugins.'io.containerd.cri.v1.cri']
  sandbox_image = "registry.k8s.io/pause:3.9"
EOF
sudo systemctl restart containerd
```

> **注意**：如果使用实例存储（如 i3、i4i 等实例），强烈推荐使用 nodeadm 的 `LocalStorageOptions` 而非手动挂载脚本，这样 nodeadm 会正确处理 pause 镜像和 containerd 数据目录。

### 问题 2：Java 应用 OOM 错误

**症状**：
```
OutOfMemoryError: Java heap space
Container killed (exit code 137)
```

**原因**：旧版本 JDK 不支持 cgroupv2

**解决方案**：
```bash
# 检查 JDK 版本
kubectl exec <pod> -- java -version

# 如果是 JDK 8 < u372，升级 JDK
# Dockerfile 修改
FROM openjdk:8u372-jdk  # 或更高版本

# 临时解决（不推荐）：使用 cgroupv1
# 在 AL2023 节点上运行
sudo grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=0"
sudo reboot
```

### 问题 3：AWS Load Balancer Controller 无法工作

**症状**：
```
Failed to get VPC ID from metadata service
```

**原因**：AL2023 默认 IMDSv2 hop limit = 1，容器无法访问 IMDS

**解决方案**：
```bash
# 方案 1：修改启动模板 hop limit
aws ec2 modify-launch-template \
  --launch-template-name my-template \
  --launch-template-data '{
    "MetadataOptions": {
      "HttpPutResponseHopLimit": 2
    }
  }'

# 方案 2：使用命令行参数（推荐）
# Helm values.yaml
clusterName: my-cluster
region: us-west-2
vpcId: vpc-xxxxx
```

### 问题 4：私有镜像仓库证书失效

**症状**：
```
x509: certificate signed by unknown authority
```

**原因**：containerd 2.1+ 默认启用 transfer service，不读取 `/etc/containerd/certs.d`

**解决方案**：
```bash
# 禁用 transfer service
sudo cat >> /etc/containerd/config.toml <<EOF
[plugins.'io.containerd.cri.v1.images']
  use_local_image_pull = true
EOF
sudo systemctl restart containerd
```

### 问题 5：节点无法加入集群 - 权限错误

**症状**：
```
kubelet: Unauthorized
```

**原因**：aws-auth ConfigMap 未更新节点 IAM 角色

**解决方案**：
```bash
# 检查当前 aws-auth
kubectl get configmap aws-auth -n kube-system -o yaml

# 添加节点角色
kubectl edit configmap aws-auth -n kube-system

# 添加以下内容
mapRoles: |
  - rolearn: arn:aws:iam::ACCOUNT:role/NodeInstanceRole
    username: system:node:{{EC2PrivateDNSName}}
    groups:
      - system:bootstrappers
      - system:nodes
```

---

## 迁移后验证清单

### 1. 节点健康检查

```bash
# 检查所有节点状态
kubectl get nodes -o wide

# 应该看到：
# - STATUS: Ready
# - OS-IMAGE: Amazon Linux 2023
# - KERNEL-VERSION: 6.1.x

# 检查节点资源
kubectl top nodes

# 检查节点事件
kubectl get events --all-namespaces --field-selector type=Warning
```

### 2. Pod 健康检查

```bash
# 检查所有 Pod 状态
kubectl get pods --all-namespaces

# 检查 Pod 分布
kubectl get pods --all-namespaces -o wide | \
  awk '{print $8}' | sort | uniq -c

# 检查失败的 Pod
kubectl get pods --all-namespaces --field-selector status.phase!=Running,status.phase!=Succeeded

# 检查重启次数异常的 Pod
kubectl get pods --all-namespaces --sort-by=.status.containerStatuses[0].restartCount
```

### 3. 应用功能测试

```bash
# 测试 Service 连通性
kubectl run test-pod --image=busybox --restart=Never -- sleep 3600
kubectl exec test-pod -- nslookup kubernetes.default
kubectl exec test-pod -- wget -O- http://my-service

# 测试 Ingress/LoadBalancer
curl http://<load-balancer-dns>

# 测试持久化存储
kubectl exec <pod> -- df -h
kubectl exec <pod> -- touch /mnt/data/test-file
```

### 4. 监控和日志

```bash
# 检查 kubelet 日志
kubectl logs -n kube-system -l k8s-app=kubelet --tail=100

# 检查 containerd 日志（在节点上）
sudo journalctl -u containerd -n 100

# 检查应用日志
kubectl logs -n <namespace> <pod-name> --tail=100
```

### 5. 性能基准测试

```bash
# 测试网络性能
kubectl run iperf3-server --image=networkstatic/iperf3 -- -s
kubectl run iperf3-client --image=networkstatic/iperf3 -- -c <server-pod-ip>

# 测试磁盘性能（在节点上）
sudo fio --name=randwrite --ioengine=libaio --iodepth=16 --rw=randwrite --bs=4k --size=1G --runtime=60 --time_based

# 对比 AL2 vs AL2023 的 Pod 启动时间
time kubectl run test --image=nginx --restart=Never
kubectl delete pod test
```

---

## 回滚计划

### 场景 1：Karpenter 回滚

```bash
# 回滚 EC2NodeClass
kubectl apply -f ec2nodeclass-backup.yaml

# 强制重建节点
kubectl delete node <al2023-node>
```

### 场景 2：托管节点组回滚（蓝绿部署）

```bash
# 只需删除新节点组
eksctl delete nodegroup \
  --cluster my-cluster \
  --name al2023-ng

# 移除旧节点的 taint
for node in $(kubectl get nodes -l eks.amazonaws.com/nodegroup=old-ng -o name); do
  kubectl taint nodes ${node#node/} old-node-
done
```

### 场景 3：托管节点组回滚（就地升级）

```bash
# 回滚启动模板到旧版本
aws ec2 modify-launch-template \
  --launch-template-name my-template \
  --default-version 1

# 强制更新节点组
aws eks update-nodegroup-version \
  --cluster-name my-cluster \
  --nodegroup-name my-ng \
  --launch-template name=my-template,version=1 \
  --force
```

---

## 性能优化建议

### 1. 优化 containerd 配置

```bash
# /etc/containerd/config.toml
[plugins.'io.containerd.cri.v1.images']
  max_concurrent_downloads = 10  # 增加并发下载

[plugins.'io.containerd.grpc.v1.cri'.containerd.runtimes.runc.options]
  SystemdCgroup = true
```

### 2. 优化 kubelet 配置

```yaml
# NodeConfig
spec:
  kubelet:
    config:
      maxPods: 110  # 根据实例类型调整
      imageGCHighThresholdPercent: 85
      imageGCLowThresholdPercent: 80
      evictionHard:
        memory.available: "100Mi"
        nodefs.available: "10%"
```

### 3. 启用 SOCI（适合大镜像）

SOCI (Seekable OCI) 通过 containerd snapshotter 启用，不是 kubelet feature gate。

对于 **AL2023**（>= v20250821 的 AMI 已预装 SOCI）：
```yaml
# NodeConfig
spec:
  kubelet:
    config:
      containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
  # SOCI 通过 containerd 配置启用，参考 Karpenter Blueprints:
  # https://github.com/aws-samples/karpenter-blueprints/tree/main/blueprints/soci-snapshotter
```

对于 **Bottlerocket**（>= v1.44.0）：
```toml
[settings.container-runtime]
snapshotter = "soci"
```

详细配置请参考 [Karpenter SOCI Blueprint](https://github.com/aws-samples/karpenter-blueprints/tree/main/blueprints/soci-snapshotter)。

---

## NVIDIA GPU 迁移注意事项

### 驱动版本差异

| 组件 | AL2 AMI | AL2023 AMI |
|------|---------|------------|
| NVIDIA GPU 驱动 | R570 | R580 |
| CUDA 用户模式驱动 | 12.x | 12.x, 13.x |
| Linux 内核 | 5.10 | 6.1, 6.12 |

### CUDA 13 驱动与 CUDA 12 容器镜像兼容性

AL2023 使用 R580 驱动（CUDA 13），如果容器镜像基于 CUDA 12，可能出现：
1. **容器启动失败**：NVIDIA 容器镜像通常设置 `NVIDIA_REQUIRE_CUDA=cuda>=X.Y` 环境变量
2. **运行时异常**：跨 CUDA 主版本可能导致计算结果不一致

**解决方案**（按推荐程度排序）：

1. **升级容器镜像（推荐）**：
```dockerfile
# 从
FROM nvidia/cuda:12.5.0-runtime-ubuntu22.04
# 改为
FROM nvidia/cuda:13.0.0-runtime-ubuntu22.04
```

2. **绕过版本检查（紧急情况）**：
```yaml
env:
  - name: NVIDIA_DISABLE_REQUIRE
    value: "1"
```
此方法仅用于紧急过渡，可能导致未定义行为。

### AWS Neuron (Trainium/Inferentia)

从 AWS Neuron 2.20 开始，Neuron 运行时（`aws-neuronx-runtime-lib`）不再支持 AL2。Neuron 驱动（`aws-neuronx-dkms`）是目前唯一仍支持 AL2 的组件。

如果使用 Neuron 工作负载：
- 必须使用容器化部署（基于 AL2023 或 Ubuntu 的容器镜像）
- 参考 [AWS Neuron 设置指南](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/general/setup/index.html)

---

## 自动化工具

本 Skill 提供了多个自动化脚本来简化迁移流程。所有脚本都位于 `scripts/` 目录。

### 1. 兼容性检查脚本

在迁移前运行，检查环境是否满足 AL2023 要求：

```bash
./scripts/check-compatibility.sh
```

**检查项目**：
- Kubernetes 版本
- VPC CNI 版本
- Java 应用 cgroupv2 兼容性
- IMDSv2 依赖组件
- 关键控制器版本
- 当前节点 OS 分布

### 2. 生成用户数据脚本

自动生成 AL2023 节点的用户数据配置：

```bash
./scripts/generate-al2023-userdata.sh <cluster-name> <region> [output-file]
```

**示例**：
```bash
./scripts/generate-al2023-userdata.sh my-cluster us-west-2
```

**输出**：
- `al2023-userdata.txt` - 可读的 MIME 格式用户数据
- `al2023-userdata-base64.txt` - Base64 编码（用于启动模板）

### 3. Karpenter 自动迁移脚本

最简单的迁移方式（推荐使用 Karpenter 的用户）：

```bash
./scripts/migrate-karpenter.sh <cluster-name> <ec2nodeclass-name>
```

**示例**：
```bash
./scripts/migrate-karpenter.sh my-cluster default
```

**功能**：
- 自动备份现有配置
- 更新 EC2NodeClass 到 AL2023
- 等待 Karpenter drift 检测
- 可选监控节点更新进度

**时间**：5 分钟配置 + 10-30 分钟自动更新

### 4. 托管节点组蓝绿迁移脚本

零停机的蓝绿部署迁移：

```bash
./scripts/migrate-managed-nodegroup-bluegreen.sh \
  <cluster-name> \
  <old-nodegroup> \
  <new-nodegroup> \
  <region>
```

**示例**：
```bash
./scripts/migrate-managed-nodegroup-bluegreen.sh \
  my-cluster \
  al2-nodegroup \
  al2023-nodegroup \
  us-west-2
```

**流程**：
1. 检测旧节点组配置（实例类型、节点数量等）
2. 创建新的 AL2023 节点组（使用相同配置）
3. 等待新节点就绪
4. 标记旧节点不可调度
5. 逐个 drain 旧节点（优雅迁移工作负载）
6. 验证迁移结果
7. 可选：删除旧节点组

**时间**：30-60 分钟（取决于工作负载数量）

### 快速使用示例

**场景 1：使用 Karpenter（最简单）**

```bash
# 1. 检查兼容性
./scripts/check-compatibility.sh

# 2. 执行迁移
./scripts/migrate-karpenter.sh my-cluster default

# 3. 监控进度
kubectl get nodes -o wide -w
```

**场景 2：使用托管节点组**

```bash
# 1. 检查兼容性
./scripts/check-compatibility.sh

# 2. 执行蓝绿迁移
./scripts/migrate-managed-nodegroup-bluegreen.sh \
  my-cluster al2-ng al2023-ng us-west-2

# 脚本会自动完成所有步骤并提示删除旧节点组
```

**场景 3：自定义用户数据**

```bash
# 1. 生成基础用户数据
./scripts/generate-al2023-userdata.sh my-cluster us-west-2

# 2. 编辑 al2023-userdata.txt 添加自定义配置
vim al2023-userdata.txt

# 3. 重新生成 Base64 编码
cat al2023-userdata.txt | base64 > al2023-userdata-base64.txt  # Linux
cat al2023-userdata.txt | base64 > al2023-userdata-base64.txt  # macOS

# 4. 在启动模板中使用 al2023-userdata-base64.txt
```

---

## 参考资源

### 官方文档
- [从 Amazon Linux 2 升级到 Amazon Linux 2023](https://docs.aws.amazon.com/eks/latest/userguide/al2023.html)
- [nodeadm 文档](https://awslabs.github.io/amazon-eks-ami/nodeadm/)
- [EKS AL2 AMI 弃用常见问题](https://docs.aws.amazon.com/eks/latest/userguide/eks-ami-deprecation-faqs.html)

### 工具
- [eksctl](https://eksctl.io/)
- [AWS CLI](https://aws.amazon.com/cli/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

### 社区资源
- [Amazon EKS AMI GitHub](https://github.com/awslabs/amazon-eks-ami)
- [Karpenter 文档](https://karpenter.sh/)

---

**版本**：v1.0
**最后更新**：2026-02-11
**作者**：基于 AWS 官方文档和社区最佳实践
