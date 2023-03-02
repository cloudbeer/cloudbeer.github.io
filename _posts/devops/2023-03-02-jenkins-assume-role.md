---
layout: post
title:  "在 AWS 里，使用 Jenkins 跨账号执行任务"
date:   2023-03-02 15:02:33 +0800
author: 啤酒云
categories: devops, aws
---

在 AWS 中，企业的 Jenkins 通常安装在开发测试环境，如果需要操作生产环境中的资源，如何设置权限呢？本文介绍了方法。

## Jenkins Configuration （Jenkins 设置）

As a Jenkins administator, Menu: Manage Jenkins -> Manage Plugins, Search "Pipeline: AWS Steps", ensure this Jenkins plugin is installed.

以 Jenkins 的管理员身份登录，进入菜单： Manage Jenkins -> Manage Plugins，搜索 "Pipeline: AWS Steps"，安装这个插件。

From "Manage Jenkins  -> Configure System" to enable 'Retrieve credentials from node'.

在菜单 "系统管理 -> 系统配置" 中，启用 "Pipeline: AWS Steps" 的 "Retrieve credentials from node"。

## Node settings 节点设置（Jenkins 运行节点）

My Jenkins is installed in an EC2 instace and the workers in EC2 also.

Firstly, Bind a role to the EC2. Choose the Jenkins EC2, then choose Actions -> Security -> Modify IAM role.

现在设置 Jenkins 所在的 EC2 的角色。

选择目标 EC2，并选择如图的菜单：

![Set EC2 Role](/assets/posts/devops/Jenkins-assume-01.png)

Next, you can choose a role, or create a new one.

When you update the IAM role of EC2, your Jenkins will be granted the role.

现在请选择一个 role，或者创建一个新的。

选择好之后，更新 EC2 的 Role。

## Create an IAM Role in another account （在另一个账号中创建角色）

Now, We can login to the production account.

Create a new role:

现在登录到生产账号。并创建一个角色。

- Trusted entity type: Amazon Web Services account
- An Amazon Web Services account: Another Amazon Web Services account of the account id of Jenkins installed (number, such as 12345679012).
- Next choose some permissions policy.
- Give the role a name, such as 'for-Jenkins'.

## Modify the Jenkins EC2 role

Now back to the Jenkins account. Modify the ec2 role.

In the "Permisions" tab, choose "Add permissions -> Create inline policy":

现在返回 Jenkins 所在的账号，给刚刚 EC2 的角色进行角色扮演。

在角色设置面板设置一个内联策略，进入 "Permisions" tab, 选择 "Add permissions -> Create inline policy":

The policy is like:

```json
{
    "Version": "2012-10-17",
    "Statement": {
        "Effect": "Allow",
        "Resource": "arn:aws-cn:iam::<your-prod-account-id>:role/for-Jenkins",
        "Action": "sts:AssumeRole"
    }
}
```

## Jenkinsfile

Now the Jenkinsfile maybe as:

Jenkinsfile 这么写就行:

```groovy
pipeline {
  agent any
  stages {
    stage('build') {
      steps {
        script {
          withAWS(role:'for-Jenkins', roleAccount:'<your-prod-account-id>', region: 'cn-northwest-1') {
            def res = s3Upload(file:'readme.md', bucket:'xxxx', path:'readme.md')
            println(res)
          }
        }
      }
    }
  }
}

```

You will see the file uploaded to the target s3 bucket if the permissions are right.

如果权限设置合理，就可以看到 Jenkins 成功上传文件到另一个账号了。

```shell
...
Setting AWS region cn-northwest-1 
 Retrieving credentials from node.
Requesting assume role
Assuming role ARN is arn:aws-cn:iam::123456789012:role/ role arn:aws-cn:sts::123456789012:assumed-role/for-Jenkins/Jenkins-Jenkins-withAWS-gitee-16 with id AROATUJBXHIVWAC6AZW3X:Jenkins-Jenkins-withAWS-gitee-16 
 [Pipeline] {
[Pipeline] s3Upload
Uploading file:/var/Jenkins_home/workspace/Jenkins-withAWS_gitee/readme.md to s3://xxxxx/readme.md 
Finished: Uploading to xxxxx/readme.md
Upload complete
[Pipeline] echo
s3://xxxxx/readme.md
[Pipeline] }
[Pipeline] // withAWS
[Pipeline] }
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // withEnv
[Pipeline] }
[Pipeline] // node
[Pipeline] End of Pipeline
Finished: SUCCESS
...
```

## More

Mybe your Jenkins worker runs in a pod. In this situation, you can use [IRSA style](https://docs.aws.amazon.com/zh_cn/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up-enable-IAM.html) to assume role between accounts.

If you use AKSK in Jenkins, you can assume the role to the IAM user of AKSK.

如果 Jenkins 安装在 EKS 的 Pod 里，那么可以利用 [IRSA 方式](https://docs.aws.amazon.com/zh_cn/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up-enable-IAM.html) 进行角色扮演。

另外一点，如果在 Jenkins 里使用的是 AKSK，那么就把角色扮演到 AKSK 对应的 IAM User 即可。

---

References：

[Jenkins plugin: Pipeline: AWS Steps](https://plugins.Jenkins.io/pipeline-aws/)
