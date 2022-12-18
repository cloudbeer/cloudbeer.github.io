---
layout: post
title:  使用 terraform 增加 EKS 组件
date:   2022-12-07 20:54:44 +0800
author: 啤酒云
categories: iac, aws, container
tags: iac, container, aws, terraform
---

在已经开通了 EKS 的情况下，使用 terraform 给 EKS 集群安装组件。

## 常用 SDK

操作 EKS 的常用 SDK 如下：

```terraform
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.40.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.15.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.7.1"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}
```

- hashicorp/aws: 操作 aws 资源
- hashicorp/kubernetes: 操作 k8s 资源
- hashicorp/helm: 操作 helm 图样
- gavinbunney/kubectl: 被广泛采用的个人工具，可以支持单资源 kubectl 操作

## 先决条件

对于已经创建资源，在 terraform 中，通常使用 data 去查询，如下代码，只需要指定 集群的 名字就可以查询到集群的信息：

```terraform
data "aws_eks_cluster" "main" {
  name = var.cluster_name
}
```

对于 helm 和 kubectl 工具，我们需要为其配置相应的权限：

```terraform
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority.0.data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
      command     = "aws"
    }
  }
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority.0.data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
    command     = "aws"
  }
}
```

## 使用 helm 安装组件

使用 helm 安装非常简单，参照 helm 图样的说明即可，传入相应的参数.

下面的代码是在集群内安装 Gitlab 的示例：

```terraform
variable "namespace" {
  type    = string
  default = "gitlab"
}

variable "name" {
  type    = string
  default = "gitlab"
}

variable "domain" {
  type = string
}

resource "helm_release" "gitlab" {
  namespace        = var.namespace
  create_namespace = true
  name             = var.name
  repository       = "https://charts.gitlab.io/"
  chart            = "gitlab"
  version          = "6.5.5"

  set {
    name  = "global.ingress.enabled"
    value = false
  }
  set {
    name  = "global.ingress.configureCertmanager"
    value = false
  }
  set {
    name  = "gitlab.certmanager.install"
    value = false
  }
  set {
    name  = "gitlab.prometheus.install"
    value = false
  }
  set {
    name  = "gitlab.grafana.install"
    value = false
  }
  set {
    name  = "nginx-ingress.enabled"
    value = false
  }
  set {
    name  = "gitlab-runner.enabled"
    value = false
  }
  set {
    name  = "global.hosts.domain"
    value = var.domain
  }
}
```

## 使用 kubectl 安装组件

下面的示例安装了 argocd，使用了官网的默认安装方法，使用 kubectl 直接执行 yaml 文件。

```terraform
variable "namespace" {
  type    = string
  default = "argocd"
}

resource "kubectl_manifest" "argocd_namepsace" {
  yaml_body = <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${var.namespace}
YAML
}
```

在集群内创建了一个 namespace。

由于 kubectl_manifest 只能执行单资源，象 argocd 给出的 yaml 文件里，包含了很多的资源，此时需要使用 `kubectl_file_documents` 将一大段资源解构成单个资源数组。

```terraform

data "http" "argocd_yaml" {
  url = "https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
}

data "kubectl_file_documents" "argocd_docs" {
  content = data.http.argocd_yaml.response_body
}
```

然后循环执行即可：

```terraform
resource "kubectl_manifest" "argocd" {
  for_each           = data.kubectl_file_documents.argocd_docs.manifests
  yaml_body          = each.value
  override_namespace = var.namespace
}
```
