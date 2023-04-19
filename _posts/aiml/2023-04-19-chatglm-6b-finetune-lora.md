---
layout: post
title:  "ChatGLM-6B 的 Lora 微调"
date:   2023-04-19 10:10:49 +0800
author: 啤酒云
categories: aiml
cover: /assets/cover/finetuning_lora.jpg
---

本文是开源项目的使用记录，按照文档操作， finetune 的过程其实很简单。

## 项目信息

相关脚本地址：<https://github.com/mymusise/ChatGLM-Tuning>

这个项目提供了如下的脚本：

转化 alpaca 数据集为 jsonl，tokenization 脚本，训练等。

## 数据准备

使用了 stanford_alpaca 的数据集格式，格式如下:

```json
[
  {
    "instruction": "帮我总结一下论文？",
    "input": "这里是论文的内容",
    "output": "总结的内容" 
   }
]
```

如果只是问答类型的数据，input 可以留空。

## 数据集转换

上述数据集 文件名是: `answers.json`

```shell
python cover_alpaca2jsonl.py \
    --data_path data/answers.json \
    --save_path data/answers.jsonl

python tokenize_dataset_rows.py \
    --jsonl_path data/answers.jsonl \
    --save_path data/answer \
    --skip_overlength True
```

## 开始训练

```shell
python finetune.py \
      --dataset_path data/answer     \
      --lora_rank 8     \
      --per_device_train_batch_size 6     \
      --gradient_accumulation_steps 1     \
      --max_steps 400     \
      --save_steps 100     \
      --save_total_limit 2     \
      --learning_rate 1e-4     \
      --fp16     \
      --remove_unused_columns false     \
      --logging_steps 50     \
      --output_dir output

```

训练比较耗时，所以这一步是最 "难" 的：如果参数不佳，需要调整参数重来一遍。

## 使用刚刚训练 Lora 模型

下面的代码可以将 Lora 模型叠加到基础模型上去。

```python
model = AutoModel.from_pretrained("ChatGLM-path", trust_remote_code=True)
model = PeftModel.from_pretrained(model, "<Your_Path>/ChatGLM-Tuning/output", fan_in_fan_out=False)
```
