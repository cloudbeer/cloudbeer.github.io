---
layout: post
title:  "在 AWS 部署 AI 文生图为 Restful API 的最简单方式"
date:   2023-04-03 16:10:49 +0800
author: 啤酒云
categories: aiml
cover: /assets/cover/cyborg_tiger.jpg
---

当你的大模型练就之后，“很容易” 将模型部署到 SageMaker，但我们一般需要通过 Restful API 集成到应用中。本文以 Stable Diffussion 为例，介绍了一种简便的集成方法，并提供了代码。

## 流程

![SageMaker restful](/assets/posts/aiml/sagemaker-s3-restful.png)

1. 用户请求 API Gateway, prompt 包含在 Url 中。

2. API Gateway 将请求传向 Lambda。

3. Lambda 请求 SageMaker 的 Endpoint。

4. SageMaker 响应请求，返回 图片和 prompt 信息。

5. Lambda 将图片上传到 S3。

6. 上传完成后，Lambda 对 S3 Object 进行 Url 签名。

7. 返回结果

8. 返回结果

## 在 SageMaker 中部署模型

进入 AWS 控制台的 SageMaker Studio，从左侧菜单选择 SageMaker JumpStart - Models, notebooks, solutions。

这里有非常多的现成的模型，选择一个，如 Stable Diffusion 2.1 base，进入之后，选择 "Deploy"。

稍等 "片刻"，等待 Endpoint 生产完成。

完成后，可以在左侧菜单的 Deployments - Endpoints 里看到 Endpoint 的 Name，这个 Name 就是下面代码中的 endpoint_name。

## 编写 Lambda

直接看代码好了，解析在代码末尾，本段 Lambda 使用 Python 编写：

```python
import json
import boto3
import time
import base64

endpoint_name = 'jumpstart-name'
bucket_name = 'cloudbeer-aigc-works'

s3_client = boto3.client('s3')
sagemaker_client = boto3.client('runtime.sagemaker')

def query_endpoint(text):
    payload = {"prompt":text, "width":512, "height":512}
    query_response = sagemaker_client.invoke_endpoint(
              EndpointName=endpoint_name, 
              ContentType='application/json', 
              Body=json.dumps(payload).encode('utf-8'), 
              Accept = 'application/json;jpeg')
    generated_images, prompt = parse_response_multiple_images(query_response)
    return generated_images[0]


def parse_response_multiple_images(query_response):
    response_dict = json.loads(query_response['Body'].read())
    return response_dict['generated_images'], response_dict['prompt']

def save_s3(image):
    object_name = str(time.time()) + '.jpg'
    resPut = s3_client.put_object(
        ContentType="image/jpeg",
        Body=base64.b64decode(image),
        Bucket=bucket_name,
        Key=object_name,
    )
    try:
        response = s3_client.generate_presigned_url('get_object',
                                                    Params={'Bucket': bucket_name,
                                                            'Key': object_name},
                                                    ExpiresIn=300)
    except ClientError as e:
        logging.error(e)
        return None
    return response
    
def lambda_handler(event, context):
    prompt = event["queryStringParameters"]['prompt']
    image = query_endpoint(prompt)
    return {
        'statusCode': 200,
        'body':  json.dumps({
            "url": save_s3(image),
            "prompt": prompt
        })
    }

```

上面的代码非常的简单，做了如下的事情：

- 定义了 2 个变量，分别是 模型的 Endpoint 和 S3 桶的名称。
- query_endpoint 和 parse_response_multiple_images 这两个函数直接使用了 SageMaker 的 Notebook 中的 Python 函数。这俩函数用来调用推理，并解析推理结果。
- save_s3 这个函数将图片上传到 S3 的存储桶，并生成一个 Presigned Url 作为输出结果。query_endpoint 的图片结果是图片的 byte 数组 base64 encode 之后的字符串，在上传 S3 的时候需要将字符串 decode 成 byte 数组。
- 最后把结果组装一下就可以了， 参数：prompt 获取自 Querystring: `event["queryStringParameters"]['prompt']`。
- 这个代码如果需要生产环境使用，请注意如下问题：
  - 图片大小为 512*512，此尺寸可以直接在代码中修改，图片的尺寸会直接关系到生成速度和资源占用。
  - Lambda 的执行超时时间需要调整。
  - S3 文件的 Key 没有创建子目录，都在根下。
  - S3 的文件名使用了时间戳，并发大的时候，有可能会有重复名称。
  - S3 的签名过期时间是 5 分钟。
  - 记得加上权限认证，把这个服务提供给你真正的客户，毕竟 GPU 有点贵。

## IAM 权限

在 Lambda 的 Configuration 的 Tab 里，可以看到一个 Execution role，点击具体的 role 进入 IAM 中，在这个 role 中需要分别加入 SageMaker 和 S3 的权限。

如，S3 的 Inline Policy 可以如下配置：

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AccessAiGC",
            "Action": "s3:*",
            "Effect": "Allow",
            "Resource": [
                "arn:aws:s3:::cloudbeer-aigc-works",
                "arn:aws:s3:::cloudbeer-aigc-works/*"
            ]
        }
    ]
}
```

你亦可以配置相应的 SageMaker 权限。

## API Gateway

新建一个 API Gateway，把他指向 Lambda 就好了。

现在访问如下的 API Gateway 的 Url 就可以看到结果了：

<https://xxxxxxxxxxx.execute-api.region.amazonaws.com/route?prompt=cyborg_tiger>  假的，不要点。

结果为：

```json
{
  "url": "https://xxxxxxx.s3.amazonaws.com/xxxxxxxx.jpg?AWSAccessKeyId=....",
  "prompt": "cyborg_tiger"
}
```

上面的 url 就是 AIGC 的输出结果，你应该看到了一只赛博老虎。😄

---

参考：

<https://aws.amazon.com/cn/blogs/machine-learning/generate-images-from-text-with-the-stable-diffusion-model-on-amazon-sagemaker-jumpstart/>
