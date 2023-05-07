---
layout: post
title:  "Jenkins 使用外部 EKS(1.24) 作为 Agent 的配置细节"
date:  2023-03-06 21:10:49 +0800
author: 啤酒云
categories: aws, devops
---

主 Jenkins 安装在某个引擎上，现在要使用外部 EKS 1.24 作为 agent，后续的构建任务都调度到 EKS。

## Jenkins 权限配置

## Jenkins Kubernetes 配置

certificate 可以去看 EKS 控制台。

Jenkins 配置 Secret Text。

Jenkins Server 的安全组需要打开 50000 端口。

参考文档：<https://devopscube.com/jenkins-build-agents-kubernetes/>

来搞一段 kubeconfig 生成器。与 [之前的文档](/2021/07/create-kubeconfig.html) 不同，1.24+ 不会给 sa 生产默认的 secret 了。

```shell
#!/bin/bash

echo "欢迎使用 kubeconfig 生成器，此脚本可以产生一个集群管理员的密钥。"
echo "执行此脚本需要您首先拥有集群最大权限的默认钥匙。"
echo 
echo

USER=$1

function userExists() {
  checkUser=`kubectl get sa -ndefault| grep -w $1-sa` 
  if [ -z "$checkUser" ]
  then
    echo 0
  else
    echo 1
  fi
}

if [ -z "$USER" ];then
  while true; do
    read -p "请输入服务账号标识：" USER

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
fi

# 创建 ServiceAccount
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $USER-sa
  namespace: default
EOF

# 注意这里是新的：创建一个 Secret  1.24+ 加上这个 
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
metadata:
  name: $USER-sa-token
  namespace: default
  annotations:
    kubernetes.io/service-account.name: $USER-sa
EOF

# 使用 sa 创建 ClusterRoleBinding
cat <<EOF | kubectl apply -f -
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: $USER-sa-admin-clusterrolebinding
subjects:
- kind: ServiceAccount
  name: $USER-sa
  namespace: default
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF



KUBE_APISERVER=`kubectl config view --minify -o=jsonpath="{.clusters[*].cluster.server}"`
# 这里是新的
TOKEN=`kubectl get secrets $USER-sa-token -n default -o=jsonpath="{.data.token}"`
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
    namespace: default
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
echo
echo "执行如下的命令试试看："
echo "kubectl --kubeconfig=./$USER.config get po  -A"
echo "kubectl --kubeconfig=./$USER.config get node  -A"
echo
echo
echo "清理资源执行:"
echo "kubectl delete clusterrolebinding $USER-sa-admin-clusterrolebinding"
# 这里是新的
echo "kubectl delete secrets $USER-sa-token -n default"
echo "kubectl delete sa $USER-sa -n default"

```

这些地方有改动

- 61 行
- 92 行
- 134 行
