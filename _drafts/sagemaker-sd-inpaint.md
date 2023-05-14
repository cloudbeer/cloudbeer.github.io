---
layout: post
title:  "在 AWS 上使用 Stable Diffusion Inpainting 给商品更换模特"
date:   2023-05-13 09:10:49 +0800
author: 啤酒云
categories: aiml, aws
---

给商品图片安上模特可以使用 stable-diffusion-inpainting 这个模型来轻松实现。本文探讨使用 AWS 服务来进行流水线方式生产，并最大程度节约使用成本。

## 模型准备

建议使用云上实例来操作此步，如 SageMaker 的笔记本实例，或者在相关的 region 里开通 Cloud9。在云上操作，下载和上传速度会更快。

下载 Huggingface 模型：stable-diffusion-inpainting

```shell
git lfs install
git clone https://huggingface.co/runwayml/stable-diffusion-inpainting
```

> 在云上的小机型使用 git clone 大模型的时候会出现 OOM 错误，上述模型大小为 4G，使用小于 2c4g 的实例 Clone 会 OOM。
>
> 使用如下命令：  
>
> ```shell
> git lfs install --skip-smudge
> git clone https://huggingface.co/runwayml/stable-diffusion-inpainting
> cd stable-diffusion-inpainting
> git lfs pull
> ```

在 SageMaker 中自定义推理，需要编写一个 code 目录，并放上 2 个文件：

 code 目录下的 inference.py 文件：

```python
import base64
import torch
import requests
from PIL import Image
from io import BytesIO
from diffusers import StableDiffusionInpaintPipeline


def model_fn(model_dir):
    pipe = StableDiffusionInpaintPipeline.from_pretrained(
        model_dir,
        torch_dtype=torch.float16,
        safety_checker = None
    )
    pipe.to("cuda")
    return pipe

def download_image(url, w, h):
    response = requests.get(url)
    res_img = Image.open(BytesIO(response.content)).convert("RGB")
    res_img = res_img.resize((w, h))
    return res_img

def gen(data, pipe):
    prompt = data.pop("prompt", data)
    image_url = data.pop("image_url", data)
    mask_url = data.pop("mask_url", None)
    width = data.pop("width", 512)
    height = data.pop("height", 512)
    
    image_ori = download_image(image_url, width, height)
    if mask_url: 
        mask_image = download_image(mask_url, width, height)
    else:
        mask_image = image_ori


    num_inference_steps = data.pop("num_inference_steps", 30)
    guidance_scale = data.pop("guidance_scale", 7.5)
    num_images_per_prompt = data.pop("num_images_per_prompt", 4)
    prompt_suffix = ",pretty face,fine skin,masterpiece,cinematic light, ultra high res, film grain, perfect anatomy, best shadow, delicate,(photorealistic:1.4),(extremely intricate:1.2)"
    nprompt = 'bad_legs,bad_fingers,(semi_realistic,cgi,3d,render,sketch,cartoon,drawing,anime:1.4),text,cropped,out_of_frame,worst_quality,low_quality,jpeg_artifacts,ugly,duplicate,morbid,mutilated,extra_fingers,mutated_hands,poorly_drawn_hands,poorly_drawn_face,mutation,deformed,blurry,dehydrated,bad_anatomy,bad_proportions,extra_limbs,cloned_face,disfigured,gross_proportions,malformed_limbs,missing_arms,missing_legs,extra_arms,extra_legs,fused_fingers,too_many_fingers,long_neck,signature'

    generated_images = pipe(
        prompt=prompt + prompt_suffix,
        negative_prompt=nprompt,
        image=image_ori, 
        mask_image=mask_image,  
        eta=0.7,
        width=width,
        height=height,
        num_inference_steps=num_inference_steps,
        guidance_scale=guidance_scale,
        num_images_per_prompt=num_images_per_prompt,
    )["images"]
    return generated_images

def predict_fn(data, pipe):
    generated_images = gen(data, pipe)
    encoded_images = []
    for image in generated_images:
        buffered = BytesIO()
        image.save(buffered, format="JPEG")
        encoded_images.append(base64.b64encode(buffered.getvalue()).decode())

    return {"generated_images": encoded_images}

```

- 定义了部分 prompt  和 完整的 negative_prompt，在使用过程中只需要输入你需要的模特提示词即可
- 定义了图片的默认大小，此尺寸也可以在外部指定，建议不要太大，并且尺寸最好是 8 的倍数

code 目录下 requirements.txt：

```txt
diffusers[torch]==0.16.1
```

现在你的项目目录应该类似这样：

```shell
~/environment/stable-diffusion-inpainting (main) $ tree
.
├── code
│   ├── inference.py
│   └── requirements.txt
├── config.json
├── feature_extractor
│   └── preprocessor_config.json
├── model_index.json
├── README.md
├── safety_checker
│   ├── config.json
│   └── pytorch_model.bin
├── scheduler
│   └── scheduler_config.json
├── sd-v1-5-inpainting.ckpt
├── text_encoder
│   ├── config.json
│   └── pytorch_model.bin
├── tokenizer
│   ├── merges.txt
│   ├── special_tokens_map.json
│   ├── tokenizer_config.json
│   └── vocab.json
├── unet
│   ├── config.json
│   └── diffusion_pytorch_model.bin
└── vae
    ├── config.json
    └── diffusion_pytorch_model.bin
```

打包上传 S3:

```shell
tar zcvf stable-diffusion-inpainting.tar.gz *

aws s3 cp stable-diffusion-inpainting.tar.gz \
  s3://cloudbeer-llm-models/diffusers/stable-diffusion-inpainting.tar.gz
```

> 当前模型整体有 8 G，打包上传这一步对于简中用户会比较痛苦，特别是代码写错的情况下。
>
> 我很痛苦！！

## 部署模型

```python
import boto3  
from sagemaker.huggingface.model import HuggingFaceModel

s3_model = "s3://cloudbeer-llm-models/diffusers/stable-diffusion-inpainting.tar.gz"

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
  initial_instance_count=1,
  instance_type='ml.g4dn.xlarge',
  endpoint_name='sd-inpainting-try-on'
)
```

- 使用了 GPU 机型 ml.g4dn.xlarge
- 给 Endpoint 定义了个名称：sd-inpainting-try-on

## 测试推理

下面的测试在本地 Notebook 中进行的，代码：

```python

import matplotlib.pyplot as plt

def display_images(images=None, columns=4, width=100, height=100):
    plt.figure(figsize=(width, height))
    for i, image in enumerate(images):
        plt.subplot(int(len(images) / columns + 1), columns, i + 1)
        plt.axis('off')
        plt.imshow(image)
        
res = gen(data = {
    "prompt": "a female,flowers field",
    "image_url": "https://th.bing.com/th/id/R.316c68fd4da6e3329115aa92fe07315f?rik=WRx0NfsTBN5Wsw&pid=ImgRaw&r=0",
    "width": 560,
    "height": 840
}, pipe=pipe)


display_images(res)
```

## 流水线
