---
layout: post
title:  "使用 Gitlab in K8S 构建 Maven 类库到 AWS CodeArtifact"
date:   2022-12-12 20:59:33 +0800
author: 啤酒云
categories: aws, gitlab, devops, container
---

在很多项目里，需要共享类库，所以需要一个构建物仓库，在 AWS 就是 CodeArtifact。本文记录了如何使用 Gitlab 自动化构建 Java 类库，并上传到 CodeArtifact。

## 创建 CodeArtifact

打开控制台进行创建: <https://console.aws.amazon.com/codesuite/codeartifact/getting-started>，记得选择合适的 region，与您 Gitlab 部署地点尽量靠近。

创建完成后，可以查看连接说明。

## 配置 Maven 的 settings

官方文档是将 settings.xml 配置到了宿主机，但在 k8s 中，可以考虑动态配置此文件。

我们将 settings.xml 的内容先丢到 Gitlab 的变量中去。我存在 `M2_SETTINGS` 变量里了。

```xml
<settings>
  <profiles>
    <profile>
      <id>cloudbeer-mvn</id>
      <activation>
        <activeByDefault>true</activeByDefault>
      </activation>
      <repositories>
        <repository>
          <id>cloudbeer-mvn</id>
          <url>ARTIFACT_URL</url>
        </repository>
      </repositories>
    </profile>
  </profiles>
  <servers>
    <server>
      <id>cloudbeer-mvn</id>
      <username>aws</username>
      <password>CODEARTIFACT_AUTH_TOKEN</password>
    </server>
  </servers>
</settings>
```

- 此变量会以环境变量 `M2_SETTINGS` 出现在 Pod 中。
- 这个 `<password>CODEARTIFACT_AUTH_TOKEN</password>` 和 `<url>ARTIFACT_URL</url>` 会在 CI 的过程中替换掉。
- 这里不能用 `${CODEARTIFACT_AUTH_TOKEN}` 这样方式，会被 CI 过程替提前换掉。

## 设置 Gitlab CI

添加如下的 `.gitlab-ci.yml` 文件：

```yaml
stages:
  - mvn-deploy

build:
  image: maven:latest
  stage: mvn-deploy
  before_script:
    - mkdir -p ~/.m2/repository
    - apt update
    - apt install unzip
    - cd /tmp
    - curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    - unzip awscliv2.zip
    - ./aws/install
    - export CODEARTIFACT_AUTH_TOKEN=`aws codeartifact get-authorization-token --domain cloudbeer --domain-owner $AWS_ACCOUNT_ID --region $AWS_REGION --query authorizationToken --output text`
    - echo $M2_SETTINGS | sed -e 's/CODEARTIFACT_AUTH_TOKEN/${CODEARTIFACT_AUTH_TOKEN}/g;" -e "s/ARTIFACT_URL/${ARTIFACT_URL}/g' > ~/.m2/settings.xml
  script:
    - cd $CI_PROJECT_DIR
    - mvn deploy "-Daether.checksums.algorithms=MD5"
```

- 使用了 maven 作为编译镜像，并安装了 aws cli 命令行工具。
- 通过 shell 脚本将动态 CODEARTIFACT_AUTH_TOKEN 和仓库地址 ARTIFACT_URL 替换掉并写入 `.m2/settings.xml` 配置信息中。
- `-Daether.checksums.algorithms=MD5` 这个解决上传过程的 checksum 警告信息。

> 本文中，设置了如下的环境变量：
>
> - ARTIFACT_URL: Maven / CodeArtifact 仓库地址
> - M2_SETTINGS: Maven 的 .m2/settings.xml 配置
> - AWS_ACCESS_KEY_ID
> - AWS_SECRET_ACCESS_KEY
> - AWS_REGION
> - AWS_ACCOUNT_ID

## Build by Tag

正式版本类库我们只想被 tag 触发。

```bash
git tag v1.0.0
git push origin v1.0.0
```

可以添加 `only: tags` 触发标记，整体如下：

```yaml
stages:
  - mvn-deploy

build:
  image: maven:latest
  stage: mvn-deploy
  only:
    - tags
  before_script:
    - mkdir -p ~/.m2/repository
    - apt update
    - apt install unzip
    - cd /tmp
    - curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    - unzip awscliv2.zip
    - ./aws/install
    - export CODEARTIFACT_AUTH_TOKEN=`aws codeartifact get-authorization-token --domain cloudbeer --domain-owner $AWS_ACCOUNT_ID --region $AWS_REGION --query authorizationToken --output text`
    - echo $M2_SETTINGS | sed -e 's/CODEARTIFACT_AUTH_TOKEN/${CODEARTIFACT_AUTH_TOKEN}/g;s/ARTIFACT_URL/${ARTIFACT_URL}/g' > ~/.m2/settings.xml
  script:
    - cd $CI_PROJECT_DIR
    - mvn deploy "-Daether.checksums.algorithms=MD5"
```

> 请注意，设置了 protected 的环境变量默认不能被传入 tags 触发的 build。
>
> 这个可以修改，在项目的 Settings -> Repository -> Protected tags，可以将 tag 为 `v*` 或者 `*-release` 的保护起来。
>
> 您需要查询一下 `v*`，然后选择最底下的 create v* 才能创建匹配规则。

同时 Java 项目的 pom.xml 可以写成这样：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.amazon.devax</groupId>
    <artifactId>eshop-commons</artifactId>
    <version>${version}</version>

    <packaging>jar</packaging>
    <properties>
        <version default-value="1.0.0-SNAPSHOT">${env.CI_COMMIT_TAG}</version>
    </properties>

    <dependencies>
    </dependencies>
    <distributionManagement>
        <repository>
            <id>cloudbeer-mvn</id>
            <url>${env.ARTIFACT_URL}</url>
        </repository>
    </distributionManagement>
</project>

```

- version 这个属性，取了 CI_COMMIT_TAG 这个值，这个环境变量就是 git commit 的 tag 名称。
- 最后 deploy 的时候，版本号就会和 git 的 tag 保持一致。

---

参考文档：

- [Maven packages in the Package Repository](https://docs.gitlab.com/ee/user/packages/maven_repository/)
- [安装或更新最新版本的 AWS CLI](https://docs.aws.amazon.com/zh_cn/cli/latest/userguide/getting-started-install.html)
- [Use CodeArtifact with mvn](https://docs.aws.amazon.com/codeartifact/latest/ug/maven-mvn.html)
