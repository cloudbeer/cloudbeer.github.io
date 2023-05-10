---
layout: post
title:  "在 SageMaker 上部署 Huggingface 模型"
date:   2023-05-10 10:13:33 +0800
author: 啤酒云
categories: aiml, aws
---

在 Huggingface 上浏览模型的时候，会看到一个 Deploy 按钮，很多模型点开会看到 Amazon SageMaker 选项，然后会看到一段代码。今天便试了一下这个，下面是测试过程：在本机运行运行代码，把 Huggingface 的 模型部署到 SageMaker 上并运行推理。

## 创建 IAM 角色

往 SageMaker 部署模型需要一个角色，先创建一个角色，如果你之前运行过 SageMaker，大抵应该有了这个角色。

- Trusted entity type: AWS service
- Use cases for other AWS services: SageMaker
- 勾选上 SageMaker - Execution

你会看到他已经选择了 AmazonSageMakerFullAccess 策略，点击下一步。

把这个角色命名为 HuggingfaceExecuteRole  或者其他。

## 代码分段解读

> 你可以在 VSCode 里创建一个 xxx.ipynb 的文件，分段执行下面的代码。VSCode 提供了 python 和 notebook 相关插件。
>
> 另外，你需要在本机配置正确的 AKSK 和 AWS Region。
>
> boto3 和 sagemaker 这俩依赖库要在本机安装一下。

### 定义模型

```python
import boto3  
from sagemaker.huggingface import HuggingFaceModel

hub =  {
 'HF_MODEL_ID':'bert-base-chinese',
 'HF_TASK':'fill-mask'
}
```

- 这里定义了模型的名字和需要做的任务名称，SageMaker 会动态拉取 Huggingface 的模型。

### 部署模型

```python
iam_client = boto3.client('iam')
role = iam_client.get_role(RoleName='HuggingfaceExecuteRole')

huggingface_model = HuggingFaceModel(
 transformers_version='4.17.0',
 pytorch_version='1.10.2',
 py_version='py38',
 env=hub,
 role=role['Role']['Arn'], 
)


predictor = huggingface_model.deploy(
 initial_instance_count=1, 
 instance_type='ml.m5.xlarge' 
)
```

- 这一步我们定义了模型运行的环境，角色和运行的机型，数量。
- role 这里需要注意一下，他的入参是 Role 的 Arn。
- 这一步完成之后，可以到 SageMaker 后台看到计算资源/Endpoint 已经成功部署，位置在 Inference - Endpoints。

### 运行推理

```python
predictor.predict({
 'inputs': "哈哈，我正在吃[MASK]。"
})
```

结果为：

```shell
[{'score': 0.26574137806892395,
  'token': 1450,
  'token_str': '呢',
  'sequence': '哈 哈 ， 我 正 在 吃 呢 。'},
 {'score': 0.23924605548381805,
  'token': 7649,
  'token_str': '饭',
  'sequence': '哈 哈 ， 我 正 在 吃 饭 。'},
 {'score': 0.07031755149364471,
  'token': 1557,
  'token_str': '啊',
  'sequence': '哈 哈 ， 我 正 在 吃 啊 。'},
 {'score': 0.02992616966366768,
  'token': 1521,
  'token_str': '哦',
  'sequence': '哈 哈 ， 我 正 在 吃 哦 。'},
 {'score': 0.029010694473981857,
  'token': 7613,
  'token_str': '飯',
  'sequence': '哈 哈 ， 我 正 在 吃 飯 。'}]
```

### 清理资源

```python
predictor.delete_endpoint()
```

## 总结

整个过程还是非常的方便，Endpoint 的创建的速度非常快（本示例用了 2 分半钟），省去了安装运行环境的痛苦，爽的一匹啊！
