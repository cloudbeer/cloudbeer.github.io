---
layout: post
title:  "使用 QuickSight 自动展示 S3 的 Excel 文件"
date:   2023-04-02 11:10:49 +0800
author: 啤酒云
categories: aws
cover: /assets/cover/aiml.png
---

Amazon QuickSight 是 AWS 数据分析的前端展示平台，支持使用 Amazon S3 存储桶的 Excel 文件作为数据集。本文介绍了如何设置 S3 和 如何配置自动刷新。

## S3 文件准备

首先需要创建一个 manifest 的 JSON。

manifest 文件包含了 Amazon S3 对象位置和元数据的 JSON 文件。

以下是一个示例 Amazon S3 manifest 文件：

```json
{
  "entries": [
    {
      "url": "s3://my-bucket/salesdata/q1/report1.csv",
      "mandatory": true,
      "meta": {
        "sales_period": "report1"
      }
    },
    {
      "url": "s3://my-bucket/salesdata/q1/report2.csv",
      "mandatory": true,
      "meta": {
        "sales_period": "report2"
      }
    }
  ]
}
```

按照上述格式，此文件可以使用 S3 的 上传 Event 触发 Lambda 自动生成。

将上述 JSON 文件和 csv 文件 都上传到 S3。

## 权限设置

进入 QuickSight 控制台，点击右上侧个人头像，展开菜单，选择 “管理 Quicksight”。

从左侧选择菜单 "安全性和权限"，并点击“管理” 按钮。

选择目标 S3 Bucket，保存之后，权限即可设置完成。

## 新建数据集

新建数据集，选择 S3：

- 数据源名称: 随便写
- 清单文件：填写之前上传到 S3 的 manifest 的文件的 S3 地址即可

设置完成，点击 "连接"。

进入之后，设计您的展示界面。

## 配置 QuickSight 自动刷新

到 QuickSight 控制台主页，从左侧菜单选择菜单 "数据集" ，找到刚刚创建的数据集。

进入之后，点击 "刷新" Tab，并点击右上侧的 "立即刷新" 或者 "添加新计划".

- 立即刷新 可以手工立即导入新的数据。

- 添加新计划 可以按照周期（每小时，天，周，月）配置自动刷新。
