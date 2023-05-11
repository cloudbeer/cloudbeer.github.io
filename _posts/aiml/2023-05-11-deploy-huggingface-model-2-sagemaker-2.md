---
layout: post
title:  "在 SageMaker 上部署 Huggingface 模型 (二)"
date:   2023-05-11 16:13:33 +0800
author: 啤酒云
categories: aiml, aws
---

在 Huggingface 上，有些模型并没有 Deploy - Sagemaker 这个功能，或者我们需要做一些特殊的任务，怎么办？本文介绍了如何让 SageMaker 调用自定义的推理代码。

## 背景

在 [上一篇文章](deploy-huggingface-model-2-sagemaker-1.html) 里，我们直接使用了 Huggingface 官方提供的部署和推理代码中，并使用了他提供了默认的 HF_TASK，如：

```python
hub =  {
 'HF_MODEL_ID':'bert-base-chinese',
 'HF_TASK':'fill-mask'
}
```

现在我们计划做一个推理 embeddings 文本转向量任务，使用自己的推理代码。

## 代码准备

本文选取了 distiluse-base-multilingual-cased-v2  这个模型，这个模型可以推理多语言的 embeddings，他在 Huggingface 上没有部署到 SageMaker 的选项。

先下载这个代码仓库：

```shell
git lfs install
git clone https://huggingface.co/sentence-transformers/distiluse-base-multilingual-cased-v2
```

进入这个代码仓库，在编辑器里增加两个文件，一个 推理文件 `code/inference.py`，一个依赖库文件 `code/requirements.txt`。

```shell
cd distiluse-base-multilingual-cased-v2
mkdir code
touch code/inference.py
touch code/requirements.txt 
```

我们需要在 `inference.py` 里添加 model_fn 和 predict_fn 这俩函数，这个文件如下：

```python
from sentence_transformers import SentenceTransformer

def model_fn(model_dir):
  return SentenceTransformer(model_dir)

def predict_fn(data, model):
  return model.encode(data)
```

在 `requirements.txt` 里加入 sentence_transformers 的引用：

```text
sentence_transformers==2.2.2
```

## 打包上传

现在把这个库打包上传到 S3：

```shell
tar zcvf distiluse-base-multilingual-cased-v2.tar.gz *

aws s3 cp distiluse-base-multilingual-cased-v2.tar.gz \
  s3://cloudbeer-llm-models/sentence-transformers/distiluse-base-multilingual-cased-v2.tar.gz
```

- 创建你自己的存储桶，并保证你有足够的权限。
- 模型都很大，上传前记得测试一下你的脚本。

## 部署模型

与上一篇差不多，先给 `HuggingfaceExecuteRole` 这个 IAM Role 加入策略 `AmazonS3ReadOnlyAccess`。

完整的部署代码如下：

```python
import boto3  
from sagemaker.huggingface.model import HuggingFaceModel
import numpy as np
from scipy.spatial.distance import cosine

# 此处定义了一个数组相似度计算的函数
def similarity(v1, v2):
    a = np.array(v1)
    b = np.array(v2)
    return 1-cosine(a,b)

s3_model = "s3://cloudbeer-llm-models/sentence-transformers/distiluse-base-multilingual-cased-v2.tar.gz"

iam_client = boto3.client('iam')
role = iam_client.get_role(RoleName='HuggingfaceExecuteRole')['Role']['Arn']

huggingface_model = HuggingFaceModel(
  model_data=s3_model,      
  role=role,                    
  transformers_version="4.26",  
  pytorch_version="1.13",
  py_version='py39',           
)

predictor = huggingface_model.deploy(
  initial_instance_count=2,
  instance_type='ml.m5.xlarge'
)
```

现在运行一下推理试试：

```python
res = predictor.predict("在 SageMaker 上部署 Huggingface 模型")
print(len(res), res[:10])
```

结果如下：

```text
512 [-0.08045165985822678, 0.028644787147641182, 0.01914004050195217, -0.02148452214896679, 0.017731796950101852, -0.05328822508454323, 0.004828637931495905, 0.015703866258263588, -0.017463965341448784, -0.01227850466966629]
```

测试相似度：

```python
res1 = predictor.predict("抱歉")
res2 = predictor.predict("Sorry")
sim1 = similarity(res1, res2)
print(sim1)
```

结果为：`0.9197762458059101`

```python
sim2 = similarity(res1, predictor.predict("对不起"))
sim3 = similarity(res1, predictor.predict("Je mi líto"))
sim4 = similarity(res1, predictor.predict("ごめんなさい"))
sim5 = similarity(res1, predictor.predict("吃了吗"))
print(sim2, sim3, sim4, sim5)
```

结果为：`0.9926941692158543 0.9510660558985051 0.9787457828105314 0.27865827356290396`

比较符合预期！

## 总结

上面的过程是在本地的 VSCode Notebook 中完成。

模型部署模型时间为 3 分 15 秒，我部署了 2 个实例，在实际的推理中，可以感觉到推理效率显著提高。

---
相关

[在 SageMaker 上部署 Huggingface 模型 (一)](deploy-huggingface-model-2-sagemaker-1.html)

参考

<https://github.com/aws/sagemaker-huggingface-inference-toolkit>

[Huggingface 默认支持的库版本对照](https://huggingface.co/docs/sagemaker/reference#inference-dlc-overview)
