# EKS AL2 至 AL2023 迁移实战指南

**快速迁移 Skill - 从规划到执行**

## 概述

这是一个帮助你从 Amazon EKS AL2 节点迁移到 AL2023 节点的实战指南。本指南基于 AWS 官方文档和最佳实践，提供分步骤的操作指导。

### 关键信息速查

| 项目 | 信息 |
|------|------|
| **AL2 AMI 停止支持** | 2025年11月26日 |
| **AL2 完全停止维护** | 2026年6月30日 |
| **最后支持 AL2 的 K8s 版本** | 1.32 |
| **推荐迁移目标** | AL2023 或 Bottlerocket |

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
kubectl version --short

# 检查节点 OS 版本
kubectl get nodes -o wide

# 检查节点上的 AMI 信息
aws ec2 describe-instances \
  --instance-ids $(kubectl get nodes -o jsonpath='{.items[*].spec.providerID}' | sed 's/aws:\/\/\///g') \
  --query 'Reservations[].Instances[].[InstanceId,ImageId,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

### 2. 兼容性检查

#### 必须升级的组件

| 组件 | 最低版本 | 检查命令 |
|------|---------|---------|
| **VPC CNI** | 1.16.2 | `kubectl describe daemonset aws-node -n kube-system \| grep Image:` |
| **eksctl** | 0.176.0 | `eksctl version` |

```bash
# 升级 VPC CNI
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/release-1.18/config/master/aws-k8s-cni.yaml

# 升级 eksctl
# macOS
brew upgrade eksctl

# Linux
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
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

**原因**：AL2023 1.31+ 将 pause 镜像预缓存到 `localhost`，如果手动挂载了 `/var/lib/containerd` 会丢失。

**解决方案**：
```bash
# 方案 1：手动导入 pause 镜像
sudo ctr -n k8s.io images import /etc/eks/pause.tar

# 方案 2：修改 containerd 配置使用外部源
sudo cat >> /etc/containerd/config.toml <<EOF
[plugins.'io.containerd.cri.v1.cri']
  sandbox_image = "registry.k8s.io/pause:3.9"
EOF
sudo systemctl restart containerd
```

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

```yaml
# NodeConfig
spec:
  kubelet:
    config:
      featureGates:
        FastImagePull: true
```

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
