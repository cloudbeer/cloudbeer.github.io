---
layout: post
title:  "EKS Ingress 跨账号创建 ALB"
date:   2023-05-06 09:10:49 +0800
author: 啤酒云
categories: aws, container
---

在企业级生产环境下，通常会把网络服务，安全服务等产品放在统一一个公网账号下进行管理，各个业务模块也可能使用独立的账号，并且与**外网隔离**。 EKS 会被部署在隔离环境，那么如何创建对公网的 Ingress 呢？理想的做法是创建 Ingress 的时候直接把 ALB 创建到公网账号下，本文尝试实现这一过程。

先预设一下：

- 对公的账号为 AAAA， VPC 为 10.1.0.0/16
- EKS 账号为 BBBB，VPC 为 10.0.0.0/16

需要做的工作有：设置组织，设置网络(TGW)，共享，设置 IAM 权限，编写 EKS CRD。

> 本文是使用 China Region 实现的。

## 创建组织并启用相应权限

组织是共享子网的前提，通常多账号环境下会使用 组织来管理。

在 AAAA 账号中(在其他账号下亦可)：

进入 AWS 后台的 [组织控制台](https://console.amazonaws.cn/organizations/v2/home/)：

- 创建组织，并将账号纳入，在 AAAA 账号内邀请，在 BBBB 里接受邀请。
- 开启组织的 RAM 可信访问，进入 Amazon Organizations > 服务 > RAM， 开启可信访问

进入 [RAM 控制台](https://console.amazonaws.cn/ram/home#Settings:) 开启组织内共享：

- 进入 Resource Access Manager > 设置，开启 ”在以下服务中启用共享： Amazon Organizations “

## TGW 打通网络

在 AAAA 账号里：

创建一个 Transit Gateway:

- 进入 VPC 控制台，左侧选择菜单 中转网关，点击 ”创建 Transit Gateway“
- 进入中转网关挂载，”创建 Transit Gateway 挂载“，选择 AAAA 账号下的目标 VPC

共享 tgw

- 进入 RAM 控制台 [创建资源共享](https://console.amazonaws.cn/ram/home#CreateResourceShare:)
  - 共享的资源选择 中转网关
  - 委托人选择 组织，填写组织 ID (组织 ID 在 [组织的界面的 root](https://console.amazonaws.cn/organizations/v2/home/root) 下的 ARN 的第二段 /o-xxxx/ 内找到，形如 o-xxxxx)。

> 注意，在 AAAA 账号中的 VPC 中，必须至少创建 2 个 Public Subnet

在 BBBB 账号里现在可以看到 tgw 实例了：

- 进入 VPC，中转网关挂载，挂上 VPC。

分别在 AAAA 和 BBBB 账号里的子网路由里加入 tgw 对端路由（可以从目标子网的路由连接点击进入）：

- 在 AAAA 的 路由表里加入 16.0.0.0/16 - tgw-xxxxxx
- 在 BBBB 的 路由表里加入 16.1.0.0/16 - tgw-xxxxxx

至此，网络打通。

## 共享子网

为了在 EKS Ingress 里能发现 AAAA 账号的子网 ID，还需要共享子网。

在 AAAA 账号里共享对公子网：

在 RAM 中创建新的共享资源，资源里选择 子网，会发现，刚刚绑定了 tgw 的子网出现在共享名单里，选择对组织共享。

## 安全组

在 AAAA 账号中创建安全组，后续创建 Ingress 的时候需要显式指定此安全组。

## IAM

现在需要处理 IAM 权限了。

BBBB 中的 EKS 需要在 AAAA 账号里创建 ALB 等资源，所以需要把 AAAA 的 Role 赋予给  BBBB 的 EKS 的 loadbalancer-controller，下面是创建 IRSA 的过程：

### 在 AAAA 中加入身份提供商

进入 IAM 菜单的 身份提供商，

- 点击添加提供商，填写 oidc 的 Url。（这个 Url 可以通过 BBBB 账号的 eks 信息得到）
- 受众填写 sts.amazonaws.com
- 获取指纹，确定...

### 在 AAAA 中创建 Policy

policy 的 json 文件如下：

```shell
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.7/docs/install/iam_policy_cn.json
```

使用命令创建，或者在控制台把上面的文件内容贴进去：

```shell
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy_cn.json
```

### 在 AAAA 中创建 Role

现在创建一个 Role，选择 自定义信任策略。

信任策略的 JSON 内容如下：

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws-cn:iam::AAAA:oidc-provider/oidc.eks.region.amazonaws.com.cn/id/xxxxxx"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "oidc.eks.region.amazonaws.com.cn/id/xxxxxx:aud": "sts.amazonaws.com",
                    "oidc.eks.region.amazonaws.com.cn/id/xxxxxx:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
                }
            }
        }
    ]
}
```

名为 **AmazonEKSLoadBalancerControllerRole**，

在选型策略里添加权限，选择上一步创建的  AWSLoadBalancerControllerIAMPolicy 即可。

现在，我们完成了 IAM 的 Role 创建。

## 创建 EKS 资源

下面的操作在 BBBB 账号的 EKS 集群内完成。

### ServiceAccount

如果你已经安装了 EKS 的 aws-loadbalancer-controller，那么现在可以修改一下:

```shell
kubectl edit sa aws-load-balancer-controller -n kube-system
```

将 `eks.amazonaws.com/role-arn: arn:aws-cn:iam::BBBB:role/AmazonEKSLoadBalancerControllerRole` 修改为 `eks.amazonaws.com/role-arn: arn:aws-cn:iam::AAAA:role/AmazonEKSLoadBalancerControllerRole`

### 重新安装 aws-loadbalancer-controller

安装脚本如下：

```shell
eksName=abc
region=cn-north-1
pubcVpc=vpc-in-aaaa

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set region=${region} \
  --set clusterName=${eksName} \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set vpcId=${pubcVpc} \
  --set enableShield=false \
  --set enableWaf=false \
  --set enableWafv2=false

```

上面的 vpcId 需要填写 AAAA 账号的 vpcId，此 vpc 已经共享到 BBBB 账号，你可以在控制台看到。

如果之前使用 helm 安装过，先卸载一下：

```shell
helm uninstall aws-load-balancer-controller
```

如果之前没有安装过 aws-load-balancer-controller，你可以先创建一个 ServiceAccount，其中的 role-arn 填写 AAAA 账号的 Role，如下 YAML。

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws-cn:iam::AAAA:role/AmazonEKSLoadBalancerControllerRole
  name: aws-load-balancer-controller
  namespace: kube-system
```

至此，所有基础层的工作已经全部完成。🎆 🎉🎉🎉🎉🎉

### 测试 Ingress

先创建 Deployment 和 Service 资源(测试用)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
  template:
    metadata:
      labels:
        app: httpbin
    spec:
      containers:
        - name: httpbin
          image: public.ecr.aws/r2h3l6e4/pingcloud-clustertools/kennethreitz/httpbin:latest
          resources:
            requests:
              cpu: 250m
              memory: 250Mi
---
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: default
spec:
  ports:
    - name: http-httpbin
      port: 3000
      targetPort: 80
  selector:
    app: httpbin
```

创建 Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: x-ingress
  namespace: default
  annotations:
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/subnets: "subnet-aaaa-pub1, subnet-aaaa-pub2"
    alb.ingress.kubernetes.io/security-groups: "sg-aaaa-xxxx"
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: httpbin
                port:
                  number: 3000
```

需要加入如下注解才能把 Ingress 的 ALB 创建到 AAAA 账号：

- alb.ingress.kubernetes.io/target-type 为 ip
- alb.ingress.kubernetes.io/scheme: internet-facing 表示ALB
- alb.ingress.kubernetes.io/subnets 选择 AAAA 账号的对公子网
- alb.ingress.kubernetes.io/security-groups 为 AAAA 账号的安全组

### TargetGroupBinding

如果你想让 EKS 想使用已存在的 ALB，那么只需要将 Service 绑定给目标群组即可。

可以先在 AAAA 账号下创建一个 目标群组/Target groups，并创建如下的 TargetGroupBinding CRD 资源，如下：

```yaml
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata:
  name: static-alb
  namespace: default
spec:
  serviceRef:
    name: httpbin
    port: 3000
  targetGroupARN: <AAAA-target-goupd-arn>
```

创建好之后，就会看到该目标群组下 BBBB 账号的 pod 的 ip 了。

---
参考：

中转网关使用文档：<https://docs.amazonaws.cn/vpc/latest/tgw/tgw-transit-gateways.html>

[Expose Amazon EKS pods through cross-account load balancer](https://aws.amazon.com/cn/blogs/containers/expose-amazon-eks-pods-through-cross-account-load-balancer/)
