---
layout: post
title:  "AWS CDK 入门：Hello World"
date:   2022-12-04 19:54:44 +0800
author: 啤酒云
categories: iac, aws
tags: cdk
---

本文是 AWS CDK 入门教程，将利用 "渐进" 模式 使用 AWS CDK 生产一个生产可用的 EKS 集群。本文是上半部分，CDK 入门知识。

## IaC 和 CDK 简介

### 什么是 IaC？

这段来自：<https://www.redhat.com/zh/topics/automation/what-is-infrastructure-as-code-iac>

> 基础设施即代码（IaC）是通过代码而非手动流程来管理和置备基础设施的方法。
>
> 利用 IaC 我们可以创建包含基础设施规范的配置文件，从而便于编辑和分发配置。此外，它还可确保每次置备的环境都完全相同。通过对配置规范进行整理和记录，IaC 有助于实现配置管理，并避免发生未记录的临时配置更改。
>
> 版本控制是 IaC 的一个重要组成部分，就像其他任何软件源代码文件一样，配置文件也应该在源代码控制之下。以基础设施即代码方式部署还意味着您可以将基础架构划分为若干模块化组件，它们可通过自动化以不同的方式进行组合。
>
> 借助 IaC 实现基础架构置备的自动化，意味着开发人员无需再在每次开发或部署应用时手动置备和管理服务器、操作系统、存储及其他基础架构组件。对基础架构编码即可创建一个置备用的模板，尽管置备过程仍然可以手动完成，但也可以由自动化工具（例如红帽® Ansible® 自动化平台）为您代劳。

简要来说就是：使用描述性的代码管理您的基础设施。

### 什么是 CDK？

这段来自：<https://aws.amazon.com/cn/getting-started/guides/setup-cdk/>

> AWS CDK 是一个开源软件开发框架，可让您使用熟悉的编程语言 (如 JavaScript、TypeScript、Python、Java、C# 和 Go) 定义云应用程序资源。您编写的代码转换为 CloudFormation (CFN) 模板，可使用 [AWS CloudFormation](https://aws.amazon.com/cn/cloudformation/) 创建基础设施。

这个也总结一下：CDK 就是 AWS 的 IaC，他依赖 Cloudformation，可以用常用的语言来描述您的基础设施。

## 安装和设置 AWS CDK

我习惯使用命令行的方式运行，如 `cdk deploy`。cdk 这个命令其实是一个 nodejs 程序。

nodejs 安装就不说了，现在国内有很多开源镜像，如：<https://mirrors.tuna.tsinghua.edu.cn/nodejs-release>，请安装版本 >= 10.3.0 的。

nodejs 安装完成后，就可以安装 cdk 命令行：

```shell
npm i -g aws-cdk
```

默认安装完成后 CDK 就是全局命令行了。

CDK 同时要依赖 AWS CLI 以及 AWS 凭证。

安装 AWS CLI 参考：<https://docs.aws.amazon.com/zh_cn/cli/latest/userguide/getting-started-install.html>

在开发环境配置凭证：<https://docs.aws.amazon.com/zh_cn/cli/latest/userguide/cli-configure-quickstart.html>

## Hello World

开发环境都设置好了！

首先新建一个目录：

```shell
mkdir cdk-demo && cd cdk-demo
```

初始换项目，使用 typescipt 语言:

```shell
cdk init app --language typescript
```

- 选择 typescipt 语言，是因为 cdk 的文档最多最全的是 typescipt 语言，包括 api 和 示例。

等若干分钟（会依赖您依赖包的下载速度）之后，打开 lib/cdk-workshop-stack.ts，默认示例代码可以看出，创建了一个 sqs 的 Queue 资源。

```ts
export class CdkWorkshopStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    const queue = new sqs.Queue(this, 'CdkWorkshopQueue', {
      visibilityTimeout: Duration.seconds(300)
    });

    const topic = new sns.Topic(this, 'CdkWorkshopTopic');

    topic.addSubscription(new subs.SqsSubscription(queue));
  }
}
```

对于新环境，需要运行:

```shell
cdk bootstrap
```

- 此命令在同一个账号和 region 中只需执行一次。

通过 list 命令可以查看 stack。

```shell
cdk ls
```

运行部署：

```shell
cdk deploy
```

- 此命令执行后，会有资源改变列表，并询问是否确认部署。
- 检查无误后，输入 y

待执行完成后，检查是否真的创建出了 SQS 资源。

清理资源：

```shell
cdk destroy
```

验证完成之后，请及时使用 cdk destroy 清理资源，否则会**产生费用**。

使用 cdk destroy 删除更干净。

## 关于“渐进式”

在本文的简介中，提出了 IaC/CDK 是“渐进式”的，这个主要是指 IaC 在执行的过程中，会存储当前执行的状态，并且能够回滚，叠加，删除。

而且在实际运行的过程中，我们也可以使用 “渐进式” 的模式来操作，特别是在测试某个安装的情况下，可以一步一步执行，当执行失败的时候不至于全部回滚。

比如，我们可以先创建一个 VPC：

```ts
    const vpc = new Vpc(this, 'EKSVpc', {
      ipAddresses: IpAddresses.cidr('10.10.0.0/16')
    });
```

此时 我们可以先执行这段程序:`cdk deploy`。

然后，我们加入新的代码，继续创建了一个 eks。

```ts
    const vpc = new Vpc(this, 'EKSVpc', {
      ipAddresses: IpAddresses.cidr('10.10.0.0/16')
    });
    const eksCluster = new Cluster(this, 'EKSCluster', {
      clusterName: "cdk-workshop",
      vpc,
      albController: {
        version: AlbControllerVersion.V2_4_1,
      },
      defaultCapacity: 1
    });
```

然后继续执行 `cdk deploy`，此时执行引擎会去比较当前的资源描述和当前 state 的异同，并开始创建 eks。

如果 eks 创建失败，整个过程会回滚，此时状态会回滚到 eks 创建之前，也就是说 vpc 还在。

同理，如果想要删除 eks，只需要删除相应的 eks resource 代码即可。
