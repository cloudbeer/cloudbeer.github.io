---
layout: post
title:  "Github pages jekyll 插件不支持怎么办"
date:   2022-12-04 22:13:33 +0800
categories: devops, tucao, circleci
---

花了一下午的时间，将博客的分页，分类功能加上了。结果发现 github pages 不支持，还不能自己安装 jekyll 的插件。然后头大了。 

这片文章记录了如何解决这个麻烦。

## github pages 插件别瞎用

当你觉得你完美解决了写博客的问题的时候，就发现问题了。

下午找到一个不错的分页插件：jekyll-paginate-v2， 搞定了 分页，tags 功能，本地渲染出来很不错，甚合我意。

推送之后，发现了蛋疼的事情：所有的列表页面都是空的。

Actions 也都正常，调查半天才发现，github pages 不支持 jekyll-paginate-v2。

这是他支持的：<https://pages.github.com/versions/>

## circleci 集成

那只能用第三方 CI 工具了。用 gitlab ci 肯定是可以的。

现在试试 circleci。 下面记录了过程：

### step 1. 创建新分支

创建 cloudbeer.github.io 新分支：soruce。

### step 2. 添加 circleci config 文件
 
在新分支里添加文件：`.circleci/config.yml`，内容如下：

```yaml
{% raw %}
version: 2
jobs:
  deploy:
    docker:
      - image: circleci/ruby:latest
        environment:
          USER_NAME: cloudbeer
          USER_EMAIL: cloudbeer@gmail.com
    steps:
      - checkout
      - run:
          name: install dependencies
          command: |
            gem update --system
            gem install bundler
      - restore_cache:
          keys: 
            - v1-gem-cache-{{ arch }}-{{ .Branch }}-{{ checksum "Gemfile.lock" }}
            - v1-gem-cache-{{ arch }}-{{ .Branch }}-
            - v1-gem-cache-{{ arch }}- 
      - run: bundle install --path=vendor/bundle && bundle clean
      - save_cache:
          paths:
            - vendor/bundle
          key: v1-gem-cache-{{ arch }}-{{ .Branch }}-{{ checksum "Gemfile.lock" }}

      - run: JEKYLL_ENV=production bundle exec jekyll build
      - deploy:
          name: Deploy Release to GitHub
          command: |
            if [ $CIRCLE_BRANCH == 'source' ]; then
              bash .circleci/deploy.sh
            fi
workflows:
  version: 2
  build:
    jobs:
      - deploy:
          filters:
            branches:
              only: 
                - source
{% endraw %}
```

代码的意思大概是：

- 使用 ruby 镜像，安装依赖，build
- 然后调用 deploy 脚本

### step 3. doploy 脚本

添加脚本 `.circleci/deploy.sh`，内容如下：

```bash
git config user.name "$USER_NAME"
git config user.email "$USER_EMAIL"

git checkout main
git pull origin main

find . -maxdepth 1 ! -name '_site' ! -name '.git' ! -name '.gitignore' ! -name '.circleci' -exec rm -rf {} \;
mv _site/* .
rm -R _site/

git add -fA
git commit --allow-empty -m "$(git log source -1 --pretty=%B)"

git remote set-url origin https://cloudbeer:${GITHUB_PWD}@github.com/cloudbeer/cloudbeer.github.io.git

git push -f origin main

echo "deployed successfully"
```

代码的大概意思是：

- 把分支切到 main，把编译目标 _site 目录里面的文件拷贝到根目录。
- 把代码推回去。
- github pages 里设置的是 main 分支的 / 目录，此时 main 下面都是纯 html 页面。
- 稍等一会儿 github pages 发布完成就可以看到结果了。

上面的代码有个地方需要改进，就是这行：

```shell
git remote set-url origin https://cloudbeer:${GITHUB_PWD}@github.com/cloudbeer/cloudbeer.github.io.git
```

推送的时候发现没有权限，先用这个土办法了。这里的 [GITHUB_PWD 需要去生产](https://github.com/settings/tokens)，我把申请到的结果存入了 circleci 的环境变量里。

还需要改进的有：

github 在发现有新的 push 之后 还是在运行 jekyll build，在此种情况下，应该直接部署就好。后面再看看咋搞。


## github pages 随便搞

了解了 github pages 的规则，就可以用任意支持 markdown 的框架来做你的博客了，前提是他静态页面生产器。

发现 circleci 在第二次 build 的时候很快啊，比 gitlab 快很多。可能是一个默认缓存，一个没默认缓存的缘故吧。

--- 

本文代码修改自这个文章：[How to Deploy to Github Pages Using CircleCI 2.0 + Custom Jekyll Dependencies
](https://jasonthai.me/blog/2019/07/22/how-to-deploy-a-github-page-using-circleci-20-custom-jekyll-gems/)