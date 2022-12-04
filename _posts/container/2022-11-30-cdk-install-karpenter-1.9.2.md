---
layout: post
title:  使用 CDK 安装 Karpenter 新版
date:   2022-11-30 21:49:06 +0800
categories: container, iac, aws, cloud-provider
---

本文记录了使用 CDK (2.53.0) 安装 Karpenter (v0.19.2) 的方法。

## CDK 和 Karpenter 分别是什么

这个问题先不细说了吧，后面会发文章补。

可以去相应官方网站查看：

[CDK](https://aws.amazon.com/cn/cdk/)

[Karpenter](https://karpenter.sh/)

反正好有一比：

- CDK 类似于 terraform。
- Karpenter 就是 K8S 的节点伸缩器。

## 适用性

CDK 和 Karpenter 当下这个时间点正在以天为单位 **疯狂发版**，所以这篇文章具有时效性。

当前最新版本为：

CDK 的版本为：**2.53.0**

Karpenter 的版本为： **v0.19.2**

## Show me the code

先上代码为敬！

```ts
import { Cluster, HelmChart, KubernetesManifest } from "aws-cdk-lib/aws-eks";
import { CfnInstanceProfile, CfnServiceLinkedRole, IRole, ManagedPolicy, PolicyDocument, Role, ServicePrincipal } from "aws-cdk-lib/aws-iam";

const KarpenterControllerPolicy = {
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateLaunchTemplate",
        "ec2:CreateFleet",
        "ec2:RunInstances",
        "ec2:CreateTags",
        "ec2:TerminateInstances",
        "ec2:DeleteLaunchTemplate",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeInstances",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeAvailabilityZones",
        "ssm:GetParameter",
        "pricing:GetProducts",
        "ec2:DescribeSpotPriceHistory",
        "sqs:DeleteMessage",
        "sqs:GetQueueUrl",
        "sqs:GetQueueAttributes",
        "sqs:ReceiveMessage",
        "iam:PassRole",
      ],
      "Resource": "*"
    }
  ]
};


export class KarpenterAddon {
  cluster: Cluster;
  constructor(cluster: Cluster) {
    this.cluster = cluster;


    this.createNodeRole();
    this.createKarpeter();
  }

  createNodeRole() {
    new CfnServiceLinkedRole(this.cluster, 'SpotSLR', {
      awsServiceName: 'spot.amazonaws.com',
    });
    const karpenterNodeRole = new Role(this.cluster, 'karpenter-node-role', {
      assumedBy: new ServicePrincipal(`ec2.${this.cluster.stack.urlSuffix}`),
      managedPolicies: [
        ManagedPolicy.fromAwsManagedPolicyName("AmazonEKSWorkerNodePolicy"),
        ManagedPolicy.fromAwsManagedPolicyName("AmazonEKS_CNI_Policy"),
        ManagedPolicy.fromAwsManagedPolicyName("AmazonEC2ContainerRegistryReadOnly"),
        ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMManagedInstanceCore"),
      ],
      roleName: 'KarpenterNodeRole-' + this.cluster.clusterName
    });

    new CfnInstanceProfile(this.cluster, 'karpenter', {
      roles: [karpenterNodeRole.roleName],
      instanceProfileName: 'KarpenterNodeInstanceProfile-' + this.cluster.clusterName
    });

    this.cluster.awsAuth.addRoleMapping(karpenterNodeRole, {
      groups: ['system:bootstrapper', 'system:nodes'],
      username: 'system:node:{{EC2PrivateDNSName}}'
    });
  }

  createKarpeter() {

    const ns = new KubernetesManifest(this.cluster, "karpenter-ns", {
      cluster: this.cluster,
      manifest: [{
        apiVersion: 'v1',
        kind: 'Namespace',
        metadata: {
          name: 'karpenter',
        }
      }],
      overwrite: true,
      prune: true
    });

    const sa = this.cluster.addServiceAccount("karpenter-sa", {
      name: 'karpenter',
      namespace: 'karpenter'
    });
    sa.role.addManagedPolicy(new ManagedPolicy(this.cluster, 'karpenter-node-policy', {
      document: PolicyDocument.fromJson(KarpenterControllerPolicy),
    }))
    sa.node.addDependency(ns);

    const helm = new HelmChart(this.cluster, "karpenter-chart", {
      cluster: this.cluster,
      namespace: 'karpenter',
      chart: 'oci://public.ecr.aws/karpenter/karpenter',
      repository: 'oci://public.ecr.aws/karpenter/karpenter',
      release: "karpenter",
      version: "v0.19.2",
      values: {
        serviceAccount: {
          create: false,
          name: "karpenter"
        },
        "serviceAccount.annotations": {
          "eks.amazonaws.com/role-arn": sa.role.roleArn
        },
        settings: {
          aws: {
            clusterEndpoint: this.cluster.clusterEndpoint,
            clusterName: this.cluster.clusterName,
            defaultInstanceProfile: 'KarpenterNodeInstanceProfile-' + this.cluster.clusterName,
          }
        }
      }
    });
    helm.node.addDependency(ns);
    helm.node.addDependency(sa);
  }
}
```

上面的代码大概过程如下：

- 创建一个角色，这个拥有角色有 `AmazonEKSWorkerNodePolicy` `AmazonEKS_CNI_Policy` `AmazonEC2ContainerRegistryReadOnly` `AmazonSSMManagedInstanceCore` 几个预设策略。 未来 Kapenter 会将这个角色赋予 Node。
- 在 karpenter 这个命名空间下创建一系列资源，包括：
  - IRSA：将 K8S 的 Service Account 与 IAM 的 Role 建立关联。
  - 通过 Helm 安装 Karpenter。

## 上面代码的坑

坑主要集中在 Helm 图样的安装：

1. CDK 的 HelmChart 对于 oci 库的支持处于起步阶段，经过多次试验以及阅读相关源码，才确认写法：`chart: 'oci://public.ecr.aws/karpenter/karpenter'`，`repository: 'oci://public.ecr.aws/karpenter/karpenter'`。
2. Karpenter HelmChart 对于 values 的写法，这个和官网不一样，如果按照 terraform 的写法会完全无效，terraform 的写法是："settings.aws.clusterEndpoint"，而这里的写法**必须是** JSON 格式。
