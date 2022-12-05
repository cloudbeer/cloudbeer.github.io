---
layout: post
title:  Prometheus 入门 ① Hello World
date:   2021-10-09 21:08:14 +0800
author: 啤酒云
categories: observability, prometheus
---

此入门文档是依据官网文档参考而来。没有理论，没有架构，直接实战。现在开始。

## 小试牛刀

创建一个目录，写一个配置 (config/prom.yaml)：

```yaml
global:
  scrape_interval: 15s 
  external_labels:
    monitor: 'codelab-monitor'
scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9090']
```

然后启动普罗米修斯：

```bash
docker run --rm \
    -p 9090:9090 \
    -v $(pwd)/config/prom.yaml:/etc/prometheus/prometheus.yml \
    prom/prometheus
```

搞定！现在检验一下：

在浏览器里看看这俩 url：

数据：[http://localhost:9090/metrics](http://localhost:9090/metrics)

UI：[http://localhost:9090/graph](http://localhost:9090/graph)

在 metrics 这个地址里，第一个指标是 `go_gc_duration_seconds`

我们把在 UI 里查询一下这个指标，可以显示如下的图表。

![Prom UI](/assets/posts/observability/prom01.png)

​

万里长征开始迈出了第一步了。

## 增加 exporter

这里直接使用官方的 node exporter 来输出指标。

分别启动 3 个 node exporter：

```shell
docker run --rm -d -p 9100:9100 prom/node-exporter
docker run --rm -d -p 9101:9100 prom/node-exporter
docker run --rm -d -p 9102:9100 prom/node-exporter
```

这些 exporter 暴露了metrics 信息，可以访问试试：[http://localhost:9100/metrics](http://localhost:9100/metrics)

编写 config 配置(config/nodes.yaml)：

```yaml
global:
  scrape_interval: 15s
  external_labels:
    monitor: 'nodes-monitor'
scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'nodes'
    scrape_interval: 5s
    static_configs:
      - targets:
        - host.docker.internal:9100
        - host.docker.internal:9101
        labels:
          group: 'prod'
      - targets:
        - host.docker.internal:9102
        labels:
          group: 'dev'
```

- host.docker.internal 这个是宿主机的地址。这里是从容器内访问，所以使用了这个域名。

启动普罗米修斯：

```shell
docker run --rm \
    -p 9090:9090 \
    -v $(pwd)/config/nodes.yaml:/etc/prometheus/prometheus.yml \
    prom/prometheus
```

现在 普罗米修斯的 UI 中查询 `node_cpu_seconds_total` 试试。

## 聚合指标

现在加入一个聚合规则（config/nodes-rule.yaml）：

```yaml
groups:
- name: cpu-node
  rules:
  - record: job_instance_mode:node_cpu_seconds:avg_rate5m
    expr: avg by (job, instance, mode) (rate(node_cpu_seconds_total[5m]))
```

- 定义了一个记录，名字是 `job_instance_mode:node_cpu_seconds:avg_rate5m`
- prom 表达式是：`avg by (job, instance, mode) (rate(node_cpu_seconds_total[5m]))`

重新写一个启动配置，加入这个聚合规则（config/prometheus.yml）：

```yaml
global:
  scrape_interval: 15s
  external_labels:
    monitor: 'nodes-monitor'
rule_files:
  - 'nodes-rule.yaml'
scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'nodes'
    scrape_interval: 5s
    static_configs:
      - targets:
        - host.docker.internal:9100
        - host.docker.internal:9101
        labels:
          group: 'prod'
      - targets:
        - host.docker.internal:9102
        labels:
          group: 'dev'
```

启动普罗米修斯：

```shell
docker run --rm \
    -p 9090:9090 \
    -v $(pwd)/config:/etc/prometheus \
    prom/prometheus
```

启动后，在 UI 里查一下 `job_instance_mode:node_cpu_seconds:avg_rate5m`

现在，咱们的监控之路迈出了第一步！

​
