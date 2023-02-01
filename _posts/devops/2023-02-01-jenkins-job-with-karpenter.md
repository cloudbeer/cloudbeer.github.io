---
layout: post
title:  "调度 Jenkins 任务到 Karpenter 节点池"
date:   2023-01-02 15:12:33 +0800
author: 啤酒云
categories: devops, container
---

本文介绍了如何调度 Jenkins 任务到 EKS 集群的 Karpenter 虚拟节点。Karpenter 强大的 Node 组织能力，可以最大程度节约任务运行的成本。

## 插件配置

首先确认 Jenkins 的 Kubernetes 插件已经安装:

以管理员身份进入 Manage Jenkins -> Manage Plugins, 搜索 Kubernetes，确认插件已经安装。

然后，进行 Node 配置:

进入 Manage Jenkins -> Manage Nodes and Clouds -> Config Clouds, 展开 Kubernetes Cloud details...

如果您的 Jenkins 安装在 EKS 集群里，并且工作任务也要调度到这个集群，可以按照如下配置：

- Kubernetes 地址: <https://kubernetes.default>
- Kubernetes 命名空间: jenkins
- Jenkins 地址: <http://jenkins.jenkins.svc.cluster.local:8080>
- Jenkins 通道: jenkins-agent.jenkins.svc.cluster.local:50000

如果是非本地集群，还需要配置合适的地址和权限。

## 任务配置

现在在项目（业务）根目录编写如下的一个 Jenkinsfile：

```groovy
podTemplate(yaml: '''
    apiVersion: v1
    kind: Pod
    spec:
      nodeSelector:
        karpenter-arch: arm64
      containers:
      - name: maven
        image: maven
        command:
        - sleep
        args:
        - 99d
      - name: golang
        image: golang
        command:
        - sleep
        args:
        - 99d
''') {
    node(POD_LABEL) {
      stage('Get a Maven project') {
        container('maven') {
          stage('Build a Maven project') {
            sh 'mvn --version'
          }
        }
      }

      stage('Get a Golang project') {
        git url: 'https://github.com/aws-code-sample/demo-jenkins.git', branch: 'main'
        container('golang') {
          stage('Build a Go project') {
            sh '''
            go version
            ls
          '''
          }
        }
      }
    }
}
```

在上面的代码中 Pod 的描述中，有一个 `nodeSelector: {karpenter-arch: 'arm64'}` 的选择器，表示这个 Pod 要部署到有 karpenter-arch: 'arm64' 标签的节点。这个节点是通过 Karpenter 来定义的，具体如下：

```yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: arm-builder
spec:
  requirements:
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
  ttlSecondsAfterEmpty: 90

---
apiVersion: karpenter.k8s.aws/v1alpha1
kind: AWSNodeTemplate
metadata:
  name: default
spec:
  amiFamily: Bottlerocket
  subnetSelector:
    "aws:cloudformation:stack-name": CdkEksPocStack
    "aws-cdk:subnet-type": Private
  securityGroupSelector:
    "kubernetes.io/cluster/poc-eks": owned
```

通过 Karpenter，我们可以动态去购买 ARM + Spot 的实例。

现在在 Jenkins 的 Web UI 上新建一个 Jenkins 任务。

选择 “多分支流水线”，我的 demo 中主要字段配置如下：

分支源

- 项目仓库地址：<https://github.com/aws-code-sample/demo-jenkins>

Build Configuration

- Mode: By Jenkinsfile

- 脚本路径: Jenkinsfile

## 运行结果

点击 “立即构建” 后，可以看到如下日志（部分）：

```text
Started by user Jenkins Admin
 > git rev-parse --resolve-git-dir /var/jenkins_home/caches/git-cfff1181f69195f8b158693b85c23bf9/.git # timeout=10
Setting origin to https://github.com/aws-code-sample/demo-jenkins
...
Seen branch in repository origin/main
Seen 1 remote branch
Obtained Jenkinsfile from b7f6d7cb4db0b89577a60faf5023d710798311e9
[Pipeline] Start of Pipeline
[Pipeline] podTemplate
[Pipeline] {
[Pipeline] node
Created Pod: kubernetes jenkins/demo-jenkins-main-10-1kw6t-mzbkc-6r4qk
Still waiting to schedule task
‘demo-jenkins-main-10-1kw6t-mzbkc-6r4qk’ is offline

Running on demo-jenkins-main-10-1kw6t-mzbkc-6r4qk in /home/jenkins/agent/workspace/demo-jenkins_main
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Get a Maven project)
[Pipeline] container
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Build a Maven project)
[Pipeline] sh
+ mvn --version
Apache Maven 3.8.7 (b89d5959fcde851dcb1c8946a785a163f14e1e29)
Maven home: /usr/share/maven
Java version: 17.0.6, vendor: Eclipse Adoptium, runtime: /opt/java/openjdk
Default locale: en_US, platform encoding: UTF-8
OS name: "linux", version: "5.15.79", arch: "aarch64", family: "unix"
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // container
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Get a Golang project)
[Pipeline] git
Selected Git installation does not exist. Using Default
The recommended git tool is: NONE
No credentials specified
Cloning the remote Git repository
Cloning repository https://github.com/aws-code-sample/demo-jenkins.git
 > git init /home/jenkins/agent/workspace/demo-jenkins_main # timeout=10
Fetching upstream changes from https://github.com/aws-code-sample/demo-jenkins.git
 > git --version # timeout=10
 > git --version # 'git version 2.30.2'
 > git fetch --tags --force --progress -- https://github.com/aws-code-sample/demo-jenkins.git +refs/heads/*:refs/remotes/origin/* # timeout=10
Avoid second fetch
Checking out Revision b7f6d7cb4db0b89577a60faf5023d710798311e9 (refs/remotes/origin/main)
 > git config remote.origin.url https://github.com/aws-code-sample/demo-jenkins.git # timeout=10
 > git config --add remote.origin.fetch +refs/heads/*:refs/remotes/origin/* # timeout=10
 > git rev-parse refs/remotes/origin/main^{commit} # timeout=10
 > git config core.sparsecheckout # timeout=10
 > git checkout -f b7f6d7cb4db0b89577a60faf5023d710798311e9 # timeout=10
 > git branch -a -v --no-abbrev # timeout=10
 > git checkout -b main b7f6d7cb4db0b89577a60faf5023d710798311e9 # timeout=10
Commit message: "sh"
 > git rev-list --no-walk b7f6d7cb4db0b89577a60faf5023d710798311e9 # timeout=10
[Pipeline] container
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Build a Go project)
[Pipeline] sh
+ go version
go version go1.19.5 linux/arm64
+ ls
Jenkinsfile
readme.md
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // container
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // node
[Pipeline] }
[Pipeline] // podTemplate
[Pipeline] End of Pipeline
Finished: SUCCESS
```

从上述 log 中，可以看到运行过程如下：

- 任务启动后，由于没有合适的 Node 可以选择，pod offline。
- 此时 Karpenter 购买 EC2 并安装 OS 和必要 pod，此过程大约 90 秒左右。
- 然后启动任务，从输出结果中可以看到 使用了 arm 架构（aarch64 或 arm64）
- 描述 node（或在 AWS 控制台）可显示相应的 EC2 为 Spot 实例。

---

相关阅读：

[Jenkins 的 Kubernetes 插件](https://plugins.jenkins.io/kubernetes/)

[Karpenter 官网](https://karpenter.sh/)

[在 AWS 构建应用 (Gitlab CI) 最便宜的姿势](https://youbug.cn/2022/12/the-cheapest-way-to-ci-cn.html)

[使用 CDK 安装 Karpenter 新版](https://youbug.cn/2022/11/cdk-install-karpenter-1.9.2.html)
