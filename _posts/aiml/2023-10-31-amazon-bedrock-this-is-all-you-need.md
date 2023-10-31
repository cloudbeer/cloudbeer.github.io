---
layout: post
title:  "入门 Amazon Bedrock 只看这一篇就够了"
date:   2023-10-31 21:03:33 +0800
author: 啤酒云
categories: aiml, aws
---

Amazon Bedrock 简要说就是是 AWS 的一项完全托管的服务，通过 API 调用各种优质大模型。本文将总结其基本用法，并提供完整的示例。

## 使用前提

### 开通

到 Bedrock 后台，进入 Model access，修改一下，将你需要的模型都勾选上。然后保存，使得 Access status 为 Access granted。

### 客户端类库

**首先，升级相关 AWS 的类库到最新。**

本文使用 Python，需要 boto3 >= 1.28.57

### 设置权限

在 AWS 调用服务，总是要预先设置 IAM。

Bedrock 的 IAM 请参考这个链接，请灵活设置。

<https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonbedrock.html>

下面是一个示例：

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "InvokeFM",
            "Effect": "Allow",
            "Action": [  
               "bedrock:GetFoundationModel",
               "bedrock:InvokeModel", 
               "bedrock:InvokeModelWithResponseStream"
            ],
            "Resource": "*"
        }
    ]   
}         
```

### 基本调用

调用方式也很简单，一眼就看明白了。

如果你设置好了 IAM 权限（如：本地的 AKSK 已经设置好），下面的代码可以无需修改直接运行。

```python
import boto3
import json

# 声明客户端
bedrock = boto3.client(service_name="bedrock-runtime")

# 此处使用的是 Amazon 的 titan-embedding 模型
modelId = 'amazon.titan-embed-text-v1'
# 使用 json 作为输入和输出的文本格式
contentType = 'application/json'
accept = 'application/json'

# 输入参数（不同的模型要求不一样）
body = json.dumps({
    "inputText": "Hello world!"
})

# 发起调用
response = bedrock.invoke_model(body=body, modelId=modelId, accept=accept, contentType=contentType,)

# 把结果弄出来
response_body = json.loads(response.get('body').read())
embedding = response_body.get('embedding')

# 搞定
print(embedding)
```

如果模型支持 stream 输出，则是如下的代码，修改调用方法为 `invoke_model_with_response_stream`，并解析输出 stream：

```python
import boto3
import json

# 声明客户端
bedrock = boto3.client(service_name="bedrock-runtime")

# 使用的是 Claude v2 模型
modelId = 'anthropic.claude-v2'
# 使用 json 作为输入的文本格式
contentType = 'application/json'
# stream 输出，有可能一次输出的 json 字符串会被截断
accept = '*/*'

# 输入参数（不同的模型要求不一样）
body = json.dumps({
  "prompt": "Human:你是谁?请介绍自己，不少于100字\n\nAssistant:",
  "max_tokens_to_sample": 2048,
  "temperature": 0.5,
  "top_p": 0.9,
})

# 发起调用
response = bedrock.invoke_model_with_response_stream(
    body=body,
    modelId=modelId,
    accept=accept,
    contentType=contentType,
)
stream = response.get("body")

# 输出 stream
if stream:
    for event in stream:
        chunk = event.get("chunk")
        if chunk:
            chunk_obj = json.loads(chunk.get("bytes").decode())
            text = chunk_obj["completion"]
            print(text)
```

然后，通过修改 modelId 和 body 的参数就可以完成各种目标了。你需要去查看 Bedrock 调用的各个模型文档，找到对应的参数就好了。

到这里，其实已经讲完 bedrock 的调用了。怎么样？很简单吧！

希望你现在已经去找文档并动手去写代码了！

下面是当前 Bedrock 支持的模型，等你需要参考的时候，可以回头来看下面的内容。

> Bedrock 会飞快迭代，说不定等你再回来时，下面的内容就过时了。

## Bedrock 支持的模型及参数

首先你可以 list 一下，看看支持的模型和 modelId.

```shell
aws bedrock list-foundation-models --region=<region>
```

具体的模型参数可以在控制台看到，AWS 的 Web 控制台贴心的给每个模型写了基本的输入参数。

从 Bedrock 后台，进入 Base Models 点开每个 model 的详情，就能看到调用参数了，如：<https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/models>

以下的总结大部分为搬运，有些参数官方文档也没发出来，仅供参考。一切以官方文档为准。

> 如果官方文档的来不及更新，并且你在 2023 年 11 月初看到这篇文章，应该以我的代码为准，因为我都测试了。

### Claude

- Max tokens: 100k
- 多语言

调用代码请参考上文中的 invoke_model_with_response_stream

#### Claude v2

modelId 为 `anthropic.claude-v2`

#### Claude Instance v1.2

#### modelId 为 `anthropic.claude-instant-v1`

#### Claude v1.3

modelId 为 `anthropic.claude-v1`

### Cohere

#### Command

- Model size: 52B
- Max tokens: 4096
- 英语

```python
modelId = 'cohere.command-text-v14'
accept = '*/*'
contentType = 'application/json'

def ask(q, max_tokens=2048,temperature=0.8):
  body = json.dumps({
    "prompt": q,
    "max_tokens": max_tokens,
    "temperature": temperature
  })
  response = bedrock.invoke_model(body=body, modelId=modelId, accept=accept, contentType=contentType,)
  # print(response)
  
  response_body = json.loads(response.get('body').read())
  # print(response_body)
  
  return response_body.get('generations')[0]['text']

# 测试调用
print(ask("""Translate this sentence to Chinese: Are you going to Scarborough Fair: Parsley, sage, rosemary and thyme."""))
print("-"*20)
# 试试中文，貌似能听懂，但不太会说
print(ask("请翻译为英文：君不见黄河之水天上来"))

```

### Jurassic

- Max tokens: 8191
- English, Spanish, French, German, Portuguese, Italian, Dutch

Jurassic 的入参和出参规范不太一样（入参是驼峰，claude2 是 snake），模型参数也和说明和文档稍有出入，看起来还在迭代。

经过一些修改，下面是完整可运行的代码。

#### Jurassic-2 Ultra

```python
modelId = 'ai21.j2-ultra-v1'
accept = '*/*'
contentType = 'application/json'

def ask(q, modelId=modelId, maxTokens=300):
  body = json.dumps({
    "prompt": q,
    "maxTokens": maxTokens,
    "temperature": 0.8,
    "topP": 1,
    "stopSequences": [],
    "countPenalty":{
      "scale":0
    },
    "presencePenalty":{
      "scale":0
    },
    "frequencyPenalty":{
      "scale":0
    }
  })


  response = bedrock.invoke_model(body=body, modelId=modelId, accept=accept, contentType=contentType,)
  response_body = json.loads(response.get('body').read())
  return response_body.get('completions')[0].get("data").get('text')


print(ask("Who are you?"))

# 试试中文
print(ask("你是谁?"))
```

#### Jurassic-2 Mid

modelId 为 `ai21.j2-mid-v1`

```python
print(ask("Who are you?", modelId="ai21.j2-mid-v1"))

print(ask("请翻译为英文：白日依山尽", modelId="ai21.j2-mid-v1"))
```

### Titan

Titan 有三个模型，目前只有 Embeddings 生成可以测试。

#### Titan Embeddings Generation 1 (G1)

- Max tokens: 8k
- 输出向量维度: 1536
- 多语言支持

下面代码的尝试使用 Titan 进行向量化，并进行相似度比较。

```python
modelId = 'amazon.titan-embed-text-v1'
accept = 'application/json'
contentType = 'application/json'

def predict(text):
  body = json.dumps({
      "inputText": text
  })
  response = bedrock.invoke_model(body=body, modelId=modelId, accept=accept, contentType=contentType,)
  
  response_body = json.loads(response.get('body').read())
  return response_body.get('embedding')
```

定义相似度的函数

```python
from numpy import dot, array
from numpy.linalg import norm

def cosine_sim(v1, v2):
    return dot(v1, v2)/(norm(v1)*norm(v2))

def l2_sim(v1, v2):
    return norm(array(tuple(v1))-array(tuple(v2)))

```

测试

```python
word = "对不起"
compares = ["对不起", "抱歉", "對不起", "對唔住","真遗憾", "吃了吗", "I'm sorry", "I apologize", "the weather",  "ごめんなさい", "미안해", "Désolé"]

wordvec = predict(word)
for compare in compares:
  print(f"{word} 与 {compare} 的 Cosine 相似度：",  cosine_sim(predict(compare), wordvec))

print("-"*20)

for compare in compares:
  print(f"{word} 与 {compare} 的 L2 距离：",  l2_sim(predict(compare), wordvec))
```

从向量结果比较看来，<ruby>
大<rt>不</rt>
概<rt>太</rt>
<ruby>符合预期。

## Stability AI

### Stable Diffusion XL

当前支持的版本为 v0.8。

输入参数可以参考 [DreamStudio](https://dreamstudio.ai/)

代码参考：

```python
import base64
import io
import json

import boto3
from PIL import Image

# 修改此处的 region_name 可以更换 region
bedrock = boto3.client(service_name='bedrock-runtime',region_name='us-west-2')

# 可选 style，此处为 DreamStudio 的列表参考，并未调用
style_presets = [
    "enhance",
    "anime",
    "photographic",
    "digital-art",
    "comic-book",
    "fantasy-art",
    "analog-film",
    "neon-punk",
    "isometric",
    "low-poly",
    "origami",
    "line-art",
    "craft-clay",
    "cinematic",
    "3d-model",
    "pixel-art",
]

def predict(prompt, negative_prompts=["poorly rendered"], style_preset="enhance", size=(512,512)):
  request = json.dumps({
    "text_prompts": (
        [{"text": prompt, "weight": 1.0}]
        + [{"text": negprompt, "weight": -1.0} for negprompt in negative_prompts]
    ),
    "cfg_scale": 10,
    # "seed": -1,
    "steps": 30,
    "style_preset": style_preset,
    "width": size[0],
    "height": size[1],
  })
  modelId = "stability.stable-diffusion-xl"
  response = bedrock.invoke_model(body=request, modelId=modelId)
  response_body = json.loads(response.get("body").read())

  base_64_img_str = response_body["artifacts"][0].get("base64")
  image_1 = Image.open(io.BytesIO(base64.decodebytes(bytes(base_64_img_str, "utf-8"))))
  return image_1

```

调用：

```python
predict(
    "3D product render, futuristic sofa, finely detailed, purism, ue 5, a computer rendering, minimalism, octane render, 4k", 
    negative_prompts=[
        "poorly rendered",
        "worst quality",
        "monochrome",
        "cropped",
        "duplicate",
        "out of frame", 
        "ugly", 
        "deformed",
        "complex background"
    ],
    style_preset="3d-model", 
    size=(512,512)
)
```

当前的 SDXL 模型有下面的优点和坑：

- 支持 style_preset 参数，这个参数在官方文档里没写，官方 sample notebook 有。
- 可以完美输出 512 像素的图片，1024 的反倒无法输出。
- 必须有一个边是 512 或者 768，另一个变长是 8 的倍数(这个 SD 都一样)。

## 总结和继续

亚麻的 Bedrock 集合了生成式 AI 各家（老二，老三们）之所长，并坚持不断更新迭代，终将进化为地球的最强者。

你需要做的就是了解各个模型的特点，找到合适的提示词模板（提示词工程 PE），加上预处理（用各种类库），然后组合成自动化流程。

最终，漂亮的应用呼之欲出。

祝你成功！！！

---

模型参数： <https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters.html>

[Amazon Bedrock Workshop](https://github.com/aws-samples/amazon-bedrock-workshop)
