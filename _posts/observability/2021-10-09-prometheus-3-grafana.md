---
layout: post
title:  Prometheus 入门 ③ 使用 Grafana 美化
date:   2021-10-09 18:08:34 +0800
author: 啤酒云
categories: observability, prometheus, granfana
---
​
Prometheus 本身带了一个简单的 UI，用于查询指标，并能显示简单的 chart。而 Grafana 是 Prometheus 好伴侣，能画出好看的图表。

## Grafana 一瞥

### 启动 grafana

```shell
docker run --rm -p 3000:3000 grafana/grafana-enterprise
```

启动 <http://localhost:3000/>，输入用户名和密码：admin/admin

第一次登入之后，需要修改密码。

### 增加一个仪表盘

点击 ➕ 图标，增加一个 Dashboard，然后点击 “Add an empty panel” 增加一个空面板。

选择数据源为 Grafana，这个会显示一个随机的模拟图，点击 Save 后，取个名字 “模拟面板”，保存后，就完成了一个仪表盘。

## Prometheus + Grafana

### 启动 Prometheus

首先检查本地的 Prometheus 和 exporter 是否已经启动，本示例将按照上一章的 《Prometheus (二) 自定义数据源》的价格波动来适配 Grafana。

### 配置数据源

点击 ⚙ 图标进入 Configuration，选择 DataSources，点击 “Add data source”，选择 Prometheus，配置界面如下：

![配置数据源](/assets/posts/observability/data-source.png)
​
配置完成后，点击 “Save & test”。

### Explore 数据

点击 Explore 图标，展示 Explore 界面，更换数据源为 “价格波动”。

在 Metrics browser 选择 price{}，点击按钮 “Use query” 之后，就可以看到曲线了：

![explore 数据](/assets/posts/observability/data-explore.png)

### 配置显示面板

先进入之前的仪表盘“模拟面板”，点击顶部菜单 “Add panel”，然后，进行各种配置。

在图表的下方配置：Data source 选择刚刚配置的“价格波动”，其他部分与 Explore 的类似。

在右侧配置显示样式等。

一顿操作后：​

![价格面板](/assets/posts/observability/data-panel.png)

​

还挺好玩的！

​
