---
layout: post
title:  "在 AWS EKS 中部署 Gitlab"
date:   2022-12-10 17:50:33 +0800
author: 啤酒云
categories: devops, iac, aws
tags: gitlab, cdk, eks
---

本文记录了 Gitlab 在 Kubernetes 中的安装过程，目标是构建出生产可用的 Gitlab 系统。本文以 AWS EKS 为例。

## 在 AWS 部署 Gitlab 的前提条件

首先需要创建出合适的集群，Gitlab 对 EKS 集群的需求基本需求如下：

- Ingress: 需要安装 aws-load-balancer
- PV 卷: 需要安装 ebs-csi-driver
- HPA: 需要安装 metrics-server

生产环境下：

- PostgresSQL: 安装 RDS for Postgres。
- Redis: 安装 ElasticCache for Reids。

高级特性(非必须，这部分内容稍后探讨)：

- CI 过程的优化: 创建 Karpenter Provisinor
- CI 缓存: 创建 S3 存储桶
- 数据存储的高可用

因为 Gitlab 不会创建数据库本身，**需要首先在 Postgres 里创建一个数据库** `gitlab`，这个库名可以自定义，稍后指定到安装配置里。

## 部署 Gitlab

首先在 EKS 中 创建命名空间 gitlab：

```shell
kubectl create ns gitlab
```

 创建数据库和 SMTP Server 的密码 Secret:

```shell
kubectl apply -f - << EOF
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-password
  namespace: gitlab
type: Opaque  
stringData:
  psql-password: <your-psql-secret>
  smtp-password: <your-smtp-password>
EOF
```

- 这里的 name 和 key 可以自定义，稍后需要定义到 HelmChart 的配置中。
- 用户名是直接明文写在 Gitlab 的配置中的。
- Secret 需要配置到 Gitlab 的安装 namespace。

下面是完整的 HelmChart 的配置，这里的格式是 CDK，如果您使用 Helm 直接安装，试着转换成 Values.yaml:

```ts
import { ClusterInfo, ClusterAddOn } from '@aws-quickstart/eks-blueprints';


const smtpEmail = "cloudeer@gmail.com";
const psqlAddress = "<postgres-address>";
const redisAddress = "<redis-address>";

export class GitlabAddon implements ClusterAddOn {
  constructor() {
  }
  deploy(clusterInfo: ClusterInfo) {
    const vpc = clusterInfo.cluster.vpc;
    const scope = clusterInfo.getResourceContext().scope;

    clusterInfo.cluster.addHelmChart("gitlab", {
      chart: "gitlab",
      repository: "http://charts.gitlab.io/",
      version: "6.6.2",
      namespace: "gitlab",
      release: "abigfun",
      createNamespace: true,
      values: {
        global: {
          hosts: {
            domain: "abig.fun",
            https: false,
          },
          shell: {
            tcp: {
              proxyProtocol: true
            }
          },
          email: {
            display_name: 'GitLab',
            from: smtpEmail,
            reply_to: smtpEmail
          },
          smtp: {
            enabled: true,
            address: 'smtp.gmail.com',
            tls: false,
            port: 587,
            authentication: 'login',
            user_name: smtpEmail,
            starttls_auto: true,
            openssl_verify_mode: 'peer',
            password: {
              secret: 'gitlab-password',
              key: 'smtp-password'
            }

          },
          ingress: {
            tls: {
              enabled: false
            },
            configureCertmanager: false
          },
          psql: {
            host: psqlAddress,
            port: 5432,
            username: "postgres",
            database: "gitlab",
            password: {
              secret: "gitlab-password",
              key: "psql-password"
            },
          },
          redis: {
            host: redisAddress,
            port: 6379,
            password: {
              enabled: false
            }
          }
        },
        redis: {
          install: false
        },
        postgresql: {
          install: false,
        },
        "nginx-ingress": {
          controller: {
            service: {
              annotations: {
                "service.beta.kubernetes.io/aws-load-balancer-backend-protocol": "tcp",
                "service.beta.kubernetes.io/aws-load-balancer-proxy-protocol": "*"
              }
            },
            config: {
              "use-proxy-protocol": true
            }
          }
        },
        "gitlab-runner": {
          runners: {
            privileged: true,
            config: `
[[runners]]
  [runners.kubernetes]
    image = "ubuntu:20.04"
    privileged = true
  [[runners.kubernetes.volumes.empty_dir]]
    name = "docker-certs"
    mount_path = "/certs/client"
    medium = "Memory"
  [[runners.kubernetes.volumes.empty_dir]]
    name = "dind-storage"
    mount_path = "/var/lib/docker"
  [[runners.kubernetes.volumes.host_path]]
    name = "hostpath-modules"
    mount_path = "/lib/modules"
    read_only = true
    host_path = "/lib/modules"
  [[runners.kubernetes.volumes.host_path]]
    name = "hostpath-cgroup"
    mount_path = "/sys/fs/cgroup"
    host_path = "/sys/fs/cgroup"
            `
          }
        }
      }
    });
  }
}

```

代码解读：

- 需要配置一个域名，最好这个域名是真实的。本例中使用的是: abig.fun
- Gitlab 安装了一个 NginxIngress Controller，所以 AWS 的 LB 只需要使用 TCP 即可。
- 在 K8S 里构建 docker 镜像，需要给 runner 提权，并配置一些 volumes 绑定，如上面的 gitlab-runner.runners.config 配置节点

Gitlab 安装完成后，查看安装结果：

```shell
❯ kubectl get po -n gitlab
NAME                                                READY   STATUS      RESTARTS       AGE
abigfun-certmanager-7c98d5576b-64q2l                1/1     Running     0              139m
abigfun-certmanager-cainjector-c74d89b67-w8gwj      1/1     Running     0              139m
abigfun-certmanager-webhook-6c4fbb8c86-rkfl6        1/1     Running     0              139m
abigfun-gitaly-0                                    1/1     Running     0              139m
abigfun-gitlab-exporter-fb9dc9776-f5llm             1/1     Running     0              139m
abigfun-gitlab-runner-6f75dd5f8f-snlx5              1/1     Running     8 (109m ago)   139m
abigfun-gitlab-shell-77b9f4fcf9-2lxw8               1/1     Running     0              139m
abigfun-gitlab-shell-77b9f4fcf9-h99gf               1/1     Running     0              139m
abigfun-kas-6b4c6b9b7c-snjt5                        1/1     Running     0              140m
abigfun-kas-6b4c6b9b7c-vrqmv                        1/1     Running     0              139m
abigfun-migrations-2-2pxlh                          0/1     Completed   0              44m
abigfun-minio-596cb868fd-g87wj                      1/1     Running     0              140m
abigfun-minio-create-buckets-2-r4l75                0/1     Completed   0              44m
abigfun-nginx-ingress-controller-59dc9b7959-7xlv2   1/1     Running     0              139m
abigfun-nginx-ingress-controller-59dc9b7959-q96mn   1/1     Running     0              139m
abigfun-prometheus-server-76944cc9cf-srptg          2/2     Running     0              139m
abigfun-registry-864b87ccd8-hgcv6                   1/1     Running     0              139m
abigfun-registry-864b87ccd8-qvvgl                   1/1     Running     0              139m
abigfun-sidekiq-all-in-1-v2-7c98fb88fd-vkk9w        1/1     Running     0              44m
abigfun-toolbox-89cd5c577-twctl                     1/1     Running     0              43m
abigfun-webservice-default-849d958f64-nqfhr         2/2     Running     0              44m
abigfun-webservice-default-849d958f64-rr9q7         2/2     Running     0              43m
```

## 第一次运行 Gitlab

运行前，需要进行域名解析：

显示 ingress：

```shell
kubectl get ing -n gitlab
```

会看到所有的 ingress 都绑定到了一个经典 LB。

```shell
NAME                         CLASS           HOSTS               ADDRESS                                                                        PORTS   AGE
abigfun-kas                  abigfun-nginx   kas.abig.fun        xxxxxxxxxx.elb.amazonaws.com   80      58m
abigfun-minio                abigfun-nginx   minio.abig.fun      xxxxxxxxxx.elb.amazonaws.com   80      58m
abigfun-registry             abigfun-nginx   registry.abig.fun   xxxxxxxxxx.elb.amazonaws.com   80      58m
abigfun-webservice-default   abigfun-nginx   gitlab.abig.fun     xxxxxxxxxx.elb.amazonaws.com   80      58m
```

现在去添加解析。分别将上述 HOSTS 中的域名 CNAME 到 `xxxxxxxxxx.elb.amazonaws.com`。

等域名生效。访问 <http://gitlab.abig.fun>

首先注册一个用户。

管理员账号：root

初始密码：

```shell
kubectl get secret --namespace "gitlab" abigfun-gitlab-initial-root-password -o jsonpath="{.data.password}" | base64 -d
```

使用管理账号进入之后，审批一下 刚刚注册的账号。

## 功能测试

使用刚刚自己注册的账号登录，创建一个项目，并添加一个文件: `.gitlab-ci.yml`。 这部分可以测试 git 源代码管理功能。

.gitlab-ci.yml 的内容如下：

```yaml
variables:
  DOCKER_DRIVER: overlay2
  DOCKER_HOST: tcp://docker:2376
  DOCKER_TLS_CERTDIR: "/certs"
  DOCKER_TLS_VERIFY: 1
  DOCKER_CERT_PATH: "/certs/client"

stages:
  - package

docker-build:
  image: docker:20
  stage: package
  services:
    - docker:dind
  before_script:
    - sleep 5
    - docker info
  script:
    - echo "Hehe"

```

- 上面的示例可以测试 docker dind 是否正常
- sleep 5 是为了...我也说不清，新版本的 docker 加一下这个就正常了，我觉得是个坑，搞了很久才发现是这个原因。

水一段文字记录一下成功结果：

```shell
Running with gitlab-runner 15.6.0 (44a1c2be)
  on abigfun-gitlab-runner-8567dfbd8-bcg84 xJfSsxKi
Preparing the "kubernetes" executor
00:00
Using Kubernetes namespace: gitlab
Using Kubernetes executor with image docker:20 ...
Using attach strategy to execute scripts...
Preparing environment
00:03
Waiting for pod gitlab/runner-xjfssxki-project-2-concurrent-0wrtsq to be running, status is Pending
Running on runner-xjfssxki-project-2-concurrent-0wrtsq via abigfun-gitlab-runner-8567dfbd8-bcg84...
Getting source from Git repository
00:01
Fetching changes with git depth set to 20...
Initialized empty Git repository in /builds/[MASKED]/gateway/.git/
Created fresh repository.
Checking out 7fb43706 as main...
Skipping Git submodules setup
Executing "step_script" stage of the job script
00:06
$ sleep 5
$ docker info
Client:
 Context:    default
 Debug Mode: false
 Plugins:
  buildx: Docker Buildx (Docker Inc., v0.9.1)
  compose: Docker Compose (Docker Inc., v2.14.0)
Server:
 Containers: 0
  Running: 0
  Paused: 0
  Stopped: 0
 Images: 0
 Server Version: 20.10.21
 Storage Driver: overlay2
  Backing Filesystem: extfs
  Supports d_type: true
  Native Overlay Diff: true
  userxattr: false
 Logging Driver: json-file
 Cgroup Driver: cgroupfs
 Cgroup Version: 1
 Plugins:
  Volume: local
  Network: bridge host ipvlan macvlan null overlay
  Log: awslogs fluentd gcplogs gelf journald json-file local logentries splunk syslog
 Swarm: inactive
 Runtimes: io.containerd.runtime.v1.linux runc io.containerd.runc.v2
 Default Runtime: runc
 Init Binary: docker-init
 containerd version: 1c90a442489720eec95342e1789ee8a5e1b9536f
 runc version: v1.1.4-0-g5fd4c4d1
 init version: de40ad0
 Security Options:
  seccomp
   Profile: default
 Kernel Version: 5.10.135
 Operating System: Alpine Linux v3.17 (containerized)
 OSType: linux
 Architecture: x86_64
 CPUs: 2
 Total Memory: 7.655GiB
 Name: runner-xjfssxki-project-2-concurrent-0wrtsq
 ID: MS4S:WD6L:NYMX:Q2EK:AASW:ICI5:2PSL:DARY:5EZ5:FYNP:IPCK:3WVF
 Docker Root Dir: /var/lib/docker
 Debug Mode: false
 Registry: https://index.docker.io/v1/
 Labels:
 Experimental: false
 Insecure Registries:
  127.0.0.0/8
 Live Restore Enabled: false
 Product License: Community Engine
$ echo "Hehe"
Hehe
Job succeeded
```

## 其他

### 创建内网 Postgres 数据库

数据库没有公网，没有跳板机，我使用了如下方法：

```shell
kubectl run psql-client -ndefault --env="POSTGRES_PASSWORD=pAssw0rd" --image=postgres 
```

```shell
kubectl exec -ndefault -it psql-client -- sh
```

```shell
psql -h <postgres-host> -U postgres -W 
```

```sql
CREATE DATABASE gitlab;
```

感觉好傻！
