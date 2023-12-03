---
layout: post
title:  "Amazon Bedrock 内置知识库使用入门"
date:   2023-12-03 09:10:49 +0800
author: 啤酒云
categories: aiml
---

本文是 Amazon Bedrock 自带的知识库的一个入门体验，用起来真的很方便，节省了前期的一堆劳动。

## 快速入门

在年底的 re:Invent 2023 上，AWS 发布了一堆产品，其中知识库 (Knowledge base) 便提供了非常快捷的 RAG 实现路径。

他内置了如下的能力（截止当前文章）：

- 数据源集成，当前支持 S3 存储桶里的文件

- 文档提取，当前支持如下格式
  - Plain text (.txt)
  - Markdown (.md)
  - HyperText Markup Language (.html)
  - Microsoft Word document (.doc/.docx)
  - Comma-separated values (.csv)
  - Microsoft Excel spreadsheet (.xls/.xlsx)
  - Portable Document Format (.pdf)

- 文档分片

- 向量转化（当前使用的是 Titan Embeddings G1 - Text ）

- 向量数据库集成，当前支持如下三种：
  - OpenSearch Serverless，支持在开通知识库的流程中创建。
  - Pinecone
  - Redis

- S3 数据源维护，当文档删除或者修改的时候可以同步向量数据库。

- 在控制台提供了一个知识召回的演示

- 管理 API 和 运行时 API

## 实际使用集成

通过控制台(入口：<https://console.aws.amazon.com/bedrock/home?#/knowledge-bases>)，很容易建立知识库体系。

当建立完成知识库之后，用户只需要将文档上传到对应的 S3 存储桶。

然后将知识库集成到自己的应用中，此时只需调用 运行时 API 即可。

运行时的 API 包含如下两个：

### Retrieve

知识召回，此方法将直接查询向量数据库，将文章片段及其 S3 的文件信息返回。

### RetrieveAndGenerate

知识召回之后，将结果传入 生成式 AI 进行知识总结（需要结合使用 Bedrock 的生成式大语言模型，如 Claude）.

返回一段总结好的文字，并分段给出引用地址(citations)。

### 代码示例

实际使用中，我可能需要将本地知识召回，再加上其他 Agent 得到的知识之后，再进行总结。

Retrieve 调用很简单，代码片段如下：

```js
import { BedrockAgentRuntimeClient, RetrieveCommand } from "@aws-sdk/client-bedrock-agent-runtime";
const bedrockAgentRuntimeClient = new BedrockAgentRuntimeClient({ region });

async function retrive(text) {
  return await bedrockAgentRuntimeClient.send(new RetrieveCommand({
    knowledgeBaseId,
    retrievalQuery: {
      text,
    },
    retrievalConfiguration: {
      vectorSearchConfiguration: {
        numberOfResults: 5,
      },
    }
  }));
}
```

稍加解释：

- knowledgeBaseId 是你 Amazon Bedrock 知识库的 ID，可以从控制台寻得。
- text 是你提的问题。
- numberOfResults 是需要返回的结果条数。

> 当前建议在实际集成中使用 JS 的 SDK。官方提供的 SDK，只有 JS 可以支持 streaming 流式输出。
> 使用流式输出，可以大幅减少在生成过程中的假死等待时间。

看一下我控制台打印的结果(`console.log(result.retrievalResults);`)：

```shell
2023-12-03T04:42:40.384Z cf5e41dc-22de-402c-b4bc-86eacff68691 INFO 如何进行S3事件通知？
2023-12-03T04:42:40.385Z cf5e41dc-22de-402c-b4bc-86eacff68691 INFO [
  {
    content: {
      text: 'For more infor...'
    },
    location: { s3Location: [Object], type: 'S3' },
    score: 0.65092564
  },
  {
    content: {
      text: 'Data protection in Amazon S3  PDFRSS ...'
    },
    location: { s3Location: [Object], type: 'S3' },
    score: 0.66120756
  },
  {
    content: {
      text: '.  • S3 Standard, S3 Intelligent-Tiering, S3 Stand...'
    },
    location: { s3Location: [Object], type: 'S3' },
    score: 0.669181
  },
  {
    content: {
      text: "You specify the Amazon Resource Na..."
    },
    location: { s3Location: [Object], type: 'S3' },
    score: 0.7088487
  },
  {
    content: {
      text: "Amazon S3 Event Notifi..."
    },
    location: { s3Location: [Object], type: 'S3' },
    score: 0.7597214
  }
]
```

比较符合预期，接下来只需要重整这个结果，结合其他的方法获取的知识，将问题和参考知识丢给 LLM ，结合提示词工程(PE)即可完成更好的问答式输出了。
