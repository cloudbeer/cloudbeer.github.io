---
layout: post
title:  "Argo CD 入门"
date:   2022-12-05 16:20:01 +0800
categories: devops, argocd, container, gitops
---

在 GitOps 模式下，当 CI 完成容器打包后，还需要将部署脚本的容器版本号更新到 git 仓库，接下来的工作就可以交给容器内的 CD 来干了。这有效解耦了 CI/CD 过程。这个模式非常适合多云多集群的应用部署，以及有效协调运维部门和业务研发部门的工作。

## GitOps 和 Argo CD

GitOps 的基本概念:

参考这个：<https://www.weave.works/technologies/gitops/>。大概意思是：将 CI/CD 整个过程作为代码，存储在 git 仓库，基于 git 仓库中的代码和动作作为 CI/CD 的依据。CI/CD 系统会根据变动触发构建或部署过程。

Argo CD 的定义是：

在 Kubernetes 中声明式 GitOps 的持续交付工具。Argo CD is a declarative, GitOps continuous delivery tool for Kubernetes.

下面的示例中，将演示一下一个 CD 的过程。

## 简要安装(测试模式)

安装非常简单，过程如下：

创建 命名空间：

```shell
kubectl create namespace argocd
```

安装：

```shell
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

这样就可以了。

使用下面的命令验证安装结果：

```shell
kubectl get po -nargocd
```

显示结果如下：

```shell
NAME                                                READY   STATUS    RESTARTS      AGE
argocd-application-controller-0                     1/1     Running   0             64s
argocd-applicationset-controller-6779fd5cf5-ct5ck   1/1     Running   0             78s
argocd-dex-server-68f86575b6-xcrx6                  1/1     Running   2 (65s ago)   76s
argocd-notifications-controller-769b876844-wj6ck    1/1     Running   0             74s
argocd-redis-547f5d94cd-9rb94                       1/1     Running   0             72s
argocd-repo-server-77b686784d-2bkjp                 1/1     Running   0             69s
argocd-server-6f497ddb95-l4sxv                      1/1     Running   0             66s
```

如果在生产环境，请参考高可用模式安装: <https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/>

## 部署第一个 CD 应用

请 clone 这个 github 仓库 ，这里包含了应用部署脚本和 Argo CD 的脚本。

```shell
git clone https://github.com/cloudbeer/cd-script.git
```

下面我们尝试使用 argocd 持续升级 nginx 应用。

为此，我们需要编写 nginx 的 k8s 部署脚本。

### 代码说明

部署 nginx 应用：deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx
          ports:
            - containerPort: 80
              protocol: TCP
```

暴露 nginx 服务: service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  ports:
    - name: http-nginx
      port: 80
  selector:
    app: nginx
```

kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: nginx
commonLabels:
  app: nginx
resources:
  - deployment.yaml
  - service.yaml
images:
  - name: nginx
    newTag: "1.16"
```

上面编写的部署脚本，现在无须执行，先放到 git 仓库，
本示例的代码位于： <https://github.com/cloudbeer/cd-script/tree/main/nginx>

现在编写 Argo CD 的应用，此部分可以在 Web 界面配置（稍后我们去查看 Web UI），
Argo CD 的 Application 其实是在 K8S 中以 CRD 形式存在，就象下面的代码：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx
  namespace: default
spec:
  project: default
  destination:
    namespace: default
    server: "https://kubernetes.default.svc"
  source:
    repoURL: "https://github.com/cloudbeer/cd-script.git"
    targetRevision: HEAD
    path: nginx
  syncPolicy:
    automated: 
      prune: true
      selfHeal: true
```

拆解一下上面的代码：

- `kind: Application` 是 Argo CD 扩展的 CRD。
- `project: default` project 是 argocde 的逻辑组织单元，他可以按照 project 去分类维护 Application。
- `destination` 部分描述了我们需要部署的目标为当前集群的 default 命名空间。(如果部署到其他命名空间，请先创建 ns，或者在 yaml 指定)。
- `source` 表示部署文件所在的 git 地址。本例中是这个 git 仓库的 nginx 目录。
- `syncPolicy` 是同步策略，自动策略中包括开关：
  - `automated.prune`: 字面意思是 修剪，如果设置为 true，他可以允许删除 yaml 里没有的资源以保持部署与描述一致。
  - `automated.selfHeal`: 设置为 true 的时候，Argo CD 会定期检查当前集群的状态和 yaml 描述是否一致，如果不一致，则会触发部署。

### 部署

现在请将上述 Application 部署到 K8S 集群 中。

```yaml
kubectl apply -f applications/nginx.yaml
```

检查部署结果:

```yaml
kubectl get app -nargocd
```

可以看到应用已经同步了：

```shell
NAME    SYNC STATUS   HEALTH STATUS
nginx   Synced        Healthy
```

同时检查一下业务应用部署结果：

```shell
kubectl get po -ndefault
```

查看一下当前部署的版本：

```shell
kubectl get deploy nginx -oyaml | grep image:
```

现在我们尝试更新一下 nginx 的版本号，修改一下 kustomization.yaml 文件中的版本号。然后持续观察部署结果。

> 通常修改 kustomization 的动作是由 CI 系统来完成的，在上一章文章 [Gitlab CI](/2022/12/k8s-devops-gitlab-ci.html) 里我们已经演示了如何 修改  kustomization.yaml 这个文件了。

### 使用 Web UI

先查询一下密码：

```shell
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

映射端口：

```shell
kubectl port-forward svc/argocd-server -n argocd 8080:80
```

然后访问 <http://localhost:8080>，登录用户名 admin，密码为刚刚查询的密码。

登录进去之后，就可以看到 Web 界面了，在 Web 里，可以看到很多绚烂的内容。
