---
layout: post
title:  "在 AWS 启动 Stable Diffusion"
date:   2023-10-06 21:10:49 +0800
author: 啤酒云
categories: aws, aiml
---



eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster $CLUSTER_NAME \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --role-only \
  --role-name AmazonEKS_EBS_CSI_DriverRole2

kubectl annotate serviceaccount ebs-csi-controller-sa \
    -n kube-system \
    eks.amazonaws.com/role-arn=arn:aws:iam::320236118172:role/AmazonEKS_EBS_CSI_DriverRole

helm upgrade keycloak bitnami/keycloak \
  --create-namespace \
  --namespace $KEYCLOAK_NAMESPACE \
  -f keycloak_values.yaml
