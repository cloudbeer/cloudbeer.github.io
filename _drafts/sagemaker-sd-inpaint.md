---
layout: post
title:  "在 SageMaker 上使用 Stable Diffusion 的局部重绘给衣服换模特"
date:   2023-05-13 09:10:49 +0800
author: 啤酒云
categories: aiml, aws
---


编写 code 目录下的 inference.py 文件

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

添加额外依赖在 requirements.txt 中：

```txt
diffusers[torch]==0.16.1
```


下载模型：stable-diffusion-inpainting

> 建议在相关的 region 里开通一个 Cloud9 进行此步操作，在云上操作，下载和上传速度会更快。

现在将上面的两个文件放到模型仓库的 code 目录下。

打包

上传到 S3

编写部署代码

