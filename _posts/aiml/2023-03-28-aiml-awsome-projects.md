---
layout: post
title:  "AI/ML Bookmarks"
date:   2023-03-28 10:10:49 +0800
author: 啤酒云
categories: aiml
cover: /assets/cover/aiml.png
---

本文就是 Bookmarks，是我体验过的(🦋)，正在体验的或准备体验的一些现成的库和链接。本文近期可能随时更新。

## 🐝 中文语言大模型

### ChatGLM 🦋

清华大学的大语言模型。

ChatGLM-6B 是一个开源的、支持中英双语的对话语言模型。

<https://github.com/THUDM/ChatGLM-6B>

<https://huggingface.co/THUDM>

### ChatYuan 🦋

Large Language Model for Dialogue in Chinese and English，是一个支持中英双语的功能型对话语言大模型。

<https://github.com/clue-ai/ChatYuan>

<https://www.clueai.cn/>

<https://huggingface.co/ClueAI>

## 🐝  虚拟主播

### SadTalker 🦋

Learning Realistic 3D Motion Coefficients for Stylized Audio-Driven Single Image Talking Face Animation

输入图片文件，声音文件，生成符合口型的播音视频。

<https://github.com/Winfredy/SadTalker>

> 当前特性：
>
> - 3D 效果
> - 可以眨眼睛
> - 镜头，眼神转移
>
> - 输入图片会被截取脸部放大 (2023-03-28)
> - 生成的视频偏小  (2023-03-28)
> - 程序运行环境较为苛刻，需要 N 卡， cudnn 等 (2023-03-28)

### Wav2Lip

Accurately Lip-syncing Videos In The Wild.

<https://github.com/Rudrabha/Wav2Lip>

<https://www.youtube.com/watch?v=Ic0TBhfuOrA>

## 🐝 声音

### audioldm 🦋

Generate speech, sound effects, music and beyond.

This repo currently support:

- Text-to-Audio Generation: Generate audio given text input.
- Audio-to-Audio Generation: Given an audio, generate another audio that contain the same type of sound.
- Text-guided Audio-to-Audio Style Transfer: Transfer the sound of an audio into another one using the text description.

<https://github.com/haoheliu/AudioLDM>

<https://audioldm.github.io/>

> - 通过文本生产声音
> - 也可以生成音乐
> - 效果一般 (2023-03-29)

## 🐝  试穿(Try-On)

### Dressing in Order (DiOr)

Dressing in Order: Recurrent Person Image Generation for Pose Transfer, Virtual Try-on and Outfit Editing.

可以多件衣服。

<https://github.com/cuiaiyu/dressing-in-order>

### HR-VITON

<https://github.com/sangyun884/HR-VITON>

<https://github.com/shadow2496/VITON-HD>

### PIDM

Person Image Synthesis via Denoising Diffusion Model Open

可以控制姿态。提供 ipynb 文件。

<https://github.com/ankanbhunia/PIDM>

## 🐝  开源 UI

### Stable Diffusion web UI 🦋

Diffussion 生图 and More，无需多言。

<https://github.com/AUTOMATIC1111/stable-diffusion-webui>

### InvokeAI 🦋

Diffussion 生图，界面精美。

<https://github.com/invoke-ai/InvokeAI>

<https://invoke-ai.github.io/InvokeAI/>

## 🐝  商业/在线应用

### OpenAI

ChatGPT

DALL.E

...

### midjourney 🦋

Diffussion 生图，在 Discord 内使用。

<https://www.midjourney.com/>

### Leonardo.ai

Diffussion 生图，在 Discord 内使用。

<https://leonardo.ai/>

### Playground AI 🦋

每天免费 1000 张，限定模型为 SD 1.5, SD 2.1。Prompt 参考。

<https://playgroundai.com/>

### PromptHero

Prompt 参考，Pro 版本提供 SD 模型生产。

<https://prompthero.com/>

### runaway ml

在线视频工具 <https://app.runwayml.com/>

开源：<https://github.com/runwayml>

### D-ID 🦋

数字人合成。

<https://www.d-id.com/>

### 百度文心

文心大模型

<https://wenxin.baidu.com/>

文心一言

<https://yiyan.baidu.com/>

文心一格 🦋

<https://yige.baidu.com/>

### 网易

天音 - 音乐创作平台

<https://tianyin.163.com/>

## 🐝  其他

### FILM

Frame Interpolation for Large Motion，视频插帧。

<https://github.com/google-research/frame-interpolation>

### RIFE

Real-Time Intermediate Flow Estimation for Video Frame Interpolation.

ECCV 2022 - 视频插帧中的实时中间流估计，旷世科技。

<https://github.com/megvii-research/ECCV2022-RIFE>

<https://zhuanlan.zhihu.com/p/568553080>

### HumanNeRF

Free-viewpoint Rendering of Moving People from Monocular Video (CVPR 2022)

<https://github.com/chungyiweng/humannerf>

<https://github.com/zhaofuq/HumanNeRF>

<https://github.com/Chen-Lehan/HumanNeRF>

### SysMocap

A cross-platform real-time video-driven motion capture and 3D virtual character rendering system for VTuber/Live/AR/VR.

跨平台的实时视频驱动动作捕捉及3D虚拟形象生成系统 for VTuber/Live/AR/VR.

<https://github.com/xianfei/SysMocap>
