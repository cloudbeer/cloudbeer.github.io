---
layout: post
title:  "如何使用 OpenClaw 写个人博客"
date:   2026-03-03 11:30:00 +0800
author: 小爆弹
categories: devops
---

> 本文就是用 OpenClaw 写的，然后由 OpenClaw 自动发布到这个博客的。

你有没有想过——**写博客最麻烦的部分，其实不是写作本身，而是发布流程**？打开编辑器、写 Markdown、本地预览、git add、git commit、git push……每次发文章都要走一遍，久而久之，"等会儿再发"就变成了"再也不发"。

OpenClaw 可以把这一切变成一句话。

---

## OpenClaw 是什么？

[OpenClaw](https://openclaw.ai) 是一个 AI 个人助手平台，可以通过飞书、Telegram、微信等渠道对话，帮你完成各种任务——包括帮你写博客并自动发布。

它能操作文件系统、执行 shell 命令、调用 GitHub API，所以完全可以胜任"写文章 → 提交代码 → 触发发布"这整条链路。

---

## 前置准备：搭好博客基础设施

在让 OpenClaw 帮你写博客之前，需要先把 GitHub Pages + Jekyll 的底座搭好。这是一次性的工作。

### 1. 创建 GitHub 仓库

仓库名必须是 `你的用户名.github.io`，GitHub Pages 会自动识别并托管。

### 2. 初始化 Jekyll

```bash
gem install jekyll bundler
jekyll new my-blog
cd my-blog
```

建议把源文件放在 `source` 分支，编译后的 HTML 推到 `main` 分支，保持仓库整洁。

### 3. 配置 GitHub Actions 自动构建

在 `source` 分支创建 `.github/workflows/deploy.yml`，让每次 push 到 source 时自动构建并发布到 main：

```yaml
name: Build and Deploy Jekyll

on:
  push:
    branches:
      - source

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '2.7'
      - name: Cache gems
        uses: actions/cache@v4
        with:
          path: vendor/bundle
          key: ${{ runner.os }}-gems-${{ hashFiles('**/Gemfile.lock') }}
      - name: Install dependencies
        run: |
          bundle config path vendor/bundle
          bundle install --jobs 4 --retry 3
      - name: Build
        run: bundle exec jekyll build
        env:
          JEKYLL_ENV: production
      - name: Deploy to main
        uses: peaceiris/actions-gh-pages@v4
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./_site
          publish_branch: main
          user_name: 你的GitHub用户名
          user_email: 你的邮箱
```

> 记得在 GitHub repo Settings → Actions → General 里开启 **Read and write permissions**。

### 4. 申请 GitHub Personal Access Token

去 GitHub Settings → Developer settings → Personal access tokens，创建一个有 `repo` 权限的 PAT，OpenClaw 需要用它来提交文章。

---

## 把仓库交给 OpenClaw

把博客仓库地址和 PAT 告诉 OpenClaw：

> "我的博客仓库是 https://github.com/你的用户名/你的用户名.github.io，PAT 是 ghp_xxxxx，帮我分析一下仓库结构。"

OpenClaw 会自动：
- Clone 仓库
- 分析目录结构和文章格式
- 了解你用的分类、Markdown 规范、Front Matter 格式

这个分析过程只需要做一次，之后 OpenClaw 就知道怎么往你的博客里写文章了。

---

## 日常写作：一句话发文章

搭好之后，写博客就变成了这样：

**你：** "帮我写一篇文章，讲如何用 Amazon Bedrock Knowledge Base 构建聊天界面。"

**OpenClaw：** （分析选题、起草文章、等你确认）

**你：** "很棒，发布吧。"

**OpenClaw：** （创建 Markdown 文件 → git commit → git push → GitHub Actions 自动触发构建 → 几分钟后上线）

整个过程，你只需要做两件事：**告诉它写什么**，以及**确认内容**。

---

## OpenClaw 能帮你做什么？

在博客写作这个场景里，OpenClaw 不只是"帮你打字"：

**内容生成：**
- 根据你提供的主题，自主研究、组织结构、起草全文
- 参考你已有的文章风格，保持一致的写作语气
- 自动生成 Jekyll 需要的 Front Matter（标题、日期、分类等）

**发布流程：**
- 自动 push 到正确的 source 分支
- 触发 GitHub Actions 构建
- 验证发布结果（访问 URL 确认上线）

**仓库维护：**
- 迁移 CI 工具（比如把 CircleCI 换成 GitHub Actions）
- 删除废弃配置
- 修复构建错误

---

## 效果怎么样？

本文就是实际案例。今天（2026-03-03），我用一句话告诉 OpenClaw 写什么，它完成了：

1. 分析博客仓库结构（source/main 双分支、Jekyll 配置、文章格式）
2. 发现 CI 还是 CircleCI，顺手帮我迁移到了 GitHub Actions
3. 今天连续发布了 3 篇文章
4. 全程我没有打开过代码编辑器

这才是 AI 助手应该有的样子——不是帮你"稍微快一点"，而是**把整个流程自动化**。

---

## 小结

| 环节 | 传统方式 | 用 OpenClaw |
|------|---------|------------|
| 写文章 | 自己写 Markdown | 告诉它主题，它来写 |
| 发布 | git add/commit/push | 一句"发布吧" |
| 修复 CI 报错 | 自己查日志、改配置 | 它自动诊断修复 |
| 基础设施维护 | 手动操作 | 描述需求，它来做 |

博客最大的敌人是**惰性**。OpenClaw 把摩擦力降到接近零，让写博客这件事真正变得轻松。

---

> 本文作者：小爆弹 💥 | 由 OpenClaw 撰写并发布，这不是广告，这是事实。
