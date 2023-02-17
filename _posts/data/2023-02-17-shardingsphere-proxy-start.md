---
layout: post
title:  "SharingSphere-Proxy 入门"
date:   2023-02-17 11:27:44 +0800
author: 啤酒云
categories: data
tags: SharingSphere
---

云厂商提供的数据库读写分离，通常会提供多个 url/endpoint 供开发者使用，一般需要应用自己去区分读写场景进行程序改造。现在有了这种数据访问的分布式中间件，自动对 SQL 语句进行检测和路由。本文体验了一下 SharingSphere-Proxy，并记录了一下配置和验证过程。

## 配置

首先把 SharingSphere-Proxy 的配置拷贝出来，用官方文档提供的命令即可：

```shell
docker run -d --name tmp --entrypoint=bash apache/shardingsphere-proxy
docker cp tmp:/opt/shardingsphere-proxy/conf /host/path/to/conf
docker rm tmp
```

- /host/path/to/conf 修改成你自己的目录。

对于简单的读写分离，需要 2 个配置文件，内容分别如下：

server.yaml

```yaml
authority:
  users:
    - user: admin
      password: YourPassword
  privilege:
    type: ALL_PERMITTED

transaction:
  defaultType: XA
  providerType: Atomikos

sqlParser:
  sqlCommentParseEnabled: false
  sqlStatementCache:
    initialCapacity: 2000
    maximumSize: 65535
  parseTreeCache:
    initialCapacity: 128
    maximumSize: 1024

props:
  max-connections-size-per-query: 1
  sql-show: true
```

- 这里的用户配置即是 SharingSphere-Proxy 模拟的 MySQL 引擎账号

config-readwrite-splitting.yaml

```yaml
databaseName: dbname

dataSources:
  write_ds:
    url: jdbc:mysql://xxxxxxxxx.rds.cn-northwest-1.amazonaws.com.cn:3306/dbname
    username: admin
    password: thisDBPwd
    connectionTimeoutMilliseconds: 30000
    idleTimeoutMilliseconds: 60000
    maxLifetimeMilliseconds: 1800000
    maxPoolSize: 50
    minPoolSize: 1
  read_ds_0:
    url: jdbc:mysql://xxxxxxxxxt.cluster-ro-xxxx.rds.cn-northwest-1.amazonaws.com.cn:3306/dbname
    username: admin
    password: thisDBPwd
    connectionTimeoutMilliseconds: 30000
    idleTimeoutMilliseconds: 60000
    maxLifetimeMilliseconds: 1800000
    maxPoolSize: 50
    minPoolSize: 1
rules:
  - !READWRITE_SPLITTING
    dataSources:
      readwrite_ds:
        staticStrategy:
          writeDataSourceName: write_ds
          readDataSourceNames:
            - read_ds_0
        loadBalancerName: random
    loadBalancers:
      random:
        type: RANDOM

```

- dbname url 密码这些需要修改成你自己的。

上述配置的具体意思参考官方文档。

## 启动并验证

如果源数据使用 MySQL 引擎，需要下载 MySQL 的 JDBC 的驱动包到 ext-lib 中，如：

```shell
wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.47/mysql-connector-java-5.1.47.jar
```

使用 docker 命令启动：

```shell
docker run -it --rm \
    -v $PWD/conf:/opt/shardingsphere-proxy/conf \
    -v $PWD/ext-lib:/opt/shardingsphere-proxy/ext-lib \
    -e PORT=3308 -p 3306:3308 apache/shardingsphere-proxy
```

- 上述命令启动了 SharingSphere-Proxy，并把端口映射到了主机的 3306 端口。

启动之后，则可以在客户端透明访问 SharingSphere-Proxy 了。

下面使用 MySQL 的标准客户端进行测试，如下：

```shell
mysql -h 172.31.14.22 -uadmin -p
```

输入密码后，可以直达 MySQL:

```shell
ubuntu@ip-172-31-8-115:~$ mysql -h 172.31.14.22 -uadmin -p
Enter password:
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 2
Server version: 5.7.22-ShardingSphere-Proxy 5.3.1 MySQL Community Server (GPL)

Copyright (c) 2000, 2023, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql>
```

创建数据库，use 一下，创建一个表。

```SQL
CREATE TABLE student 
( 
  id int NOT NULL AUTO_INCREMENT, 
  t varchar(50) NULL, 
  PRIMARY KEY (id) 
);
```

测试一下如下的 SQL

```sql
INSERT INTO student (t) values ('1'), ('2'), ('3'), ('4'), ('5'), ('6'), ('7'), ('8');SELECT * from student;
```

期望的结果是，他能正确路由。SharingSphere-Proxy 的 log 显示如下：

```shell
...
[INFO ] 2023-02-17 03:52:50.643 [Connection-2-ThreadExecutor] ShardingSphere-SQL - Logic SQL: INSERT INTO student (t) values ('1'), ('2'), ('3'), ('4'), ('5'), ('6'), ('7'), ('8')
[INFO ] 2023-02-17 03:52:50.644 [Connection-2-ThreadExecutor] ShardingSphere-SQL - Actual SQL: write_ds ::: INSERT INTO student (t) values ('1'), ('2'), ('3'), ('4'), ('5'), ('6'), ('7'), ('8')
[INFO ] 2023-02-17 03:52:50.685 [Connection-2-ThreadExecutor] ShardingSphere-SQL - Logic SQL: SELECT * from student
[INFO ] 2023-02-17 03:52:50.685 [Connection-2-ThreadExecutor] ShardingSphere-SQL - Actual SQL: read_ds_0 ::: SELECT * from student
...
```

由于同步数据需要一些时间，所以上述测试的 SQL 把 INSERT 和 SELECT 操作写在了一句话里。
可以看到，插入成功之后，并不总是能直接拿到刚刚插入的结果，这个也证实了查询操作的确路由到了 ro 的 endpoint 上了。

写完收工！

---

参考：

<https://shardingsphere.apache.org/document/current/cn/user-manual/shardingsphere-proxy/startup/docker/>

<https://shardingsphere.apache.org/document/current/cn/user-manual/shardingsphere-proxy/yaml-config/>

<https://shardingsphere.apache.org/document/current/cn/user-manual/shardingsphere-jdbc/yaml-config/rules/readwrite-splitting/>
