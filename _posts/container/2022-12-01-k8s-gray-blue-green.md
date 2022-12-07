---
layout: post
title:  在 K8S 中实现 灰度，蓝绿 发布
date:   2022-12-01 16:09:00 +0800
author: 啤酒云
categories: container, devops
tags: kubernetes, 蓝绿, 灰度, 容器
---

在基本的 K8S 中，没有提供方便细粒度的流量分配策略。但借助 K8S 的 selector 机制，仍然可以实现简单的灰度和蓝绿发布。

## 应用部署

应用版本 1

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ng-v1
spec:
  replicas: 4
  selector:
    matchLabels:
      app: ng
  template:
    metadata:
      labels:
        app: ng
        version: v1
    spec:
      containers:
        - name: ng
          image: nginx:1.22
```

应用版本 2

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ng-v2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ng
  template:
    metadata:
      labels:
        app: ng
        version: v2
    spec:
      containers:
        - name: ng
          image: kong/httpbin
```

- 为了演示版本不同，分别部署了 2 个完全不同的应用作为演示。
- 这俩应用有着相同的 label: app 以及不同的 label: version

## 灰度发布

首先创建一个 service，这个 service 对外暴露服务使用了 app=ng 作为选择器。

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ng
spec:
  ports:
    - port: 80
  selector:
    app: ng
```

由于 service 本身是按照 RR 的策略进行轮询的，所有对应的 pod endpoint 得到的流量会保持一致。

所以上述代码中，流量会按照 pod 数量分配，此示例中 v1:v2 流量比例为 4:1。通过改变 pod 的数量就可以实现**粗糙的**灰度了。

启动一个 pod 测试一下：

```shell
kubectl run -it --rm test --image=nginx:1.22 --restart=Never -- sh
```

在终端中重复执行多次 curl，查看会发现流量按照 4:1 的比例分配了。

```shell
curl ng
```

这个 bash 代码模拟了每隔 5 秒逐步增加 V2 的流量，通过 4 次改变 pod 数量，最终将流量完全切换到 v2。

```bash
#!/bin/bash
v1count=5
v2count=0
for i in {1..5}
do
  v1count=$((v1count-1))
  v2count=$((v2count+1))
  kubectl scale deployment ng-v1 --replicas $v1count
  kubectl scale deployment ng-v2 --replicas $v2count
  sleep 5
done
```

这个方法不适合如下情况：

- pod数量只有一两个的
- 需按一定规则灰度

## 蓝绿发布

需要修改 service，增加一个版本的 selector，让 service 固定在特定版本：

当应用是版本 v1 的时候：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ng
spec:
  ports:
    - port: 80
  selector:
    app: ng
    version: v1
```

实际生产中，先部署好 v2 版本，当验证无误后，可以通过修改 service 的 version 为 v2 。

现在测试一下：

先将 2 个版本部署成等量 pod。

```shell
kubectl scale deployment ng-v1 --replicas 1

kubectl scale deployment ng-v2 --replicas 1
```

初始的 service 为版本 v1：

```shell
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ng
spec:
  ports:
    - port: 80
  selector:
    app: ng
    version: v1
EOF
```

现在切换到 v2 版本，如下：

```shell
kubectl patch svc ng -p '{"spec":{"selector": {"app": "ng", "version": "v2"}}}'
```

## A/B test 发布

A/B test 意味着需要按照一定逻辑进行流量分发。

> 😭，臣妾做不到。

但可以借助 nginx 等产品完成。

事实上，一些第三方的 ingress 产品，以及 Service Mesh 就都可以解决这些问题的。

如果对延迟不敏感，可以考虑直接上 Istio 或 Linkerd 等 Service Mesh 产品。
