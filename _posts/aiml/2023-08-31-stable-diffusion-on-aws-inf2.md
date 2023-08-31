---
layout: post
title:  "在 AWS Inferentia 2 上使用 Stable Diffusion"
date:   2023-08-31 13:10:49 +0800
author: 啤酒云
categories: aws, aiml
---

AWS Inferentia2 实例专为深度学习（DL）推理而构建。它们在 Amazon EC2 中以最低的成本为生成式人工智能（AI）模型（包括大型语言模型（LLM）和视觉转换器）提供高性能计算。您可以使用 Inf2 实例来运行推理应用程序，以实现文本摘要、代码生成、视频和图像生成、语音识别、个性化、欺诈检测等等。

## 启动实例

启动 Inf2 实例需要选择专门的系统 AMI，在 AMI 市场搜索 Neuron，选择 AMI： `Deep Learning AMI Neuron PyTorch 1.13 (Ubuntu 20.04)` - 截止 2023-08-31

由于需要转化模型，官方的 sample 实例建议机型为 `inf2.8xlarge`。

进入系统后，查看 `/home/ubuntu/README` 文件，首先启动 PyTorch 的 Inf2 环境：

```shell
source /opt/aws_neuron_venv_pytorch/bin/activate
```

## Stable diffusion 1.5

### 模型转换

使用如下的代码将模型转化为 Inf2 的支持的模型。

此代码来自于官方示例。

```python
import os
os.environ["NEURON_FUSE_SOFTMAX"] = "1"

import torch
import torch.nn as nn
import torch_neuronx
import numpy as np

from matplotlib import pyplot as plt
from matplotlib import image as mpimg
import time
import copy
from IPython.display import clear_output

from diffusers import StableDiffusionPipeline
from diffusers.models.unet_2d_condition import UNet2DConditionOutput

from diffusers.models.cross_attention import CrossAttention

clear_output(wait=False)

###### 定义参数 #########
DTYPE = torch.float32
COMPILER_WORKDIR_ROOT = '/home/ubuntu/models/deli-inf2'
model_id = "XpucT/Deliberate"
#########################

######## 类和方法的定义 #################
def get_attention_scores(self, query, key, attn_mask):
    dtype = query.dtype

    if self.upcast_attention:
        query = query.float()
        key = key.float()

    if(query.size() == key.size()):
        attention_scores = cust_badbmm(
            key,
            query.transpose(-1, -2),
            self.scale
        )

        if self.upcast_softmax:
            attention_scores = attention_scores.float()

        attention_probs = torch.nn.functional.softmax(attention_scores, dim=1).permute(0,2,1)
        attention_probs = attention_probs.to(dtype)

    else:
        attention_scores = cust_badbmm(
            query,
            key.transpose(-1, -2),
            self.scale
        )

        if self.upcast_softmax:
            attention_scores = attention_scores.float()

        attention_probs = torch.nn.functional.softmax(attention_scores, dim=-1)
        attention_probs = attention_probs.to(dtype)

    return attention_probs

def cust_badbmm(a, b, scale):
    bmm = torch.bmm(a, b)
    scaled = bmm * scale
    return scaled

class UNetWrap(nn.Module):
    def __init__(self, unet):
        super().__init__()
        self.unet = unet

    def forward(self, sample, timestep, encoder_hidden_states, cross_attention_kwargs=None):
        out_tuple = self.unet(sample, timestep, encoder_hidden_states, return_dict=False)
        return out_tuple

class NeuronUNet(nn.Module):
    def __init__(self, unetwrap):
        super().__init__()
        self.unetwrap = unetwrap
        self.config = unetwrap.unet.config
        self.in_channels = unetwrap.unet.in_channels
        self.device = unetwrap.unet.device

    def forward(self, sample, timestep, encoder_hidden_states, cross_attention_kwargs=None):
        sample = self.unetwrap(sample, timestep.float().expand((sample.shape[0],)), encoder_hidden_states)[0]
        return UNet2DConditionOutput(sample=sample)

class NeuronTextEncoder(nn.Module):
    def __init__(self, text_encoder):
        super().__init__()
        self.neuron_text_encoder = text_encoder
        self.config = text_encoder.config
        self.dtype = torch.float32
        self.device = text_encoder.device

    def forward(self, emb, attention_mask = None):
        return [self.neuron_text_encoder(emb)['last_hidden_state']]

class NeuronSafetyModelWrap(nn.Module):
    def __init__(self, safety_model):
        super().__init__()
        self.safety_model = safety_model

    def forward(self, clip_inputs):
        return list(self.safety_model(clip_inputs).values())

# --- Compile CLIP text encoder and save ---
print("Load model....")
# Only keep the model being compiled in RAM to minimze memory pressure
pipe = StableDiffusionPipeline.from_pretrained(model_id, torch_dtype=DTYPE)

print("Compile CLIP text encoder and save")
text_encoder = copy.deepcopy(pipe.text_encoder)

# Apply the wrapper to deal with custom return type
text_encoder = NeuronTextEncoder(text_encoder)

# Compile text encoder
# This is used for indexing a lookup table in torch.nn.Embedding,
# so using random numbers may give errors (out of range).
emb = torch.tensor([[49406, 18376,   525,  7496, 49407,     0,     0,     0,     0,     0,
        0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
        0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
        0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
        0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
        0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
        0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
        0,     0,     0,     0,     0,     0,     0]])

with torch.no_grad():
    text_encoder_neuron = torch_neuronx.trace(
            text_encoder.neuron_text_encoder,
            emb,
            compiler_workdir=os.path.join(COMPILER_WORKDIR_ROOT, 'text_encoder'),
            compiler_args=["--enable-fast-loading-neuron-binaries"]
            )

# Save the compiled text encoder
text_encoder_filename = os.path.join(COMPILER_WORKDIR_ROOT, 'text_encoder/model.pt')
torch_neuronx.async_load(text_encoder_neuron)
torch.jit.save(text_encoder_neuron, text_encoder_filename)

# delete unused objects
del text_encoder
del text_encoder_neuron
del emb

# --- Compile VAE decoder and save ---
print("Compile VAE decoder and save")
# Only keep the model being compiled in RAM to minimze memory pressure
decoder = copy.deepcopy(pipe.vae.decoder)

# # Compile vae decoder
decoder_in = torch.randn([1, 4, 64, 64])
with torch.no_grad():
    decoder_neuron = torch_neuronx.trace(
        decoder,
        decoder_in,
        compiler_workdir=os.path.join(COMPILER_WORKDIR_ROOT, 'vae_decoder'),
        compiler_args=["--enable-fast-loading-neuron-binaries"]
    )


# Save the compiled vae decoder #######################
decoder_filename = os.path.join(COMPILER_WORKDIR_ROOT, 'vae_decoder/model.pt')
torch_neuronx.async_load(decoder_neuron)
torch.jit.save(decoder_neuron, decoder_filename)

# delete unused objects
del decoder
del decoder_in
del decoder_neuron

# --- Compile UNet and save ---
print("Compile UNet and save")
# Replace original cross-attention module with custom cross-attention module for better performance
CrossAttention.get_attention_scores = get_attention_scores
# Apply double wrapper to deal with custom return type
pipe.unet = NeuronUNet(UNetWrap(pipe.unet))
# Only keep the model being compiled in RAM to minimze memory pressure
unet = copy.deepcopy(pipe.unet.unetwrap)


# Compile unet - FP32
sample_1b = torch.randn([1, 4, 64, 64])
timestep_1b = torch.tensor(999).float().expand((1,))
encoder_hidden_states_1b = torch.randn([1, 77, 768])
example_inputs = sample_1b, timestep_1b, encoder_hidden_states_1b

with torch.no_grad():
    unet_neuron = torch_neuronx.trace(
        unet,
        example_inputs,
        compiler_workdir=os.path.join(COMPILER_WORKDIR_ROOT, 'unet'),
        compiler_args=["--model-type=unet-inference", "--enable-fast-loading-neuron-binaries"]
    )


# save compiled unet
unet_filename = os.path.join(COMPILER_WORKDIR_ROOT, 'unet/model.pt')
torch_neuronx.async_load(unet_neuron)
torch_neuronx.lazy_load(unet_neuron)
torch.jit.save(unet_neuron, unet_filename)

# delete unused objects
del unet
del unet_neuron
del sample_1b
del timestep_1b
del encoder_hidden_states_1b


# --- Compile VAE post_quant_conv and save ---
print("Compile VAE post_quant_conv and save")
# Only keep the model being compiled in RAM to minimze memory pressure
post_quant_conv = copy.deepcopy(pipe.vae.post_quant_conv)

# # # Compile vae post_quant_conv
post_quant_conv_in = torch.randn([1, 4, 64, 64])
with torch.no_grad():
    post_quant_conv_neuron = torch_neuronx.trace(
        post_quant_conv,
        post_quant_conv_in,
        compiler_workdir=os.path.join(COMPILER_WORKDIR_ROOT, 'vae_post_quant_conv'),
        compiler_args=["--enable-fast-loading-neuron-binaries"]
    )


# # Save the compiled vae post_quant_conv
post_quant_conv_filename = os.path.join(COMPILER_WORKDIR_ROOT, 'vae_post_quant_conv/model.pt')
torch_neuronx.async_load(post_quant_conv_neuron)
torch.jit.save(post_quant_conv_neuron, post_quant_conv_filename)

# delete unused objects
del post_quant_conv



# # --- Compile safety checker and save ---
print("Compile safety checker and save")
# Only keep the model being compiled in RAM to minimze memory pressure
safety_model = copy.deepcopy(pipe.safety_checker.vision_model)


clip_input = torch.randn([1, 3, 224, 224])
with torch.no_grad():
    safety_model_neuron = torch_neuronx.trace(
        safety_model,
        clip_input,
        compiler_workdir=os.path.join(COMPILER_WORKDIR_ROOT, 'safety_model_neuron'),
        compiler_args=["--enable-fast-loading-neuron-binaries"]
    )

# # Save the compiled vae post_quant_conv
safety_model_neuron_filename = os.path.join(COMPILER_WORKDIR_ROOT, 'safety_model_neuron/model.pt')
torch_neuronx.async_load(safety_model_neuron)
torch.jit.save(safety_model_neuron, safety_model_neuron_filename)

# delete unused objects
del safety_model_neuron

del pipe

```

- 需要 diffusers 的版本为 0.14.0
- 直接使用了 hf 上的 diffusers 模型：`XpucT/Deliberate`，使用最新的 diffusers 代码自己转换的 C 站模型会推理失败。具体原因不详。
- 上述代码转换后的模型只支持 512 * 512 的图片，这个代码是相关的shape：`torch.randn([1, 4, 64, 64])`

保存文件： python trans_1.5.py 之后，直接运行 `python trans_1.5.py`。

此过程将会生产 neuron 的模型，如下：

```shell
drwxrwxr-x 3 ubuntu ubuntu 4096 Aug 30 02:23 safety_model_neuron
drwxrwxr-x 3 ubuntu ubuntu 4096 Aug 30 02:14 text_encoder
drwxrwxr-x 3 ubuntu ubuntu 4096 Aug 30 02:22 unet
drwxrwxr-x 3 ubuntu ubuntu 4096 Aug 30 02:18 vae_decoder
drwxrwxr-x 3 ubuntu ubuntu 4096 Aug 30 02:22 vae_post_quant_conv
```

### 推理

直接上代码：

```python
# 类库，类和方法的定义，参数定义和上面一致，略。。。
print("加载原始模型")
pipe = StableDiffusionPipeline.from_pretrained(
    model_id,
    torch_dtype=torch.float32,
    safety_checker=None,
)
pipe.scheduler = UniPCMultistepScheduler.from_config(pipe.scheduler.config)

text_encoder_filename = os.path.join(COMPILER_WORKDIR_ROOT, "text_encoder/model.pt")
unet_filename = os.path.join(COMPILER_WORKDIR_ROOT, "unet/model.pt")
decoder_filename = os.path.join(COMPILER_WORKDIR_ROOT, "vae_decoder/model.pt")
post_quant_conv_filename = os.path.join(
    COMPILER_WORKDIR_ROOT, "vae_post_quant_conv/model.pt"
)
safety_model_neuron_filename = os.path.join(
    COMPILER_WORKDIR_ROOT, "safety_model_neuron/model.pt"
)


# Load the compiled UNet onto two neuron cores.

print("加载 Neuro 转换模型")

print("加载 unet")
pipe.unet = NeuronUNet(UNetWrap(pipe.unet))
device_ids = [0, 1]
pipe.unet.unetwrap = torch_neuronx.DataParallel(
    torch.jit.load(unet_filename), device_ids, set_dynamic_batching=False
)


print("加载 text_encoder")
pipe.text_encoder = NeuronTextEncoder(pipe.text_encoder)
pipe.text_encoder.neuron_text_encoder = torch.jit.load(text_encoder_filename)

print("加载 vae decoder")
pipe.vae.decoder = torch.jit.load(decoder_filename)

print("加载 vae post_quant_conv")
pipe.vae.post_quant_conv = torch.jit.load(post_quant_conv_filename)

print("加载 safety_checker, skipping...")
# pipe.safety_checker.vision_model = NeuronSafetyModelWrap(torch.jit.load(safety_model_neuron_filename))

# Run pipeline
prompt = [
    "A 24 y.o pretty girl, masterpiece, 8k, highres",
    "a photo of an astronaut riding a horse on mars",
    "sonic on the moon",
    "elvis playing guitar while eating a hotdog",
    "saved by the bell",
    "engineers eating lunch at the opera",
    "panda eating bamboo on a plane",
    "A digital illustration of a steampunk flying machine in the sky with cogs and mechanisms, 4k, detailed, trending in artstation, fantasy vivid colors",
    "kids playing soccer at the FIFA World Cup",
]

total_time = 0
i = 0
for x in prompt:
    start_time = time.time()
    image = pipe(
        x, negative_prompt="nsfw, bad finger, lowres", num_inference_steps=20
    ).images[0]
    total_time = total_time + (time.time() - start_time)
    image.save(f"outputs/{i}.webp", "WEBP")
    i = i + 1
print("Average time: ", np.round((total_time / len(prompt)), 2), "seconds")

```

推理顺利完成，速度很快。

## SDXL

8月28日刚刚更新的新的 neuron 2.13 版本可以支持 SDXL 了。当前 AMI 未放出，所以需要先手工安装依赖包。

具体的依赖包仓库在：<https://pip.repos.neuron.amazonaws.com/>

比如安装最新版本的 neuronx-distributed 命令：

```shell
pip install neuronx-distributed transformers-neuronx -i https://pip.repos.neuron.amazonaws.com/
```

### 模型转换

废话不多说，上代码：

```python
# filename: trans_xl.py 
import os

import numpy as np
import torch
import torch.nn as nn
import torch_neuronx
from diffusers import DiffusionPipeline, DPMSolverMultistepScheduler
from diffusers.models.unet_2d_condition import UNet2DConditionOutput
from diffusers.models.attention_processor import Attention

from matplotlib import pyplot as plt
from matplotlib import image as mpimg
import time
import copy
from IPython.display import clear_output

clear_output(wait=False)


COMPILER_WORKDIR_ROOT = "/home/ubuntu/models/sdxl"

# COMPILER_WORKDIR_ROOT = "/home/ubuntu/models/ds8"

# Model ID for SD XL version pipeline
model_id = "stabilityai/stable-diffusion-xl-base-1.0"


def get_attention_scores_neuron(self, query, key, attn_mask):
    if query.size() == key.size():
        attention_scores = custom_badbmm(key, query.transpose(-1, -2), self.scale)
        attention_probs = attention_scores.softmax(dim=1).permute(0, 2, 1)

    else:
        attention_scores = custom_badbmm(query, key.transpose(-1, -2), self.scale)
        attention_probs = attention_scores.softmax(dim=-1)

    return attention_probs


def custom_badbmm(a, b, scale):
    bmm = torch.bmm(a, b)
    scaled = bmm * scale
    return scaled


class UNetWrap(nn.Module):
    def __init__(self, unet):
        super().__init__()
        self.unet = unet

    def forward(
        self, sample, timestep, encoder_hidden_states, text_embeds=None, time_ids=None
    ):
        out_tuple = self.unet(
            sample,
            timestep,
            encoder_hidden_states,
            added_cond_kwargs={"text_embeds": text_embeds, "time_ids": time_ids},
            return_dict=False,
        )
        return out_tuple


class NeuronUNet(nn.Module):
    def __init__(self, unetwrap):
        super().__init__()
        self.unetwrap = unetwrap
        self.config = unetwrap.unet.config
        self.in_channels = unetwrap.unet.in_channels
        self.add_embedding = unetwrap.unet.add_embedding
        self.device = unetwrap.unet.device

    def forward(
        self,
        sample,
        timestep,
        encoder_hidden_states,
        added_cond_kwargs=None,
        return_dict=False,
        cross_attention_kwargs=None,
    ):
        sample = self.unetwrap(
            sample,
            timestep.float().expand((sample.shape[0],)),
            encoder_hidden_states,
            added_cond_kwargs["text_embeds"],
            added_cond_kwargs["time_ids"],
        )[0]
        return UNet2DConditionOutput(sample=sample)


# --- Compile VAE decoder and save ---

# Only keep the model being compiled in RAM to minimze memory pressure

print("Load model....")
pipe = DiffusionPipeline.from_pretrained(model_id, torch_dtype=torch.float32)


print("Compile vae decoder....")

decoder = copy.deepcopy(pipe.vae.decoder)

# # Compile vae decoder
decoder_in = torch.randn([1, 4, 128, 128])
decoder_neuron = torch_neuronx.trace(
    decoder,
    decoder_in,
    compiler_workdir=os.path.join(COMPILER_WORKDIR_ROOT, "vae_decoder"),
)

# Save the compiled vae decoder
decoder_filename = os.path.join(COMPILER_WORKDIR_ROOT, "vae_decoder/model.pt")
torch.jit.save(decoder_neuron, decoder_filename)

# delete unused objects
del decoder


# --- Compile UNet and save ---

print("Compile UNet")

# pipe = DiffusionPipeline.from_pretrained(model_id, torch_dtype=torch.float32)

# Replace original cross-attention module with custom cross-attention module for better performance
Attention.get_attention_scores = get_attention_scores_neuron

# Apply double wrapper to deal with custom return type
pipe.unet = NeuronUNet(UNetWrap(pipe.unet))

# Only keep the model being compiled in RAM to minimze memory pressure
unet = copy.deepcopy(pipe.unet.unetwrap)
# del pipe

# Compile unet - FP32
sample_1b = torch.randn([1, 4, 128, 128])
timestep_1b = torch.tensor(999).float().expand((1,))
encoder_hidden_states_1b = torch.randn([1, 77, 2048])
added_cond_kwargs_1b = {
    "text_embeds": torch.randn([1, 1280]),
    "time_ids": torch.randn([1, 6]),
}
example_inputs = (
    sample_1b,
    timestep_1b,
    encoder_hidden_states_1b,
    added_cond_kwargs_1b["text_embeds"],
    added_cond_kwargs_1b["time_ids"],
)

unet_neuron = torch_neuronx.trace(
    unet,
    example_inputs,
    compiler_workdir=os.path.join(COMPILER_WORKDIR_ROOT, "unet"),
    compiler_args=["--model-type=unet-inference"],
)

# save compiled unet
unet_filename = os.path.join(COMPILER_WORKDIR_ROOT, "unet/model.pt")
torch.jit.save(unet_neuron, unet_filename)

# delete unused objects
del unet


print("Compile VAE post_quant_conv ")
# --- Compile VAE post_quant_conv and save ---

# Only keep the model being compiled in RAM to minimze memory pressure
# pipe = DiffusionPipeline.from_pretrained(model_id, torch_dtype=torch.float32)
post_quant_conv = copy.deepcopy(pipe.vae.post_quant_conv)
# del pipe

# Compile vae post_quant_conv
post_quant_conv_in = torch.randn([1, 4, 128, 128])
post_quant_conv_neuron = torch_neuronx.trace(
    post_quant_conv,
    post_quant_conv_in,
    compiler_workdir=os.path.join(COMPILER_WORKDIR_ROOT, "vae_post_quant_conv"),
)

# Save the compiled vae post_quant_conv
post_quant_conv_filename = os.path.join(
    COMPILER_WORKDIR_ROOT, "vae_post_quant_conv/model.pt"
)
torch.jit.save(post_quant_conv_neuron, post_quant_conv_filename)

# delete unused objects
del post_quant_conv

del pipe

```

但由于 SDXL 的模型要大很多，转换速度比较慢。

### 推理代码

```python
# 头部定义掠过

decoder_filename = os.path.join(COMPILER_WORKDIR_ROOT, "vae_decoder/model.pt")
unet_filename = os.path.join(COMPILER_WORKDIR_ROOT, "unet/model.pt")
post_quant_conv_filename = os.path.join(
    COMPILER_WORKDIR_ROOT, "vae_post_quant_conv/model.pt"
)

pipe = DiffusionPipeline.from_pretrained(model_id, torch_dtype=torch.float32)
pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config)


# Load the compiled UNet onto two neuron cores.
pipe.unet = NeuronUNet(UNetWrap(pipe.unet))
device_ids = [0, 1]
pipe.unet.unetwrap = torch_neuronx.DataParallel(
    torch.jit.load(unet_filename), device_ids, set_dynamic_batching=False
)

# Load other compiled models onto a single neuron core.
pipe.vae.decoder = torch.jit.load(decoder_filename)
pipe.vae.post_quant_conv = torch.jit.load(post_quant_conv_filename)

# Run pipeline
prompt = [
    "A 24 y.o pretty girl, masterpiece, 8k, highres",
    "a photo of an astronaut riding a horse on mars",
]

total_time = 0
i = 0

for x in prompt:
    start_time = time.time()
    pmt = f"""anime artwork {x} . anime style, key visual, vibrant, studio anime, highly detailed"""
    npmt = """photo, deformed, black and white, realism, disfigured, low contrast"""
    image = pipe(pmt, negative_prompt=npmt, num_inference_steps=20).images[0]
    total_time = total_time + (time.time() - start_time)
    image.save(f"outputs/xl-{i}.webp", "WEBP")
    i = i + 1
print("Average time: ", np.round((total_time / len(prompt)), 2), "seconds")

```

过程和 1.5 差不多。

但模型加载的时间较长。

## 总结

- 模型需哟转换，基本都能能成功完成转换，
- 1.5 的模型能成功完成推理的模型不多。
- SDXL 模型本身有较高质量。但加载时间较长。
- 当前按照官方示例，不支持动图片态尺寸。模型转化的时候已经固定好尺寸了。
- 推理速度很快：512 尺寸的 SD1.5 可达到 19it/s 左右，1024 的 SDXL 是 3.5it/s。

---
参考：

<https://github.com/aws-neuron/aws-neuron-samples>

<https://awsdocs-neuron.readthedocs-hosted.com/en/latest/release-notes/index.html>
