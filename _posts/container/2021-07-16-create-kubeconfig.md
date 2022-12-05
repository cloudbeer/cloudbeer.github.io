---
layout: post
title:  "生产有权限控制的 kubeconfig"
date:   2021-07-16 09:53:06 +0800
author: 啤酒云
categories: container
---
​
在开发测试场景中，我们开通了 k8s 集群，需要把集群的资源分配给使用者，但希望他们只能在自己的命名空间使用资源，不影响其他人的。

下面的过程展示了如何使用 k8s 原生能力做到这一点。

## 实现步骤

### 创建 namespace

首先创建一个使用者名字的命名空间

```shell
kubectl create ns well
```

### 创建 ServiceAccount

在用户命名空间下创建 SA

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: well-sa
  namespace: well
```

### 创建一个 Role

在用户命名空间下创建 Role，这里将你希望给使用者的资源和权限放进去。

```yaml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: well-role
  namespace: well
rules:
- apiGroups: [""]
  resources: 
  - pods
  - deployments
  - configmaps
  - services
  verbs: 
  - get
  - list
  - watch
  - create
  - update
  - delete
```

### 创建 RoleBinding

将刚刚创建的 SA 和 Role 绑在一起。

```yaml
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: well-binding
  namespace: well
subjects:
- kind: ServiceAccount
  name: well-sa
roleRef:
  kind: Role
  name: well-role
  apiGroup: rbac.authorization.k8s.io
```

现在 well-sa 这个 ServiceAccount 就可以访问 well 命名空间下的相应资源了。接下来需要把 SA 对应的钥匙给使用者。

### 生产 kubeconfig

kubeconfig 模版如下：

```yaml
apiVersion: v1
kind: Config
users:
- name: well
  user:
    token: <token>
clusters:
- cluster:
    certificate-authority-data: <certificate-authority-data>
    server: <api-server>
  name: well-cluster
contexts:
- context:
    cluster: well-cluster
    namespace: well
    user: well
  name: well-cluster
current-context: well-cluster
```

现在只需要将上面相应的内容替换成实际的内容。

这些参数的获取路径如下：

- 通过命令 `kubectl config view --flatten --minify`  可以拿到 certificate-authority-data 和 api-server 信息 。
- 通过命令 `kubectl describe sa well-sa -n well`  拿到 secret 的 key。
- 通过命令 `kubectl describe secret <key> -n well`  拿到 token 信息。

替换完成后将kubeconfig 存成文件发放给使用者即可。

## 自动化

上述过程可以自动化完成，下面是实现这一过程的完整 Shell 脚本。

首先你需要有一个权限足够的 kubeconfig 在你的 kubectl 当前上下文。

拷贝此脚本命名文件名为 create-key.sh，给执行权限。

```bash
#!/bin/bash

echo "欢迎使用 kubeconfig 生成器，此脚本可以产生一个有限权限的密钥。"
echo "执行此脚本需要您首先拥有集群最大权限的默认钥匙。"
echo 
echo "使用方法："
echo "./create-key.sh"
echo "或者"
echo "./create-key.sh <yourname>"
echo

# 检查 ns
function userExists() {
  checkUser=`kubectl get ns | grep -w $1` 
  if [ -z "$checkUser" ]
  then
    echo 0
  else
    echo 1
  fi
}


USER=$1

if [ -z "$USER" ];then
  while true; do
    read -p "请输入用户标识：" USER

    if [ -z "$USER" ];then # 啥也不输入
      echo "您得输入点啥，或者 ctrl + c 退出，请重新输入。"
      echo
    else
      checkUser=`userExists $USER`
      if [ "$checkUser" == "0" ];
      then
        break
      else
        echo "$USER 被占用，请重新输入或者 ctrl + c 退出。"
        echo
      fi
    fi
  done
else
    checkUser=`userExists $USER`
    if [ "$checkUser" = "1" ];then
        echo "$USER 被占用。" >>/dev/stderr
        exit
    fi
fi


kubectl create ns $USER

# 创建 SA
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $USER-sa
  namespace: $USER
EOF

# 创建一个角色，并控制资源，调整这部分分配您需要的资源权限
cat <<EOF | kubectl apply -f -
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: $USER-role
  namespace: $USER
rules:
- apiGroups: [""]
  resources: 
  - pods
  - deployments
  - configmaps
  - services
  verbs: 
  - get
  - list
  - watch
  - create
  - update
  - delete
EOF

# 创建 Role Binding
cat <<EOF | kubectl apply -f -
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: $USER-binding
  namespace: $USER
subjects:
- kind: ServiceAccount
  name: $USER-sa
roleRef:
  kind: Role
  name: $USER-role
  apiGroup: rbac.authorization.k8s.io
EOF

KUBE_APISERVER=`kubectl config view --minify -o=jsonpath="{.clusters[*].cluster.server}"`
TOKEN_KEY=`kubectl get sa $USER-sa -n $USER -o=jsonpath="{.secrets[0].name}"`
TOKEN=`kubectl get secrets $TOKEN_KEY -n $USER -o=jsonpath="{.data.token}"`
CLUSTER_AUTH=`kubectl config view --flatten --minify -o=jsonpath="{.clusters[0].cluster.certificate-authority-data}"`
TOKEN_DECODE=`echo $TOKEN | base64 --decode`

# 生产 kubeconfig 文件
cat > $USER.config  <<EOF
apiVersion: v1
kind: Config
users:
- name: $USER
  user:
    token: $TOKEN_DECODE
clusters:
- cluster:
    certificate-authority-data: $CLUSTER_AUTH
    server: $KUBE_APISERVER
  name: $USER-cluster
contexts:
- context:
    cluster: $USER-cluster
    namespace: $USER
    user: $USER
  name: $USER-cluster
current-context: $USER-cluster
EOF

cat $USER.config | pbcopy

echo
echo "成功了！！！！"
echo
echo
echo "kubeconfig 文件已经保存为 ./$USER.config，并已经拷贝至您的剪切板中了。"
echo "当前 kubeconfig 仅允许访问命名空间 $USER 下的特定资源。"
echo
echo "执行如下的命令试试看："
echo "kubectl get po --kubeconfig=./$USER.config"
echo "kubectl get secret --kubeconfig=./$USER.config"
echo "kubectl get po --kubeconfig=./$USER.config -n default"
```

- 执行 ./create-key.sh 或者 ./create-key.sh well 都可以。
- 执行完成会在当前目录下保存一个 well.config 的文件，这个就是 kubeconfig 文件，发给使用这就好。或者将剪切板里的内容贴给使用者。
- 本脚本给了测试用例，其中，kubectl get po 有权限，kubectl get secret 没有权限，kubectl get po -n default 没有权限。
- 修改 Role 的部分，可以精细控制权限，也可以创建多个 Role 和 Binding，对不同的资源分权限控制。
- 需要释放资源，直接删除命名空间，方便快捷。`kubectl delete ns well`

此脚本在 Mac 下测试通过。
