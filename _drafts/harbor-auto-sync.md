---
layout: post
title:  "Harbor 同步功能体验"
date:   1977-12-04 22:13:33 +0800
author: 啤酒云
categories: container
---

Harbor 是 CNCF 已经毕业的项目，用于容器镜像和 Helm 图样的存储，ta 有一个比较优秀的功能是可以将散落四处的镜像集中起来，并自动同步，适合那些无法使用统一镜像仓库的企业。

## 简易安装

如果未设置密码，Harbor 的默认管理面账号是：

admin/Harbor12345

进入之后记得修改密码。

> 请注意，此安装方式仅限功能验证，不能用于生产环境。
> 生产环境建议配置 托管 postgres 和 redis, 并将存储配置到 S3

## 同步功能设置

Harbor 支持主流的镜像仓库，包括：

- Alibaba ACR
- Artifact Hub
- Aws ECR
- Azure ACR
- Docker Hub
- Docker Registry
- DTR
- Github GHCR
- Gitlab
- Google GCR
- Harbor
- Helm Hub
- Huawei SWR
- JFrog Artifactory
- Quay
- Tencent TCR

进入系统管理 -> 仓库管理，点击 新建目标

### Docker Hub 公开镜像

先试试 scratch 镜像

仓库管理

- 提供者：选择 Docker Hub
- 目标名称：docker-hub-public

单击测试连接，显示成功，点击确定。

复制管理 -> 新建规则

由于当前 Harbor 未配置 SSL 证书，所以在本地 Docker 引擎中需要增加如下配置：`"insecure-registries": ["http://harbor.abig.fun"]`

打开 Docker 桌面版菜单，选择 Settings -> Docker Engine，整体配置大约如下：

```json
{
  "builder": {
    "gc": {
      "defaultKeepStorage": "20GB",
      "enabled": true
    }
  },
  "experimental": false,
  "features": {
    "buildkit": true
  },
  "insecure-registries": ["http://harbor.abig.fun"]
}
```

登录到 Harbor，可以使用 admin 用户：

```shell
docker login harbor.abig.fun
```
