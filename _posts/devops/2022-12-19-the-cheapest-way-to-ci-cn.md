---
layout: post
title:  "在 AWS 构建应用 (Gitlab CI) 最便宜的姿势"
date:   2022-12-19 11:40:33 +0800
author: 啤酒云
categories: aws, gitlab, devops, container
---

Graviton 在 AWS 是性价比最高的（最高节约 40%），而 Spot 实例适合任务类型的负载，最高能有 90% 的节省。而 Gitlab Runner 可以轻松将构建任务调度到这种类型的节点上。

## 安装 Gitlab runner

首先，我们需要为 Gitlab runner 打一个标签。这里我设置了标签为 arm。稍后我们会将任务调度到这个 runner。

下面是 CDK 代码:

```ts
cluster.addHelmChart("arm-runner", {
  chart: "gitlab-runner",
  repository: "http://charts.gitlab.io/",
  version: "0.48.0",
  namespace: "gitlab",
  release: "arm-runner",
  createNamespace: false,
  values: {
    runnerRegistrationToken: "<your-runner-token>",
    gitlabUrl: "<your-gitlab-url>",
    privileged: true,
    rbac: {
      create: true,
      rules: [
        {
          apiGroups: [""],
          resources: ["pods"],
          verbs: ["list", "get", "create", "watch", "delete"],
        },
        {
          apiGroups: [""],
          resources: ["pods/exec"],
          verbs: ["create"],
        },
        {
          apiGroups: [""],
          resources: ["pods/log"],
          verbs: ["get"],
        },
        {
          apiGroups: [""],
          resources: ["pods/attach"],
          verbs: ["list", "get", "create", "update", "delete"],
        },
        {
          apiGroups: [""],
          resources: ["secrets"],
          verbs: ["list", "get", "create", "update", "delete"],
        },
        {
          apiGroups: [""],
          resources: ["configmaps"],
          verbs: ["list", "get", "create", "update", "delete"],
        }
      ]
    },
    runners: {
      name: "arm-runner",
      tags: "arm, mass",
      runUntagged: false,
      helpers: {
        image: "gitlab/gitlab-runner-helper:arm64-v14.10.2"
      },
      config: `
    [[runners]]
    name = "arm-runner"
    environment = ["FF_USE_LEGACY_KUBERNETES_EXECUTION_STRATEGY=true"]
    executor = "kubernetes"
    [runners.kubernetes]
      image = "ubuntu:22.04"
      privileged = true
    [[runners.kubernetes.volumes.empty_dir]]
      name = "docker-certs"
      mount_path = "/certs/client"
      medium = "Memory"
    [[runners.kubernetes.volumes.empty_dir]]
      name = "dind-storage"
      mount_path = "/var/lib/docker"
    [[runners.kubernetes.volumes.host_path]]
      name = "hostpath-modules"
      mount_path = "/lib/modules"
      read_only = true
      host_path = "/lib/modules"
    [[runners.kubernetes.volumes.host_path]]
      name = "hostpath-hosts"
      mount_path = "/etc/hosts"
      read_only = true
      host_path = "/etc/hosts"
    [[runners.kubernetes.volumes.host_path]]
      name = "hostpath-cgroup"
      mount_path = "/sys/fs/cgroup"
      host_path = "/sys/fs/cgroup"
    [runners.kubernetes.node_selector]
      "karpenter-arch" = "arm64" 
    `
    },
  }
});
```

配置中需要着重关注以下:

- 在 ARM 环境下，需要指定 gitlab-runner-helper 的镜像，因为 这个镜像是单架构的，而默认的图样使的是 X86 的镜像。这个镜像会作为 构建任务的 sidecar 运行。
- `FF_USE_LEGACY_KUBERNETES_EXECUTION_STRATEGY` 必须设置为 true 才能调度 pod 任务。
- 配置中 `[runners.kubernetes.node_selector]` 是为 K8S 调度做准备的，此处表示后续的构建任务会调度到相应 tag 的 node 节点。

## Karpenter 节点池

[Karpenter](https://karpenter.sh/)  是 AWS 最新的节点伸缩工具，非常好用。

Kapennter 的安装和入门就不做过多说明了。直接看代码：

```yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: arm-builder
spec:
  requirements:
    - key: "karpenter.k8s.aws/instance-category"
      operator: In
      values: ["c", "m", "r"]
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["spot"]
    - key: "kubernetes.io/arch"
      operator: In
      values: ["arm64"]
  limits:
    resources:
      cpu: 1000
  labels:
    karpenter-arch: arm64
  providerRef:
    name: default
  ttlSecondsAfterEmpty: 30

---
apiVersion: karpenter.k8s.aws/v1alpha1
kind: AWSNodeTemplate
metadata:
  name: default
spec:
  amiFamily: Bottlerocket
  subnetSelector:
    "aws:cloudformation:stack-name": gitlab
    "aws-cdk:subnet-type": Private
  securityGroupSelector:
    "kubernetes.io/cluster/gitlab": owned

```

代码说明:

- 创建了节点池(Provisioner)，可以指定节点的机型范围，CPU 类型，付费类型等。指定 arm 就可以选择 Graviton 机型，指定 spot 可以只购买竞价实例。
- 这里建议使用 Bottlerocket 作为 node 的操作系统，使用 Amazon Linux 会抛出一个无法解析 git 仓库的地址的错误。

## Gitlab CI 配置

现在需要将构建任务调度到这个 runner 上。

下面是 .gitlab-ci.yml 的示例：

```yaml
stages:
  - Build

frontend-build:
  stage: Build
  image: node:16.16.0-alpine
  tags:
    - arm
  script:
    - npm install
    - npm run build
  artifacts:
    paths:
      - build/
```

上面的代码很简单，只需要给构建任务指定 tags 标签即可

## 总结

通过以上的三段配置，整体的 CI 流程如下：

触发 Gitlab 构建 -> 寻找有 arm 标记的 runner -> 启动构建任务(pod) -> 寻找 `karpenter-arch: arm64` 的节点 -> 没有符合条件的节点，pod pending -> Karpenter 购买 arm + spot 节点 -> 构建任务开始调度成功 -> 执行构建任务 -> 任务结束，释放 node 节点。

如图：

![Gitlab CI with karpenter](/assets/posts/devops/gitlab-ci-karpenter.png)

Karpenter 会购买最便宜的机型，全新节点的购买时间约 1 分 30 秒。
