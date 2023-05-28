---
layout: post
title:  "使用 SageMaker 部署 ChatGLM-6B 自定义 API"
date:   2023-05-28 10:13:33 +0800
author: 啤酒云
categories: aiml, sagemaker
---

ChatGLM-6B 默认是一个聊天模型，也可以用来提取 embeddings。但当前的企业内部智能搜索方案大多都使用了 text2vec + LLM 多个模型，text2vec 用于向量生产，LLM 用于对查询结果进行总结。本文试试图使用同一个 LLM 模型完成这两项工作，编写自定义 API，并将模型部署到 SageMaker 上。

## 关键代码

废话不多说，ChatGLM-6B 抽取 embeddings 的关键代码如下：

```python
def to_embeddings(model,text):
    input_ids = tokenizer.encode(text, return_tensors="pt").to("cuda")
    model_output = model(input_ids, output_hidden_states=True)
    data = (model_output.hidden_states[-1].transpose(0, 1))[0]
    data = F.normalize(torch.mean(data, dim=0), p=2, dim=0)
    return data.tolist()
```

上述代码不做过多解释，因为我也不太懂。

生成的结果是一个长度为 4096 的浮点数组。

## SageMaker predict 接口设计

也直接看代码吧：

```python

def predict_fn(data, pipe):
    text = data.pop("text", data)
    type = data.pop("type", 0)

    if type == 0:
        response, history = pipe.chat(tokenizer, text, history=[])
        return response
    else:
        return to_embeddings(pipe, text)
```

预测接口增加了参数 `type`，可以通过使用此参数来执行不同的任务，在本例中

- type 为 0 执行聊天任务
- else 生成 embeddings

## 部署

关键代码已经完成，现在只需要将上述逻辑放到 项目的 code 目录下的 `inference.py` 文件中，ChatGLM-6B 模型我们直接让 SageMaker 去 Huggingface 上下载。

code 目录我已经打包上传到 S3。

```python
import boto3  
from sagemaker.huggingface.model import HuggingFaceModel

s3_model = "s3://cloudbeer-llm-models/llm/chatglm-6b-model.tar.gz"

iam_client = boto3.client('iam')
role = iam_client.get_role(RoleName='HuggingfaceExecuteRole')['Role']['Arn']

huggingface_model = HuggingFaceModel(
  model_data=s3_model,
  role=role,
  transformers_version='4.26',
  pytorch_version='1.13',
  py_version='py39',
)

predictor = huggingface_model.deploy(
  initial_instance_count=1,
  instance_type='ml.g4dn.2xlarge',
  endpoint_name='chatglm-6b-model',
)
```

## 测试

#### SageMaker 模型加载

```python
from sagemaker.huggingface.model import HuggingFacePredictor

predictor = HuggingFacePredictor(
  endpoint_name='chatglm-6b-model'
)
```

#### 对话

```python
predictor.predict({
    "text": "你好，你是谁"
})
```

`'我是一个名为 ChatGLM-6B 的人工智能助手，是基于清华大学 KEG 实验室和智谱 AI 公司于 2023 年共同训练的语言模型开发的。我的任务是针对用户的问题和要求提供适当的答复和支持。'
`

#### 生产 embedddings

```python
res = predictor.predict({
    "text": "你好世界",
    "type": 1
})

print(len(res), res[:2])
```

`4096 [-0.0092010498046875, 0.0296630859375]`

## 避坑

下面的坑截止到本文写作日期存在：

- ChatGLM-6B 的最小机型应该是 2xlarge，如 ml.g4dn.2xlarge，我使用 xlarge 一直出错，日志显示 模型无法加载到 100%。
- transfomers 的最小版本需求为 4.27.1，当前 SageMaker 的 Huggingface 最高版本是 4.26.1，在 requirements.txt 中加入相应的版本依赖即可。
- 如果使用了 CUDA，按照报错信息，需要增加 cpm-kernels 的依赖。

我的 code/requirements.txt 如下：

```text
cpm-kernels==1.0.11
transformers==4.27.1
```

---
参考：

[本文完整源码](https://github.com/cloudbeer/chatglm-infer-sagemaker)

<https://huggingface.co/THUDM/chatglm-6b>

[FastChat 中各 LLM 获取 embeddings 的方法](https://github.com/lm-sys/FastChat/blob/51ed4fab89f61988e8395a3268595f1effb8528f/fastchat/serve/model_worker.py#L246)
