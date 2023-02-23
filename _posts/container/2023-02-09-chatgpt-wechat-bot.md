---
layout: post
title:  一个现成的 ChatGPT 微信机器人
date:   2023-02-09  19:09:00 +0800
author: 啤酒云
categories: container
tags: 容器
---

本文是一个集成了 ChatGPT 的简单微信机器人的部署文档，使用了现有的 github 仓库，并进行适当修改，并发布成公共镜像包。当前文档说明为 2.0 镜像包。

## 说明

在这个项目（<https://github.com/wangrongding/wechat-bot>）的基础上进行的修改：

- 从 openai 改回了 chatgpt 的调用。
- 修改了 chatgpt 的对话模型，现在有两种机器人: 群机器人和私人机器人。
- 在群里，用群机器人开头的文字会训练群机器人，用私人机器人名字开头的可以训练私有机器人。
- 与机器人私聊也要以机器人的名字开头，私聊的时候用两种机器人名字开头都会训练私有机器人。
- 增加了错误处理，当出错的时候，现在机器人能做出响应了。

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
          image: cloudbeer/wx-chatbot:2.0
          env:
            - name: OPENAI_API_KEY
              value: [your-api-key]
            - name: BOT_NAME
              value: [your-bot-name]
            - name: ROOM_BOT_NAME
              value: [your-room-bot-name]
          command:
            - node
            - index.js
```

修改上面代码中的环境变量 `[your-api-key]`, `[your-bot-name]`，`[your-room-bot-name]`：

- OPENAI_API_KEY: 在 openai 网站申请的 API_KEY，当前申请地址是： <https://platform.openai.com/account/api-keys>

- BOT_NAME: 私人机器人的名字，当发送以这个名字开头的文字的时候，会调用 chatgpt，如 BOT_NAME 为 `hisiri` 的时候，发送：`hisiri 你好` 会得到 ChatGPT 的响应。

- ROOM_BOT_NAME: 群机器人名字，这个机器人的会话是基于群的，群内的所有人都可以训练同一个机器人。

- 你可以在群里分别和两个机器人对话。

部署完成之后，使用 logs 命令查看二维码，相关的命令如下：

```shell
kubectl logs wx-chatbot-xxxxxxx -f
```

- -f 可以持续打印日志，查看控制台信息。
- 使用微信扫码之后，当前扫码的微信会成为 ChatGPT 机器人。你可以和他私聊或者拉到群里。
- 聊天的时候需要分别以 2 个机器人的名字开头才能做出响应。

## Docker 启动

Docker 启动不再赘述，使用如下命令即可：

```bash
docker run --rm -it --name wx-chatgpt-bot \
  -e OPENAI_API_KEY=abc -e BOT_NAME=小米 -e ROOM_BOT_NAME=大米 \
  cloudbeer/wx-chatbot:2.0 node index.js
```

- 记得修改三个环境变量：`-e OPENAI_API_KEY=abc -e BOT_NAME=@siri`。
- 注意：此命令在 MAC 启动有bug。用 linux 系统无虞。

## 问题和改进点

- 免费账号 ChatGPT 测会经常报 429 Too Many Requests 的错误。
- 微信可能会被封，建议使用新注册的微信小号作为机器人。（暂且不清楚微信侧触发机制）
- 重启应用会重新加载微信的会话，导致重复调用 ChatGPT API，并由可能导致微信被封，重启应用的时候多等一会儿，让会话过期，或者修改两个bot 的名字后重启。
