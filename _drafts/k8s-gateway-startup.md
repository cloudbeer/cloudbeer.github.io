---
layout: post
title:  "K8S Gateway 入门"
date:   1977-12-04 22:13:33 +0800
author: 啤酒云
categories: container
---

在 K8S 集群南北向流量控制中，是否可以实现丰富的逻辑控制，比如基于 Http Headers 的流量控制，是否可以集成业务权限控制？
目前使用普通的 Ingress API 无法满足这一需求，各家自行实现的 Ingress Controller 产品都将特殊的控制写在了 annotation 里了。
曾经，Service Mesh 的 Virtual Service 是一个很好的方案，但如果只想用 Gateway 而去安装一个 Istio 系统显得有点"重"了。

在本文中，我们选择 Envoy Gateway 来体验一下。

## 基本概念

### Gateway vs Ingress

| 特性 | Gateway | Ingress |
| 角色权限集成 | 有 | 没有 |
| 表现力 | 原生支持很多的逻辑，如 header, 流量分配 | 很少，仅支持普通的路由，以及在 annotation 里的注解特殊实现 |
| 可扩展 | 灵活 | 极少 |

## 安装 Envoy Gateway

---
参考：

[Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
