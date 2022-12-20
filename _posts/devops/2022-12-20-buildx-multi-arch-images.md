---
layout: post
title:  自动化构建多架构(amd, arm)镜像
date:   2022-12-20 17:40:33 +0800
author: 啤酒云
categories: devops, container, tucao, gitlab
---

现在很多软件发行的 Docker 镜像都会支持多架构，Docker 官方也有教程教大家如何实现，并且提供了一个 buildx 插件方便大家实现。本文使用 Gitlab CI 试了一下此插件，主要命令是 `docker buildx build --platform...`。

## 检查 docker 环境

检查官方的 docker 20 的镜像，运行 docker info 查看 Plugins：

```shell
$ docker info
Client:
 Context:    default
 Debug Mode: false
 Plugins:
  buildx: Docker Buildx (Docker Inc., v0.9.1)
  compose: Docker Compose (Docker Inc., v2.14.1)
...
```

已经内置了 buildx 插件。

## Gitlab CI 脚本

### 构建到官方仓库 docker hub

下面的示例 build 了一个 arm64 + amd64 的裸 JDK。

```yaml
dockerx:
  stage: test
  image: docker:20
  variables:
    DOCKER_DRIVER: overlay2
    DOCKER_HOST: tcp://docker:2376
    DOCKER_TLS_CERTDIR: /certs
    DOCKER_TLS_VERIFY: 1
    DOCKER_CERT_PATH: /certs/client
  services:
    - docker:20-dind
  before_script:
    - until docker version > /dev/null; do sleep 1; done
    - echo "FROM amazoncorretto:11" > Dockerfile
    - docker context create xbuilder-ctx
    - docker buildx create --name xbuilder --use xbuilder-ctx
    - docker buildx use xbuilder
  script:
    - echo $DOCKER_PASS | docker login -u$DOCKER_USER --password-stdin
    - docker buildx build --platform linux/arm64,linux/amd64 -t cloudbeer/$CI_PROJECT_NAME:$CI_COMMIT_SHORT_SHA --push .

```

- 主要的命令为 `docker buildx build --platform linux/arm64,linux/amd64`，可以直接指定平台架构。
- 在 19+ 版本的 docker 里，docker 生产的证书需要时间，为了安全起见，需要检测 docker 状态：`until docker version > /dev/null; do sleep 1; done`，等他没问题再进行下一步操作，否则任务会中断。
- `docker context, docker buildx create, docker buildx use` 这些解决了 "
ERROR: multiple platforms feature is currently not supported for docker driver.", "Docker buildx - could not create a builder instance with TLS data loaded from environment" 这些个错误。
- `docker buildx build... --push` 会直接把镜像构建结果推送到 docker bub。

构建结果：<https://hub.docker.com/r/cloudbeer/pure-ci/tags>

![Buildx result](/assets/posts/devops/docker-hub-multi.png)

### 推送到 AWS ECR

使用 AWS 的服务，一般离不开 aws cli，在本场景中，要么在 aws cli 镜像中安装 docker，要么在 docker 里安装 aws cli，下面是我的测试脚本，此脚本可以 run 到最后：

```yaml
dockerx-ecr:
  stage: test
  image: amazon/aws-cli
  variables:
    DOCKER_DRIVER: overlay2
    DOCKER_HOST: tcp://docker:2376
    DOCKER_TLS_CERTDIR: /certs
    DOCKER_TLS_VERIFY: 1
    DOCKER_CERT_PATH: /certs/client
  services:
    - docker:dind
  before_script:
    - amazon-linux-extras install docker
    - mkdir -p ~/.docker/cli-plugins/
    - until docker version > /dev/null; do sleep 1; done
    - docker container create --name buildx docker/buildx-bin sh
    - docker cp buildx:/buildx ~/.docker/cli-plugins/docker-buildx
    - echo "FROM amazoncorretto:11" > Dockerfile
    - docker context create xbuilder-ctx
    - docker buildx create --name xbuilder --use xbuilder-ctx
    - docker buildx use xbuilder
  script:
    - aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $DOCKER_REGISTRY
    - docker buildx build --platform linux/arm64,linux/amd64 -t $DOCKER_REGISTRY/$CI_PROJECT_NAME:$CI_COMMIT_SHORT_SHA --push .
```

上面的脚本大部分都成功了，最后还是折了。下面是一些坑总结（吐槽模式开启）：

- 使用 官方 docker 镜像作为基础镜像构建，会发现 awscli v2 装不上， awscli v2 安装到 alpine 需要编译，不是简单加几个依赖包就行的，这个懒得折腾了。
- 使用 pip 官方安装的 awscli v2 居然是在 docker 里运行的，这是在搞笑吗？我本来就是个 dind，套娃了啊。
- 使用 aws-cli 镜像作为底包，`amazon-linux-extras install docker` 这个安装的 docker 居然把 plugins 都干掉了。干掉 compose 可以理解，为啥把 buildx 这么好的工具干掉了。
- 安装 buildx 插件，可以直接从 buildx 镜像包中拷贝，命令是 `docker container create` 和 `docker cp`。
- 使用 AWS ECR 别忘记要先建库。
- 使用 AWS ECR 别忘记要先建库。
- 使用 AWS ECR 别忘记要先建库。
- **我忘记了。**

最终的部分 log 贴在下面：

```shell
...
$ aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $DOCKER_REGISTRY
Login Succeeded
#3 transferring context: 2B done
#3 DONE 0.1s
#4 [linux/arm64 internal] load metadata for docker.io/library/amazoncorretto:11
#4 DONE 2.6s
#5 [linux/amd64 internal] load metadata for docker.io/library/amazoncorretto:11
#5 DONE 2.6s
...
#6 [linux/amd64 1/1] FROM docker.io/library/amazoncorretto:11@sha256:6962bc64de2b612c2a760299956853762cfcee538b1b6b55706661426546936c
#6 DONE 0.1s
#8 exporting to image
#8 exporting layers done
#8 exporting manifest sha256:3dd903be615ce4c36321b161806bc061a567079a2947ec658cdcd14d1c114235 0.0s done
#8 exporting config sha256:8b9bb2aca3d28e14fa06412d152fd4ce6c7a55f1554bec3c71ce4a4410060af3
#8 exporting config sha256:8b9bb2aca3d28e14fa06412d152fd4ce6c7a55f1554bec3c71ce4a4410060af3 0.0s done
#8 exporting manifest sha256:4218135aa38e8522e988b60392190cd7bfc1715cedb3f301f82cec43fee383e2 0.0s done
#8 exporting config sha256:de3379d966e1b03cf4c7f3c6db803f459cf1c3e887fbe2c10af9ce0c72a6f406 0.0s done
#8 exporting manifest list sha256:dc0282c4166a58f7b8298e5061a00c02c6bce6e358000b479e49e6d73cf57b34 0.0s done
#8 pushing layers
#8 ...
#9 [auth] sharing credentials for [MASKED].dkr.ecr.us-east-1.amazonaws.com
#9 DONE 0.0s
#8 exporting to image
#8 ...
#7 [linux/amd64 1/1] FROM docker.io/library/amazoncorretto:11@sha256:6962bc64de2b612c2a760299956853762cfcee538b1b6b55706661426546936c
#7 sha256:74c4a50287c9345fabef12ad41b61e3450e3400fbe99f5d48281ceb781041ae3 147.75MB / 147.75MB 2.6s done
#7 sha256:5b4a36b5b78f93a5f470cf722b313bb32cddb0f8e0fa0db348059b5c0881b04f 62.33MB / 62.33MB 1.0s done
#7 DONE 2.9s
#6 [linux/arm64 1/1] FROM docker.io/library/amazoncorretto:11@sha256:6962bc64de2b612c2a760299956853762cfcee538b1b6b55706661426546936c
#6 sha256:c0aade9a94f7c23d8fc79b4c11ce14d37b8569a6fec3017a295169ff500ec8d8 144.91MB / 144.91MB 2.9s
#6 sha256:6cbfee25f0741b3d3f4d2474d904a200cd8404a01aa17813bf3fc3d4ebb551a4 63.96MB / 63.96MB 1.8s done
#6 sha256:c0aade9a94f7c23d8fc79b4c11ce14d37b8569a6fec3017a295169ff500ec8d8 144.91MB / 144.91MB 3.0s done
#6 DONE 3.1s
#8 exporting to image
#8 pushing layers 17.6s done
#8 pushing manifest for [MASKED].dkr.ecr.us-east-1.amazonaws.com/pure-ci:1ac460d1@sha256:dc0282c4166a58f7b8298e5061a00c02c6bce6e358000b479e49e6d73cf57b34
#8 pushing manifest for [MASKED].dkr.ecr.us-east-1.amazonaws.com/pure-ci:1ac460d1@sha256:dc0282c4166a58f7b8298e5061a00c02c6bce6e358000b479e49e6d73cf57b34 2.2s done
#8 DONE 19.8s
Job succeeded
```

## 不是本文的总结

- 使用 docker-buildx 会直接使用相应架构的底层依赖镜像，如果使用这种方法，您不能将一个有架构依赖的可执行文件直接拷贝构建镜像，否则会出现底层包和业务包对不上的问题。
- 可以将构建过程放到 Dockerfile 里面去，Docker 有完整的多阶段构建的模式来生产您的镜像（如 go 语言）。
- 对于脚本类型的语言，完全可以用这种方式构建，依赖包安装也应该在 Dockerfile 中进行。
- Java 的普通运行包可以使用直接拷贝的方式，X86 环境下构建的 jar 包可以直接运行在 ARM 的 jdk 中。
- Dockerfile 的底包也应该是多架构的，请不要强制指定具体的 sha256 值。
