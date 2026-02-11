# AL2 到 AL2023 迁移 Skill

帮助你从 Amazon EKS AL2 节点迁移到 AL2023 节点的实战工具集。

## 📋 快速开始

### 关键日期

| 日期 | 事件 |
|------|------|
| **2025年11月26日** | EKS 优化版 AL2 AMI 停止支持 |
| **2026年6月30日** | Amazon Linux 2 完全停止维护 |

### 快速决策

```
使用 Karpenter?
├─ 是 → 使用 migrate-karpenter.sh（最简单）
└─ 否 → 使用托管节点组还是自管理？
   ├─ 托管节点组 → 使用 migrate-managed-nodegroup-bluegreen.sh
   └─ 自管理节点组 → 参考 SKILL.md 手动迁移
```

## 🛠️ 工具和脚本

### 1. 兼容性检查

在迁移前检查环境兼容性：

```bash
./scripts/check-compatibility.sh
```

**检查项目**：
- ✅ Kubernetes 版本 (>= 1.23)
- ✅ VPC CNI 版本 (>= 1.16.2)
- ⚠️ Java 应用 cgroupv2 兼容性
- ⚠️ IMDSv2 依赖组件
- ⚠️ 关键控制器版本

### 2. 生成 AL2023 用户数据

生成 AL2023 节点的用户数据配置：

```bash
./scripts/generate-al2023-userdata.sh <cluster-name> <region>
```

**输出**：
- `al2023-userdata.txt` - 可读的用户数据
- `al2023-userdata-base64.txt` - Base64 编码（用于启动模板）

### 3. Karpenter 自动迁移

最简单的迁移方式（如果使用 Karpenter）：

```bash
./scripts/migrate-karpenter.sh <cluster-name> <ec2nodeclass-name>
```

**特点**：
- ✅ 自动备份现有配置
- ✅ 一键更新到 AL2023
- ✅ Karpenter 自动滚动更新节点
- ⏱️ 10-30 分钟完成

### 4. 托管节点组蓝绿迁移

零停机的蓝绿部署迁移：

```bash
./scripts/migrate-managed-nodegroup-bluegreen.sh \
  <cluster-name> \
  <old-nodegroup> \
  <new-nodegroup> \
  <region>
```

**流程**：
1. 创建新的 AL2023 节点组
2. 等待新节点就绪
3. 标记旧节点不可调度
4. 逐个 drain 旧节点
5. 验证迁移结果
6. 可选：删除旧节点组

**时间**：20-60 分钟（取决于工作负载数量）

## 📖 文档

### SKILL.md

完整的迁移指南，包含：
- ✅ 迁移前准备清单
- ✅ 三种迁移方案详解（Karpenter / 托管节点组 / 自管理节点组）
- ✅ 常见问题排查
- ✅ 迁移后验证步骤
- ✅ 回滚计划

## 📁 文件结构

```
al2-to-al2023-migration/
├── README.md                                    # 本文件
├── SKILL.md                                     # 完整迁移指南
└── scripts/
    ├── check-compatibility.sh                   # 兼容性检查
    ├── generate-al2023-userdata.sh             # 生成用户数据
    ├── migrate-karpenter.sh                    # Karpenter 自动迁移
    └── migrate-managed-nodegroup-bluegreen.sh  # 托管节点组蓝绿迁移
```

## 🚀 典型使用流程

### 场景 1：使用 Karpenter（推荐）

```bash
# 1. 检查兼容性
./scripts/check-compatibility.sh

# 2. 执行迁移（5分钟操作 + 20分钟等待）
./scripts/migrate-karpenter.sh my-cluster default

# 3. 监控迁移进度
kubectl get nodes -o wide
kubectl logs -f -n karpenter -l app.kubernetes.io/name=karpenter
```

### 场景 2：使用托管节点组

```bash
# 1. 检查兼容性
./scripts/check-compatibility.sh

# 2. 执行蓝绿迁移（30-60分钟）
./scripts/migrate-managed-nodegroup-bluegreen.sh \
  my-cluster \
  al2-nodegroup \
  al2023-nodegroup \
  us-west-2

# 3. 验证后删除旧节点组（脚本会提示）
```

### 场景 3：自管理节点组

参考 `SKILL.md` 中的"自管理节点组迁移"章节，手动操作。

## ⚠️ 重要注意事项

### 必须升级的组件

| 组件 | 最低版本 |
|------|---------|
| VPC CNI | 1.16.2 |
| eksctl | 0.176.0 |

### Java 应用兼容性

AL2023 使用 cgroupv2，需要：
- JDK 8 >= 8u372
- JDK 11 >= 11.0.16
- JDK 15+

### IMDSv2 配置

hostNetwork Pod 需要配置 IMDSv2 hop limit：

```json
"MetadataOptions": {
  "HttpPutResponseHopLimit": 2
}
```

影响组件：
- aws-load-balancer-controller
- cluster-autoscaler
- ebs-csi-driver
- efs-csi-driver

## 🔧 故障排查

### Pod 无法启动

```bash
# 检查事件
kubectl describe pod <pod-name>

# 常见问题：
# 1. Java OOM → 升级 JDK
# 2. 镜像拉取失败 → 检查 ECR 权限
# 3. 存储挂载失败 → 检查 EBS CSI 版本
```

### 节点无法加入集群

```bash
# 检查节点日志
ssh ec2-user@<node-ip>
sudo journalctl -u kubelet -f

# 常见问题：
# 1. UserData 格式错误 → 使用 generate-al2023-userdata.sh 重新生成
# 2. 网络配置问题 → 检查安全组和子网
# 3. IAM 权限问题 → 检查节点角色权限
```

### 更多问题

参考 `SKILL.md` 中的"常见问题排查"章节。

## 📚 参考资源

### 官方文档
- [从 Amazon Linux 2 升级到 Amazon Linux 2023](https://docs.aws.amazon.com/eks/latest/userguide/al2023.html)
- [nodeadm 文档](https://awslabs.github.io/amazon-eks-ami/nodeadm/)
- [EKS AL2 AMI 弃用 FAQ](https://docs.aws.amazon.com/eks/latest/userguide/eks-ami-deprecation-faqs.html)

### 工具
- [eksctl](https://eksctl.io/)
- [Karpenter](https://karpenter.sh/)
- [AWS CLI](https://aws.amazon.com/cli/)

## 🤝 贡献

如果你在迁移过程中遇到问题或有改进建议，欢迎反馈！

## 📝 版本

- **版本**: v1.0
- **最后更新**: 2026-02-11
- **作者**: 基于 AWS 官方文档和社区最佳实践

---

**提示**: 建议先在测试环境完整验证迁移流程后再在生产环境执行。
