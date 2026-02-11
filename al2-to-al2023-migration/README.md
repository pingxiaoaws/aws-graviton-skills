# AL2 到 AL2023 迁移 Skill

帮助你从 Amazon EKS AL2 节点迁移到 AL2023 节点的实战工具集。

## 关键日期

| 日期 | 事件 |
|------|------|
| **2025-11-26** | EKS 优化版 AL2 AMI 停止支持（不再发布更新） |
| **2026-03-26** | K8s 1.32（最后支持 AL2 的版本）标准支持结束 |
| **2026-06-30** | Amazon Linux 2 完全停止维护 |

**Kubernetes 1.33 起完全停止提供 AL2 AMI**，升级到 1.33 时会自动切换至 AL2023。

## 快速决策

```
使用 Karpenter?
├─ 是 → scripts/migrate-karpenter.sh（最简单）
└─ 否 → 托管节点组还是自管理？
   ├─ 托管节点组 → scripts/migrate-managed-nodegroup-bluegreen.sh
   └─ 自管理节点组 → 参考 SKILL.md 手动迁移
```

## 脚本工具

| 脚本 | 用途 |
|------|------|
| `scripts/check-compatibility.sh` | 迁移前兼容性检查（K8s 版本、VPC CNI、Java cgroupv2、IMDS、GPU/Neuron） |
| `scripts/generate-al2023-userdata.sh` | 生成 AL2023 节点的 MIME + NodeConfig 用户数据 |
| `scripts/migrate-karpenter.sh` | Karpenter 一键迁移（更新 EC2NodeClass，自动滚动替换） |
| `scripts/migrate-managed-nodegroup-bluegreen.sh` | 托管节点组蓝绿迁移（零停机） |

### 使用示例

```bash
# 1. 检查兼容性
./scripts/check-compatibility.sh

# 2a. Karpenter 迁移
./scripts/migrate-karpenter.sh my-cluster default

# 2b. 或托管节点组蓝绿迁移
./scripts/migrate-managed-nodegroup-bluegreen.sh my-cluster al2-ng al2023-ng us-west-2
```

## 文件结构

```
al2-to-al2023-migration/
├── README.md          # 快速入门（本文件）
├── SKILL.md           # 完整迁移指南（详细步骤、原理、排查）
└── scripts/
    ├── check-compatibility.sh
    ├── generate-al2023-userdata.sh
    ├── migrate-karpenter.sh
    └── migrate-managed-nodegroup-bluegreen.sh
```

## 详细文档

完整指南请参考 [SKILL.md](SKILL.md)，包含：
- 迁移前准备清单（VPC CNI、cgroupv2、IMDS、GPU/CUDA）
- 三种迁移方案详解（Karpenter / 托管节点组 / 自管理节点组）
- AL2023 用户数据格式（nodeadm / NodeConfig）
- SOCI 镜像懒加载加速
- 常见问题排查与回滚方案

## 参考资源

- [AL2 到 AL2023 迁移文档](https://docs.aws.amazon.com/eks/latest/userguide/al2023.html)
- [nodeadm 文档](https://awslabs.github.io/amazon-eks-ami/nodeadm/)
- [EKS AL2 AMI 弃用 FAQ](https://docs.aws.amazon.com/eks/latest/userguide/eks-ami-deprecation-faqs.html)
- [eksctl](https://eksctl.io/) | [Karpenter](https://karpenter.sh/)
