---
layout: post
title:  "The cheapest way to build applications (Gitlab CI) on AWS"
date:   2022-12-18 20:59:33 +0800
author: 啤酒云
categories: aws, gitlab, devops, container
---

Graviton (ARM) is the most cost-effective in AWS (up to 40% savings), while Spot instances are suitable for task-type workloads and can save up to 90%. Gitlab Runner can easily schedule build tasks to Graviton + Spot instances.

## Config Gitlab runner

First, we need to tag the Gitlab runner. Here I set the tag to arm. Later we will schedule the task to the runner.

Here is the CDK code:

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

Some notices:

- Under ARM env, we need to specify the gitlab-runner-helper image, because the helper image is single-arch, default pattern is X86. This image will run as a sidecar for the build task.
- `FF_USE_LEGACY_KUBERNETES_EXECUTION_STRATEGY` must be sett to true to execute pod.
- `[runners.kubernetes.node_selector]` is prepared for K8S pod scheduling, which means the build tasks will be scheduled to the node node of the corresponding tag.

## Karpenter Provisioner

[Karpenter](https://karpenter.sh/) is a K8S node auto scaler built by AWS.

Here is the Karpenter Provisioner code.

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

Notices:

- You can specify instance categories, CPU types, payment types, etc.
- We choose arm cpu and spot capacity type, this combination is the cheapest.
- It is recommended to use Bottlerocket as the os of node. Using Amazon Linux will throw an error that "Cannot resolve DNS address of the git repository".

## Gitlab CI config

Now we need to schedule the build task to this runner.

Here is an example `.gitlab-ci.yml` code:

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

You only need to specify the tags for the build task.

## Summary

Through the above three configurations, the overall CI process is as follows:

Trigger Gitlab build -> Look for runner with arm tag -> Start build task (pod) -> Look for `karpenter-arch: arm64` node -> No arm node, pod pending -> Karpenter purchase arm + spot node -> The build task starts -> The task ends and the node is released.

As shown in the figure below:

![Gitlab CI with karpenter](/assets/posts/devops/gitlab-ci-karpenter.png)

A whole new node purchase time is about 1 min 30s, Karpenter will always look for the cheapest instance.
