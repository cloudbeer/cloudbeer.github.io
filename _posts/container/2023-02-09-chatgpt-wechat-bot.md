---
layout: post
title:  一个现成的 ChatGPT 微信机器人
date:   2023-02-09  10:09:00 +0800
author: 啤酒云
categories: container, aws
tags: 容器
---

本文是一个集成了 ChatGPT 的简单微信机器人的部署文档，使用了现有的 github 仓库，并进行适当修改，并发布成公共镜像包。当前文档说明为 1.0 镜像包。

## 说明

在这个项目（<https://github.com/wangrongding/wechat-bot>）的基础上进行的修改：

- 从 openai 改成了 chatgpt 的调用。
- 修改了 chatgpt 的对话模型，现在会按照群和发送人整合成独立的对话 session。
- 去掉了白名单，单聊等功能等，改成 **只支持群聊** 。

镜像地址：

<https://hub.docker.com/r/cloudbeer/wx-chatbot/tags>

## 部署

### 在 K8S 中部署

部署 YAML 参考如下：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wx-chatbot
  labels:
    app: wx-chatbot
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wx-chatbot
  template:
    metadata:
      labels:
        app: wx-chatbot
    spec:
      containers:
        - name: wx-chatbot
          image: cloudbeer/wx-chatbot:1.0
          env:
            - name: OPENAI_API_KEY
              value: [your-api-key]
            - name: BOT_NAME
              value: [your-bot-name]
          command:
            - node
            - index.js
```

修改上面代码中的环境变量 `[your-api-key]`, `[your-bot-name]`：

- OPENAI_API_KEY: 在 openai 网站申请的 API_KEY，当前申请地址是： <https://platform.openai.com/account/api-keys>

- BOT_NAME: 机器人的名字，当在群里发送以这个名字开头的文字的时候，会调用 chatgpt，如 BOT_NAME 为 `hisiri` 的时候，发送：`hisiri 你好` 会得到 ChatGPT 的响应。

部署完成之后，使用 logs 命令查看二维码，相关的命令如下：

```shell
kubectl logs wx-chatbot-xxxxxxx -f
```

- -f 可以持续打印日志，查看控制台信息。
- 使用微信扫码之后，当前微信会成为 ChatGPT 机器人。

## Docker 启动

Docker 启动不再赘述，使用如下命令即可：

```bash
docker run --rm -it --name wx-chatgpt-bot \
  -e OPENAI_API_KEY=abc -e BOT_NAME=@siri \
  cloudbeer/wx-chatbot:1.0 node index.js
```

- 记得修改两个环境变量：`-e OPENAI_API_KEY=abc -e BOT_NAME=@siri`。
- 注意：此命令在 MAC 启动有bug，稍后修正。

## 问题和改进点

- 免费账号 ChatGPT 测会经常报 429 Too Many Requests 的错误。当前版本遇到此错误的时候没有回复，下一个版本会增加机器人对错误的响应。
- 微信可能会被封，建议使用新注册的微信小号作为机器人。（暂且不清楚微信侧触发机制）
- 重启应用会重新加载微信的会话，导致重复调用 ChatGPT API。
