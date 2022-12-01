---
layout: post
title:  "Apache Airflow 入门"
date:   2022-11-01 20:12:44 +0800
categories: devops
---

从小白到略知一二。

## 背景

都说 Airflow 很强大，用 python 语言写 DAG。

对于我，语言不重要，了解他的运行架构和设计思想更重要。

先安装一个单机版本试试。

## 安装

在 Mac M1 上默认安装各种编译错误，然后使用 **conda** 重新安装了 python，终于搞定。

安装过程复制自官方：

```shell
AIRFLOW_VERSION=2.4.3
PYTHON_VERSION="$(python --version | cut -d " " -f 2 | cut -d "." -f 1-2)"
CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt"
pip install "apache-airflow==${AIRFLOW_VERSION}" --constraint "${CONSTRAINT_URL}"
```

启动一个开发版本试试：

```shell
airflow standalone
```

成功启动后，控制台打印了一些有用信息。本机 Web 端默认为： `http://localhost:8080`。

登录账号也在控制台中打印。

```shell
standalone |
standalone | Airflow is ready
standalone | Login with username: admin  password: xxxxxxxxxx
standalone | Airflow Standalone is for development purposes only. Do not use this in production!
standalone |
```

进入之后，有很多现成的 DAG，一头雾水。

或者**走下面这个步骤，都差不多。**

初始化数据库：

```shell
airflow db init
```

这个过程中，有个警告，是说要安装 kubernetes 的 excutor。顺手给他装一下：

```shell
pip install apache-airflow-providers-cncf-kubernetes
```

创建一个新账号

```shell
airflow users create \
    --username xie \
    --firstname Cloudbeer \
    --lastname Xie \
    --role Admin \
    --email cloudbeer@gmail.com
```

换个端口启动 Web Server

```shell
airflow webserver --port 9000
```

换个 终端窗口启动 Scheduler：

```shell
airflow scheduler
```

## 编写第一个 DAG

Airflow 的 hello world 代码如下：

```python

from datetime import datetime, timedelta
from textwrap import dedent
from airflow import DAG

from airflow.operators.bash import BashOperator
with DAG(
    'hellodag',
    default_args={
        'depends_on_past': False,
        'email': ['cloudbeer@gmail.com'],
        'email_on_failure': False,
        'email_on_retry': False,
        'retries': 1,
        'retry_delay': timedelta(minutes=5),
    },
    description='这是一个简单的 DAG',
    schedule=timedelta(days=1),
    start_date=datetime(2022, 12, 1),
    catchup=False,
    tags=['example'],
) as dag:
    t1 = BashOperator(
        task_id='print_date',
        bash_command='date',
    )

    t2 = BashOperator(
        task_id='sleep',
        depends_on_past=False,
        bash_command='sleep 5',
        retries=3,
    )
    t1.doc_md = dedent(
        """\
    #### Task Documentation
    You can document your task using the attributes `doc_md` (markdown),
    `doc` (plain text), `doc_rst`, `doc_json`, `doc_yaml` which gets
    rendered in the UI's Task Instance Details page.
    ![img](http://montcs.bloomu.edu/~bobmon/Semesters/2012-01/491/import%20soul.png)
    **Image Credit:** Randall Munroe, [XKCD](https://xkcd.com/license.html)
    """
    )

    dag.doc_md = """
    这是一个简单的 DAG。
    """ 

    templated_command = dedent(
        """
    {% for i in range(5) %}
        echo "{{ ds }}"
        echo "{{ macros.ds_add(ds, 7)}}"
    {% endfor %}
    """
    )

    t3 = BashOperator(
        task_id='templated',
        depends_on_past=False,
        bash_command=templated_command,
    )

    t1 >> [t2, t3]
```

- 上面的代码修改 DAG 的名字为 hellodag
- 文件名命名为 hellodag.py

将这个文件放到 ~/airflow/dags 目录下。

使用 python 验证一下：

```shell
python hellodag.py
```

没有错误。

## Airflow 任务测试

dag 文件放到了对应的目录了，现在查看一下 dags。（又要开一个终端）

```shell
airflow dags list
```

- hellodag 已经出现在列表了。

```shell
airflow tasks list hellodag --tree
```

- 这个命令可以看到这个 dag 包含了三个任务 `print_date`, `sleep`, `templated`
- --tree 显示了依赖关系。

```shell
<Task(BashOperator): print_date>
    <Task(BashOperator): sleep>
    <Task(BashOperator): templated>
```

测试一下任务：

```shell
airflow tasks test hellodag print_date 2015-06-01

airflow tasks test hellodag sleep 2015-06-01

airflow tasks test hellodag templated 2015-06-01
```

运行 backfill (回填)

```shell
airflow dags backfill hellodag \
    --start-date 2015-06-01 \
    --end-date 2015-06-07
```

好了。入了个门。我去研究 Airflow in K8S 了。
