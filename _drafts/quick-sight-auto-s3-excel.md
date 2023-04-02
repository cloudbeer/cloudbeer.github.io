---
layout: post
title:  "使用 Quicksight 自动显示 S3 的 Excel 文件"
date:   2053-10-06 21:10:49 +0800
author: 啤酒云
categories: aws
---


Amazon QuickSight 支持使用 Amazon S3 manifest 文件来批量导入数据集

### Amazon S3 manifest 文件

manifest 文件是一个包含 Amazon S3 对象位置和元数据的 JSON 文件。以下是一个示例 Amazon S3 manifest 文件：

```json
{
  "entries": [
    {
      "url": "s3://my-bucket/salesdata/q1/report1.csv",
      "mandatory": true,
      "meta": {
        "sales_period": "Q1"
      }
    },
    {
      "url": "s3://my-bucket/salesdata/q1/report2.csv",
      "mandatory": true,
      "meta": {
        "sales_period": "Q1"
      }
    },
    {
      "url": "s3://my-bucket/salesdata/q2/report1.csv",
      "mandatory": true,
      "meta": {
        "sales_period": "Q2"
      }
    },
    {
      "url": "s3://my-bucket/salesdata/q2/report2.csv",
      "mandatory": true,
      "meta": {
        "sales_period": "Q2"
      }
    }
  ]
}
```

如果是实时的，可以使用 lambda 自动产生此文件。
