---
layout: post
title:  "TLS 1.1 过期后上传 S3 的策略"
date:   203-05-07 10:13:33 +0800
author: 啤酒云
categories: aws
---

TLS 1.1 近期全面过期，有些老的设备还在使用，如何最小代价升级客户端应用？这里实验了 2 种方法：改用 http 或者使用 Cloudfront。

## 使用 http

如果您在客户端使用了 S3 的域名，直接把 https 变成 http 即可。

上传文件的过程，得到 S3 签名 url 之后，直接使用 http 亦可以完成上传操作。

## 使用 Cloudfront 上传 S3

目前 Cloudfront 还会长期支持 TLS 1.1。

Cloudfront 一般用于 S3 文件的读取，此处沿用原来的方式即可。

如果您必须使用 https 上传文件，可以 via Cloudfront，可按照如下方式操作：

1 创建一个 新的 Origin，指向 目标 S3 存储桶。

2 创建新的 behavior，指向刚刚创建的 Origin。

2.1 behavior 里要 Restrict viewer access 打开，这样就可以使用 Cloudfront 签名进行文件上传了。

## Cloudfront 签名上传的实验过程

打开 Restrict viewer access 需要创建一个 key。

### 创建 key

创建（本地/上传文件的客户机）key：

```ssh
cd ~/.ssh
openssl genrsa -out cf.pem 2048
openssl rsa -pubout -in cf.pem -out cf.pub.pem
```

这样可以得到两个文件：

- cf.pem 私钥
- cf.pub.pem 公钥

在 Cloudfront 的 [Key managenent 的 Public keys](https://console.aws.amazon.com/cloudfront/v3/home?#/publickey) 里上传 cf.pub.pem 的内容。

并在 Key groups 里创建一个组，把这个 Public key 加入。

### 创建 Origin

我之前已经创建了对外的读操作的 Cloudfront，现在已有的分发下面继续创建一个 Origin。

- 选择目标 S3 domain
- Origin access: Origin access control settings (recommended)

如果之前没有配置过 S3 的策略，需要按照页面指示，把 policy 配置过去。

### 创建 Behavior

- Path pattern: /upload
- Origin: 选上一步创建的 Origin
- Allowed HTTP methods: GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE
- Restrict viewer access: Yes
- Key groups 将之前创建的 Key group 加入
- Response headers policy: 选择 SimpleCORS （此处为了方便浏览器测试）

### 测试

直接上传：

```request
PUT https://xxxxxxxxxx.cloudfront.net/upload/6.png
Content-Type: multipart/form-data;

< ./1.png
```

报 403 错误

使用签名 URL 上传

使用 aws cli 进行签名：

```shell
aws cloudfront sign --url https://xxxxxxxxx.cloudfront.net/upload/6.png \
  --key-pair-id KXXXXXEDPH5 \
  --private-key file://~/.ssh/cf.pem \
  --date-less-than 2024-11-11
```

- key-pair-id 是 Cloudfront 后台给你的 Key Pair ID
- private-key 是本地文件路径，必须以 file:// 开始

现在上传测试：

```request
PUT https://d20x1q1mghmz4k.cloudfront.net/upload/6.png?Expires=1731283200&Signature=sj0ykX4c-fmSdXfKDnfeNZbkF7p-twG6VHAvs7BK6oSrycXWITvwkLQm0zNIkM3qX1NdR7D1eMANklGZTfuE916M~Kxgpa0M38tJ13KPCbpY9WqmyxvARyJz7JOOM3xOpB2AlvbVFvjTJAtGGGRHpXoepWPCXvXY3aszsPmeql7a-TADdvWRm8u4TpVBkLcTl3XDXcVl3lXAJmsonkFFXhDENVp42zfL3EhUINdciGO5JsjeTMAe1f9cGVVgfBc9CBnBPdDq6wom57qy~Tl5OnXY8kfi1RoIabbQ93cPUhfqZouoGOutDvUbPUYw5cnuZYSo0Lz7WgN~w7AtGJuV3Q__&Key-Pair-Id=K2R1WNDACEDPH5
Content-Type: multipart/form-data;

< ./1.png
```

成功上传。

> 我这里的 http request 使用的是 VSCODE 的插件 REST Client

我这里使用了路径 /upload 作为测试路径，当前会把文件上传到 S3 存储桶的 /upload 路径下，并且这个路径下的所以文件都要签名。

如果真实生产环境，可以新建一个 Cloudfront 分发专门用来上传文件，或者使用 rewrite 来重新 /upload 路径。

---
参考：

[为 Cloudfront 设置密钥对](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-trusted-signers.html#private-content-creating-cloudfront-key-pairs)

[aws cloudfront sign](https://docs.aws.amazon.com/cli/latest/reference/cloudfront/sign.html)
