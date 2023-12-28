---
layout: post
title:  "使用 EventBridge 调度 AWS Lambda"
date:   2023-12-28 12:10:49 +0800
author: 啤酒云
categories: aws
---

得益于 Lambda 的免运维，快速部署等特性，现在越来越多的应用都使用 Serverless 技术。本文演示了一个场景，定时调度 Lambda，将 AWS 的 EC2 资源导出到 AWS 的数据湖 - S3 存储桶。

## 创建项目

使用 AWS SAM 创建项目，创建目录后：

```shell
sam init
```

我选择的 python 和 zip。

创建好了之后，我不准备使用 HelloWorld 目录，所以新建了一个目录 aws.

现在的文件结构大概如下：

```shell
├── README.md
├── __init__.py
├── aws
│   ├── __init__.py
│   ├── ec2.py
│   └── requirements.txt
├── events
│   ├── event.json
│   └── params.json
├── samconfig.toml
├── template.yaml
```

## 代码编写和解读

requirements.txt 里增加 boto3 即可。

ec2.py 这个文件，我准备用来导出 ec2 实例信息。

```python
import boto3
import random
import os
import datetime

s3_bucket = os.environ["S3Bucket"]

client = boto3.client("ec2")

def handler(event, context):
    ec2 = boto3.resource("ec2")
    print(get_date_str())

    tmpFile = "/tmp/ec2-info.csv"  # Lambda 里这个目录是可写的

    f = open(tmpFile, "w")
    f.write(
        "instance_name,availability_zone,private_ip,cpu_qty,memory_gb,disk_gb,owner1,operating_system\n"
    )

    for instance in ec2.instances.all():
        line = []
        instaceTypeInfo = get_ec2_info(instance)
        tags = instance.tags
        line.append(get_value(tags, "Name"))  # instance_name
        line.append(instance.placement["AvailabilityZone"])  # az

        line.append(instance.private_ip_address)  # private_ip
        line.append(
            str(instance.cpu_options["CoreCount"])
            if "CoreCount" in instance.cpu_options
            else "Unkown"
        )  # cpu_qty
        line.append(str(instaceTypeInfo["Memory"] / 1024))  # memory_gb
        line.append(str(get_ebs_info(instance.id)["size"]))  # disk_gb
        line.append(get_value(tags, "Owner1"))  # owner1
        line.append(instance.platform_details)  # operating_system
        f.write(",".join(line))
        f.write("\n")
    f.close()
    backup_s3_file(s3_bucket, "export-resources/ec2-info.csv")
    upload_s3(s3_bucket, "export-resources/ec2-info.csv", tmpFile)
    os.remove(tmpFile)
    return "OK"

# upload file
def upload_s3(bucket, key, file):
    s3 = boto3.resource(
        "s3"
    )
    s3.Bucket(bucket).upload_file(file, key)
    return "OK"


# get a string by date second
def get_date_str():
    now = datetime.datetime.now()
    return now.strftime("%Y%m%d%H%M%S") + "-" + str(random.randint(0, 999))

# change s3 filename to backup it
def backup_s3_file(bucket, key):
    s3 = boto3.resource(
        "s3"
    )
    try:  # first time change will raise error
        s3.Object(bucket, key + "." + get_date_str()).copy_from(
            CopySource=bucket + "/" + key, MetadataDirective="REPLACE"
        )
        s3.Object(bucket, key).delete()
    except Exception as ex:
        print(ex)

    return "OK"

# get value from dict
def get_value(tags, key):
    for tag in tags:
        if tag["Key"] == key:
            return tag["Value"]
    return "None"


# get cpu and memory info from instance_type
def get_ec2_info(instance):
    details = client.describe_instance_types(InstanceTypes=[instance.instance_type])
    # print(details)
    return {
        "VCpus": details["InstanceTypes"][0]["VCpuInfo"]["DefaultVCpus"],
        "Cores": details["InstanceTypes"][0]["VCpuInfo"]["DefaultCores"],
        "Memory": details["InstanceTypes"][0]["MemoryInfo"]["SizeInMiB"],
    }


# get ebs by instance id
def get_ebs_info(instance_id):
    ebses = client.describe_volumes(
        Filters=[{"Name": "attachment.instance-id", "Values": [instance_id]}]
    )

    count = 0
    size = 0
    for ebs in ebses["Volumes"]:
        count += 1
        size += ebs["Size"]

    return {"count": len(ebses["Volumes"]), "size": size}
```

上面的代码使用了 boto3 输出了所需要的 EC2 instances 信息，存到 csv 文件中，然后上传到 S3，并备份了旧文件。

实现按时调度，需要修改触发器，我们修改 `template.yaml` 文件:

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Transform: AWS::Serverless-2016-10-31
Description: >
  cloud-resources-exporter

  Sample SAM Template for cloud-resources-exporter

Globals:
  Function:
    Timeout: 900
    MemorySize: 256

Parameters:
  S3Bucket:
    Type: String
    Description: "SCV file location."

Resources:
  AWSEC2ExporterFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: aws/
      Handler: ec2.handler
      Runtime: python3.9
      Architectures:
        - arm64
      Policies:
        - AmazonEC2ReadOnlyAccess
      Environment:
        Variables:
          S3Bucket: !Ref S3Bucket
      Events:
        ScheduleEvent:
          Type: ScheduleV2
          Properties:
            ScheduleExpression: cron(0 * * * ? *)

Outputs:
  AWSEC2ExporterFunction:
    Description: AWS EC2 Exporter Function ARN
    Value: !GetAtt AWSEC2ExporterFunction.Arn
```

上述代码的一些重点：

- 在 Lambda 执行角色里增加了一个 托管策略：AmazonEC2ReadOnlyAccess
- S3Bucket 作为一个环境变量传入了 Lambda
- Events 部分定义了函数触发器：
  - ScheduleEvent 可以创建一个 EventBridge 计划
  - 此计划会自动绑定目标为当前的 Lambda 函数（注意：在 Lambda 控制台看不到此触发器）
  - ScheduleExpression 的支持 at(), rate() 和 cron()
    - at(yyyy-mm-ddThh:mm:ss)
    - rate(value unit)
    - cron(minutes hours day-of-month month day-of-week year)

## 调试和部署

本地调试：

设置好 AKSK之后：

本地创建文件 events/params.json :

```json
{
  "Parameters": {
    "S3Bucket": "xxx"
  }
}

```

执行命令：

```shell
sam build
sam local invoke AWSEC2ExporterFunction --env-vars events/params.json
```

## 部署到线上

```shell
sam deploy \
  --region us-east-1 \
  --parameter-overrides \
  S3Bucket=xxxx
```

上述整个代码里，没有一点 EventBridge 的痕迹，就是这么神奇地搞完了！

---
Schedule 参考(以为 aws 的为准)：

<https://docs.aws.amazon.com/scheduler/latest/UserGuide/schedule-types.html>

<https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-cron-expressions.html>

<https://crontab.guru/examples.html>
