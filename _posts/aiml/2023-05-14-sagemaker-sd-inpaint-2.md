---
layout: post
title:  "在 AWS 上使用 Stable Diffusion 给商品更换模特(二)"
date:   2023-05-16 17:10:49 +0800
author: 啤酒云
categories: aiml, aws
---

现在，我准备上传图片和蒙版到 S3，触发部署代码，并完成任务，推理完成之后，释放 Endpoint。

## 模型加载流程改善

在进行试验的过程中，发现每次对模型进行打包和上传 S3 会浪费很多时间。

此处改进一下：**在加载模型的时候，直接从 Huggingface 的 `runwayml/stable-diffusion-inpainting` 加载模型**。

```python
def model_fn(model_dir):
    print(model_dir)
    pipe = StableDiffusionInpaintPipeline.from_pretrained(
        "runwayml/stable-diffusion-inpainting",
        torch_dtype=torch.float16,
        safety_checker = None
    )
    pipe.to("cuda")
    return pipe
```

使用上面的方法可以从 Huggingface 加载模型，并使用自己的推理代码。

具体做法是：

- 创建一个文件夹，如 src
- 在 src 下创建 code 文件夹
- 在 code 文件夹下加入 inference.py 和 requirements.txt 文件
- 修改 inference.py 的 model_fn 方法，如上
- 打包上传 code 下面的两个文件

现在无需下载模型到本地打包了，真实部署的时候，SageMaker 会去下载模型。

当前上传的程序包只有 1k 左右，如下：

```shell
~/environment/stable-diffusion-inpainting (main) $ tree
.
├── code
│   ├── inference.py
│   └── requirements.txt
```

## inference.py 代码解读

商品图片下载方式修改：

```python
def split_s3_path(s3_path):
    path_parts=s3_path.replace("s3://","").split("/")
    bucket=path_parts.pop(0)
    key="/".join(path_parts)
    return bucket, key

def download_image(url, w, h):
    o = split_s3_path(url)
    response = s3.get_object(Bucket=o[0], Key=o[1])['Body'].read()
    res_img = Image.open(BytesIO(response)).convert("RGB")
    res_img = res_img.resize((w, h))
    return res_img
```

- 商品和图片的入参会修改为 S3 地址，如：s3://cloudbeer-llm-models/works/2023-05-16/shirt01.png
- 在后期可以做相关触发器，直接读取 S3 地址

整个生产流程也进行了改进：

```python
def gen(data, pipe):
    prompt = data.pop("prompt", data)
    image_url = data.pop("image_url", data)
    mask_url = data.pop("mask_url", None)
    width = data.pop("width", 384)
    height = data.pop("height", 512)
    
    image_ori = download_image(image_url, width, height)
    if mask_url: 
        mask_image = download_image(mask_url, width, height)
    else:
        mask_url = image_url
        mask_image = image_ori

    num_inference_steps = data.pop("num_inference_steps", 30)
    guidance_scale = data.pop("guidance_scale", 7.5)
    num_images_per_prompt = data.pop("num_images_per_prompt", 4)
    prompt_suffix = ",fine skin,masterpiece,cinematic light, ultra high res, film grain, perfect anatomy, best shadow, delicate,(photorealistic:1.4),(extremely intricate:1.2)"
    nprompt = 'bad_legs,bad_fingers,(semi_realistic,cgi,3d,render,sketch,cartoon,drawing,anime:1.4),text,cropped,out_of_frame,worst_quality,low_quality,jpeg_artifacts,ugly,duplicate,morbid,mutilated,extra_fingers,mutated_hands,poorly_drawn_hands,poorly_drawn_face,mutation,deformed,blurry,dehydrated,bad_anatomy,bad_proportions,extra_limbs,cloned_face,disfigured,gross_proportions,malformed_limbs,missing_arms,missing_legs,extra_arms,extra_legs,fused_fingers,too_many_fingers,long_neck,signature'


    now = datetime.now() 
    date_str = now.strftime("%Y-%m-%d")

    html = "<html><head><title>图片生成" + date_str + "</title><link href='../main.css' rel='stylesheet'></head><body>"
    html += "<h1>图片生成" + date_str + "</h1>"
    html += "<h4>提示词: " + prompt + prompt_suffix + "</h4>"
    
    cf_in_url = s3_to_cf_url(image_url)
    cf_msk_url = s3_to_cf_url(mask_url)
    html += "<div><a href='" + cf_in_url + "' target='_blank'><img src='" + cf_in_url + "' /></a>"
    html += "<a href='" + cf_msk_url + "' target='_blank'><img src='" + cf_msk_url + "' /></a></div>"


    for i in range(num_images_per_prompt):
        generated_images = pipe(
            prompt=prompt + prompt_suffix,
            negative_prompt=nprompt,
            image=image_ori, 
            mask_image=mask_image,
            width=width,
            height=height,
            num_inference_steps=num_inference_steps,
            guidance_scale=guidance_scale,
            num_images_per_prompt=1,
        )["images"]

        for image in generated_images:
            file_name = str(uuid.uuid4()) + ".jpg"
            key = key_prefix + date_str + '/' + file_name
            in_mem_file = BytesIO()
            image.save(in_mem_file, format="JPEG")
            in_mem_file.seek(0)
            s3.upload_fileobj(
                in_mem_file, 
                saving_bucket, 
                key,
                ExtraArgs={
                    'ContentType': 'image/jpeg'
                }
            )
            html += "<a href='" + file_name + "' target='_blank'><img src='" + file_name + "' /></a>"
    html += "</body></html>"

    index_file_name = 'index-' + str(uuid.uuid4()) + '.html'
    s3.put_object(
        Bucket='cloudbeer-llm-models',
        Key=key_prefix + date_str + '/' + index_file_name,
        Body=html.encode('utf-8'),
        ContentType='text/html'
    )

    return cloudfront_url + key_prefix + date_str + '/' + index_file_name

```

代码中需要注意的是：

- 推理 pipeline 中，改为每次生产 1 张图片，num_images_per_prompt 改为循环次数，这样可以有效避免内存溢出
- 每生产一张图片，就上传到 S3
- 将此次任务的图片生产出一个 html 预览页
- S3 会通过 Cloudfront 映射出来，方便预览

代码完成之后，可以直接打包，并上传 S3:

```shell
cd ./src

rm stable-diffusion-inpainting-tryon.tar.gz
tar zcvf stable-diffusion-inpainting-tryon.tar.gz *

aws s3 cp stable-diffusion-inpainting-tryon.tar.gz \
  s3://cloudbeer-llm-models/diffusers/stable-diffusion-inpainting-tryon.tar.gz
```

## 模型部署

直接通过 SageMaker 部署：

```python
import boto3  
from sagemaker.huggingface.model import HuggingFaceModel

s3_model = "s3://cloudbeer-llm-models/diffusers/stable-diffusion-inpainting-tryon.tar.gz"

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
  endpoint_name='sd-inpainting-tryon',
)
```

- 由于要从 SageMaker 上传 S3，HuggingfaceExecuteRole 这个角色要加入相应 S3 写权限

大约 5 分钟后，部署完成。

## 推理任务

推理代码如下：

```python
from sagemaker.huggingface.model import HuggingFacePredictor

predictor = HuggingFacePredictor(
  endpoint_name='sd-inpainting-tryon'
)

res = predictor.predict({
    "prompt": "a strong man,back view,white shorts,football field",
    "image_url": "s3://cloudbeer-llm-models/works/2023-05-16/shirt01.png",
    "mask_url": "s3://cloudbeer-llm-models/works/2023-05-16/shirt01_mask.png",
    "num_images_per_prompt": 10,
    "width": 512,
    "height": 512
})

print(res)
```

当前手工执行的，后期可以加入 CloudWatch 或者 S3 时间触发器进行调用。

会打印一个 url，内容大概如下：

![sd-inpainting-tryon](/assets/posts/aiml/sd-inpaiting-2.jpg)

推理任务完成后，删除计算资源：

```python
predictor.delete_model()
predictor.delete_endpoint()
```

---

参考：

[本文完整源码](https://github.com/cloudbeer/sd-inpainting-tryon)

[在 AWS 上使用 Stable Diffusion 给商品更换模特(一)](sagemaker-sd-inpaint-1.html)
