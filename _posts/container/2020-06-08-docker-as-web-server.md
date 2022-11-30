---
layout: post
title:  "使用 docker 作为 Web 开发服务器"
date:   2021-06-08 00:10:49 +0800
categories: container
---

提供一种思路，临时启动一个 nginx 容器作为服务器来开发前端应用，nginx 作为静态页面发布器，并可以代理远端 API。同时，我们也可以在 shell 中操作打开浏览器，并监控文件的改变并刷新浏览器。php，python 等脚本类的 web 开发也可以使用这个方法，只需要更换相应的 server 镜像作为容器运行的基础环境。

## 前提条件

- 安装了 docker：安装方法略。
- nginx 镜像： `docker pull nginx:alpine` 。
- 这个例子使用了 python 作为脚本语言。

以下脚本我在 mac 中运行通过。

## nginx 配置

首先配置 nginx，这个脚本会从容器中启动，启动后，容器的 /app 是主目录，并反向代理了 2 组 api。

如果远端服务器是本机，需要从容器内部访问宿主机资源，localhost 是不好使的，请使用域名：`host.docker.internal`

nginx 的配置如下：

```nginx
server { 
  listen       8500;
  index   index.html;
  location / {
    index   index.html;
    root    /app;
    expires 1s;
  }
  location ^~/api/crm/ {
    proxy_http_version 1.1;
    proxy_pass      http://host.docker.internal:7304/;
  }
  location ^~/api/qq/ {
    proxy_http_version 1.1;
    proxy_pass      http://www.qq.com/api/;
  }
}
```

## docker

docker 启动脚本如下：

```shell
docker run --rm -it -v <publishPath>:/app -v <nginxConfPath>:/etc/nginx/conf.d/server.conf -p 8500:8500 nginx:alpine
```

直接运行这个脚本，打开 <http://localhost:8500>，我们的简易开发服务环境就搭建起来了。每次修改文件的时候，刷新浏览器就可以看到改变。

但，如果能自动刷新浏览器就圆满了。下面咱们试着来解决此问题。

## 开发过程中的自动刷新

我想直接通过外部脚本监控文件的改变。并自动刷新浏览器。

docker 脚本也放在里面一起执行算了。

完成这次任务使用了 python，完整的脚本是这么写的：

```python
#!/usr/bin/env python3
#coding=utf-8

import os 
import subprocess
import webbrowser
import _thread
import time
from selenium import webdriver
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# 启动浏览器，并访问目标地址
driver = webdriver.Chrome()
driver.get('http://localhost:8500')

# 当前工作目录
cwd = os.getcwd()
# 我当前的发布目录
publishPath = cwd + "/publish"


def dockerServer():
  """ 此函数启动 docker """
  dockerCmd = ['docker', 'run', '--rm', '-it', 
                '-v', publishPath +":/app",
                '-v', cwd+"/server.conf:/etc/nginx/conf.d/server.conf",
                '-p', "8500:8500", 'nginx:alpine']
  print("开始执行 nginx in docker...")
  process = subprocess.run(" ".join(dockerCmd), shell=True, check=True)



def refreshBrowser(delay=1):
  """ 延时 1 秒刷新浏览器，当有大量文件被更新时候，可以丢弃无效刷新动作 """
  print(delay, "秒后刷新浏览器...")
  time.sleep(delay)
  driver.refresh()

class RefreshBrowserHandler(FileSystemEventHandler):
  """ watchdog 的监控事件 """
  def on_modified(self, event):
    refreshBrowser()  # 这里需改进，应该将任务放到线程池里，以便丢弃持续刷新操作。

def watchPublish(path):
  """ watchdog 监控发布目录，一旦发现文件改变，便出发刷新事件 """
  print("正在监控目录改变:", path)
  event_handler = RefreshBrowserHandler()
  observer = Observer()
  observer.schedule(event_handler, path, recursive=True)
  observer.start()
  try:
    while True:
      time.sleep(1)
  except KeyboardInterrupt:
    observer.stop()
  observer.join()


# 启动
_thread.start_new_thread(dockerServer, ())
_thread.start_new_thread(refreshBrowser, (1,))
watchPublish(publishPath)
```

上面的脚本需要如下的依赖：

- python 自带的 webbrowser 无法控制刷新浏览器，所以采用了 selenium 包: `pip install selenium` 。
- 我使用了 chome，但提示无法找到 chromedriver，下载一个安装好了，从这里下载：[http://npm.taobao.org/mirrors/chromedriver](http://npm.taobao.org/mirrors/chromedriver)，找到和你当前浏览器版本匹配的安装包。
- 另外需要安装的包 是 watchdog，也 pip 安装一下。

## 总结

docker 的 images 平时就在那里安静的躺着，等我们需要开发的时候，启动他，开发完用 ctrl+c 关闭他，由于使用了 `--rm`，docker 的实例也跟着清除了，很清爽。

推而广之，这种方法对于所有脚本类的 Web 开发都有效，我们无需安装任何环境，只需要临时启动一个 docker 容器就好，处女座程序员可以试试这种方法。

---

参考：

[How to run an function when anything changes in a dir with Python Watchdog?](https://stackoverflow.com/questions/32923451/how-to-run-an-function-when-anything-changes-in-a-dir-with-python-watchdog)

[Selenium with Python](https://selenium-python.readthedocs.io/)
