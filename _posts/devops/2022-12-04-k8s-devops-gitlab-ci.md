---
layout: post
title:  "容器 DevOps: Gitlab CI"
date:   2022-12-04 14:32:01 +0800
author: 啤酒云
categories: devops
tags: gitlab, gitops, 持续集成
---

当下 Gitlab 具备了 CI/CD 能力。 其 CI 流水线 主要定义在源代码根目录的 .gitlab-ci.yml 的文件里。这篇文章主要描述了如何编写 GitOps 方式的 gitlab-ci 文件。

## 示例描述

本文使用了 Gitlab SaaS 版本。SaaS 版本的 CI 每个月有 400min 的免费的额度。

本文的源代码在：<https://gitlab.com/cloudbeer/gateway>，这是一个 Spring Cloud gateway 应用。

ci 的过程包括：

- 编译 java 源码
- 打包 docker 镜像，并上传到镜像仓库（本文使用的是 AWS ECR 仓库）
- 修改部署目标脚本的镜像版本

完成这几个步骤之后，argocd 会接手 cd 的工作。

## .gitlab-ci.yml 代码拆解

### 环境变量

环境变量的定义有三种方式：

- 全局定义：左侧菜单 Settings -> CI/CD, 页面上 Variables 部分，展开 Expand。
- 在 yaml 文件里直接定义：参见下面的代码。
- 手工指定：在每次手工启动流水线时，可以填写变量。

```yaml
variables:
  DOCKER_DRIVER: overlay
  DOCKER_REGISTRY: 00000000.dkr.ecr.us-east-2.amazonaws.com
  AWS_DEFAULT_REGION: us-east-2
  DOCKER_HOST: tcp://docker:2375
```

### stages 的定义

首先定义几个 大的步骤：

```yaml
stages:
  - build
  - package
  - deploy
```

然后在各个步骤详情里，可以把当前的步骤进行分类，就像这样：

```yaml
do-something:
  stage: build
  image: alpine
  script: "sleep 300"
```

### 源码编译

对于编译型语言，需要将源代码进行编译，本示例中就是需要将 java 源代码编译打包成 jar 包。

```java
maven-build:
  image: maven:latest
  stage: build
  script: "mvn package"
  artifacts:
    paths:
      - target/*.jar
```

- 编译时使用 maven 这个镜像
- 运行的指令是 `mvn package`
- 编译的结果指定为 target 目录下的所有 jar 文件，gitlab 会将 artifacts 上传，供给后面的步骤使用。

### Docker 镜像打包上传

```yaml
docker-build:
  image:
    name: amazon/aws-cli
    entrypoint: [""]
  services:
    - docker:dind
  stage: package
  before_script:
    - amazon-linux-extras install docker
  script:
    - docker build -t $DOCKER_REGISTRY/$CI_PROJECT_NAME:$CI_COMMIT_SHORT_SHA .
    - aws ecr get-login-password | docker login --username AWS --password-stdin $DOCKER_REGISTRY
    - docker push $DOCKER_REGISTRY/$CI_PROJECT_NAME:$CI_COMMIT_SHORT_SHA

```

- 打包完成后需要上传到 ecr，而 ecr 依赖了 aws cli，所以使用了 aws_cli 的镜像包。在执行过程中，还需要将 AWS 的 AKSK 配置到环境变量。
- 在 before_script 里，在 aws_cli 镜像里安装 docker，此时使用了 dind (docker in docker) 模式。
- 在 docker build 的过程中，使用了 git 的 commiot sha 作为版本号。 CI_COMMIT_SHORT_SHA 是 gitlab 的内置环境变量。

> gitlab 的 dind 可以参考这个：<https://docs.gitlab.com/ee/ci/docker/using_docker_build.html>

> gitlab 内置环境变量参考：<https://docs.gitlab.com/ee/ci/variables/predefined_variables.html>

### 部署

在本示例中，采用了 gitops 的方式，将 CI 和 CD 完全解耦，CI 只需要做到构建完成，并更新部署代码仓库就可以了。剩下的工作交由 CD 来完成。

```yaml
yaml-change:
  stage: deploy
  image: line/kubectl-kustomize
  before_script:
    - apk add git
    - git clone https://cloudbeer:${GITHUB_PWD}@github.com/cloudbeer/cd-script.git "/${CI_COMMIT_SHA}"
    - git config --global user.email "cloudbeer@gmail.com"
    - git config --global user.name "gitlab-robot"
  script:
    - cd "/${CI_COMMIT_SHA}/gateway"
    - kustomize edit set image $DOCKER_REGISTRY/$CI_PROJECT_NAME:$CI_COMMIT_SHORT_SHA
    - cat kustomization.yaml
  after_script:
    - cd "/${CI_COMMIT_SHA}"
    - git add .
    - git commit -m "[skip ci]updating image $DOCKER_REGISTRY/$CI_COMMIT_SHORT_SHA"
    - git push origin main
```

- 镜像上传到镜像仓库后，就可以去修改部署代码了。本示例将部署代码放到了 github，您可以将部署代码放到任意 git 仓库。但在 gitops 模式下，部署脚本不建议和业务源代码放到一起。
- 本示例使用了 [kustomize](https://kustomize.io/) 来更新部署，kustomize 也被 argocd 默认支持。
- 过程是：将部署代码从 git 仓库拉回本地，通过 kustomize 命令修改了 image 的地址，修改完成后推回 git 仓库。

> GITHUB_PWD 需要配置一个 带有 scope 的 token，请到 <https://github.com/settings/tokens> 配置。

完整的代码如下：

```yaml
variables:
  DOCKER_REGISTRY: cloudbeer
  DOCKER_DRIVER: overlay
  DOCKER_HOST: tcp://docker:2375

stages:
  - build
  - package
  - deploy

maven-build:
  image: maven:latest
  stage: build
  script: "mvn package"
  artifacts:
    paths:
      - target/*.jar

docker-build:
  image: docker:20
  stage: package
  services:
    - docker:dind
  before_script:
    - docker info
  script:
    - docker build -t $DOCKER_REGISTRY/$CI_PROJECT_NAME:$CI_COMMIT_SHORT_SHA .
    - echo $DOCKER_PASS | docker login -u$DOCKER_USER --password-stdin
    - docker push $DOCKER_REGISTRY/$CI_PROJECT_NAME:$CI_COMMIT_SHORT_SHA

yaml-change:
  stage: deploy
  image: line/kubectl-kustomize
  before_script:
    - apk add git
    - git clone https://cloudbeer:${GITHUB_PWD}@github.com/cloudbeer/cd-script.git "/${CI_COMMIT_SHA}"
    - git config --global user.email "cloudbeer@gmail.com"
    - git config --global user.name "gitlab-robot"
  script:
    - cd "/${CI_COMMIT_SHA}/gateway"
    - kustomize edit set image $DOCKER_REGISTRY/$CI_PROJECT_NAME:$CI_COMMIT_SHORT_SHA
    - cat kustomization.yaml
  after_script:
    - cd "/${CI_COMMIT_SHA}"
    - git add .
    - git commit -m "[skip ci]updating image $DOCKER_REGISTRY/$CI_COMMIT_SHORT_SHA"
    - git push origin main
```

完整代码与文章正文会稍有出入，改用了公开的 github 和 docker hub 来存储 部署文件 和 镜像。

### 本项目的运行和测试过程

克隆项目

```shell
git clone https://gitlab.com/cloudbeer/gateway.git
```

上传到您自己的 gitlab 仓库，并启动自动构建。

修改构建脚本，将 部署仓库，镜像仓库分别改成您自己的地址。并将相关账号配置到 Variables 里。

改动代码后，如果您不想让 gitlab 自动启动 pipeline，在 commit 信息里加上 `[skip ci]xxxx` 即可。

观察构建过程，成功后，可以看到镜像仓库中增加了 版本(tag)， 部署仓库中的 gateway 目录里的 kustomization.yaml 被修改。

---

本文涉及的三个外部仓库，这三个仓库均为 public：

业务源代码：<https://gitlab.com/cloudbeer/gateway>

部署仓库：<https://github.com/cloudbeer/cd-script>

镜像仓库：<https://hub.docker.com/r/cloudbeer/gateway/tags>
