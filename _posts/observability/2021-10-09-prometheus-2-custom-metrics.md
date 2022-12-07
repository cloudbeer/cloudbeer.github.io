---
layout: post
title:  Prometheus 入门 ② 自定义数据源
date:   2021-10-09 20:08:34 +0800
author: 啤酒云
categories: observability 
tags: prometheus, 监控, tencent
---

​本文将介绍如何使用第三方的 exporter，并尝试自己编写一个业务度量接口。

## 现成的 exporter

prom 官方提供了很多数据源 exporter。包括：

- blackbox_exporter
- consul_exporter
- graphite_exporter
- haproxy_exporter
- memcached_exporter
- mysqld_exporter
- node_exporter
- statsd_exporter

前面的章节里，我们已经使用过官方的 node_exporter。

我们现在尝试使用第三方的 exporter。

下面的示例演示了使用 腾讯云的 exporter。

腾讯云的 exporter 地址在：<https://github.com/tencentyun/tencentcloud-exporter>

首先，需要拉下上述源代码并编译成可执行文件：

```shell
git clone https://github.com/tencentyun/tencentcloud-exporter
cd tencentcloud-exporter
go build cmd/qcloud-exporter/qcloud_exporter.go
```

编译完成，生成了一个文件：`qcloud_exporter`

现在需要编写一个 config 文件（config.yml）：

```yaml
credential:
  region: "ap-shanghai"
rate_limit: 15
products:
  - namespace: QCE/CVM
    all_metrics: true
    all_instances: true
    extra_labels: [InstanceId, InstanceName]
```

我将 access_key 和 secret_key 放入了环境变量，所以上述配置文件中无需配置这两个参数：

```shell
export TENCENTCLOUD_SECRET_ID="YOUR_ACCESS_KEY"
export TENCENTCLOUD_SECRET_KEY="YOUR_ACCESS_SECRET"
```

现在只需要启动 exporter 即可：

```shell
./qcloud_exporter --config.file=./config.yml
```

启动完成后，可以在浏览器中看到 metrics 信息，地址是：<http://0.0.0.0:9123/metrics>

腾讯云的 exporter 使用的是 云 API 实现，如果在本地运行 exporter，会有明显的延时，实际使用中，建议部署在云上的同 region。

现在，将这个 exporter 配置到 prom 中，只需要在 config 文件的 `scrape_configs` 下新增一个 job 配置（prometheus.yml）。

```yaml
global:
  scrape_interval: 15s
  external_labels:
    monitor: 'cvm-monitor'
scrape_configs:
  - job_name: 'qcloud_cvm'
    scrape_timeout: 20s
    scrape_interval: 30s
    static_configs:
      - targets:
        - host.docker.internal:9123
```

然后，启动 prom：

```shell
docker run --rm -p 9090:9090 \
    -v $(pwd)/prometheus.yml:/etc/prometheus/prometheus.yml \
    prom/prometheus
```

启动后查询“外网网卡每秒出流量” `qce_cvm_wanouttraffic_max` 试试。

## 编写自定义业务监控指标

我们通过观察 metrics 的数据格式，可以看出他的格式是：名称{键="值",键="值"...} 数值，如：

```shell
# TYPE qce_cvm_wanouttraffic_max gauge
qce_cvm_wanouttraffic_max{instance_id="ins-ireqmbad",instance_name="tke_cls-k383r70d_worker1"} 0.0.1
```

现在我们模拟编写两个业务指标试试。

下面使用了 php 代码模拟了 2 个商品的价格波动，采用了随机数进行演示。

```shell
$router->get('/metrics', function () use ($router) {
    $v = '# TYPE price gauge';
    $v .= "\n";
    $v .= 'price{product="蓝色潜水艇"} '.rand(100,10000)/100;
    $v .= "\n";
    $v .= 'price{product="果壳中的宇宙"} '.rand(200,20000)/100;
    $v .= "\n";
    return (new Response($v, 200))
                  ->header('Content-Type', 'text/plain; version=0.0.4');
});
```

请注意，这里需要按照规范来写，包括头部的注释 `# TYPE price gauge`，规范请看这里：<https://prometheus.io/docs/instrumenting/exposition_formats/>

输出结果大概为：

```shell
# TYPE price gauge
price{product="蓝色潜水艇"} 59.71
price{product="果壳中的宇宙"} 121.69
```

假设我们把这个接口发布到地址：<http://localhost:8004/metrics>。

现在我们把他配置到 prom 中。

编写 config 文件（prometheus2.yml）:

```yaml
global:
  scrape_interval: 15s
  external_labels:
    monitor: 'prom-monitor'
scrape_configs:
  - job_name: 'book-price'
    scrape_timeout: 5s
    scrape_interval: 10s
    static_configs:
      - targets:
        - host.docker.internal:8004
```

用这个配置文件启动 prom：

```shell
docker run --rm -p 9090:9090 \
    -v $(pwd)/prometheus2.yml:/etc/prometheus/prometheus.yml \
    prom/prometheus
```

​
在 prom 的UI 查询 price，会得到类似下面的折线图：

![自定义业务指标监控](/assets/posts/observability/custom-metrics.png)

​

现在，我们可以对业务指标进行监控了。

​
