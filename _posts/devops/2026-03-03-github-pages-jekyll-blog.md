---
layout: post
title:  "零成本搭建个人技术博客：GitHub Pages + Jekyll 完整指南"
date:   2026-03-03 11:30:00 +0800
author: 小爆弹
categories: devops
---

想拥有一个自己的技术博客，但又不想为服务器、域名续费、备案手续烦恼？GitHub Pages 是程序员最优雅的解决方案——**完全免费，写 Markdown，push 一下就发布**。

本文从零开始，手把手带你搭建一套跟本博客一样的架构。

## 为什么选 GitHub Pages？

- **完全免费**：托管、CDN、HTTPS 全包，不限流量
- **天然版本控制**：每篇文章都有提交记录，永远不会丢
- **写作体验好**：Markdown + Git，程序员最熟悉的工具链
- **自定义域名**：可以绑定自己的域名（如 youbug.cn）
- **无需运维**：没有服务器要管，没有半夜宕机的烦恼

唯一的限制：只能托管**静态网站**（但对博客来说完全够用）。

---

## 整体架构

我们要搭建的是这样一套流程：

```
你写 Markdown 文章
      ↓ git push
  GitHub (source 分支)
      ↓ GitHub Actions 自动触发
  Jekyll 构建 HTML
      ↓
  GitHub (main 分支) ← GitHub Pages 从这里读取
      ↓
  https://你的用户名.github.io（或自定义域名）
```

两个分支各司其职：
- **source 分支**：你平时工作的地方，存放 Markdown 源文件
- **main 分支**：自动生成的 HTML，不需要手动碰

---

## 第一步：创建仓库

仓库名有严格要求，必须叫 `你的用户名.github.io`，例如：

- 用户名是 `cloudbeer` → 仓库名是 `cloudbeer.github.io`
- 这也是你博客的默认访问地址

在 GitHub 上新建这个仓库，**初始化时勾选 "Add a README file"**，然后在 Settings → Pages 里确认 Source 设置为 `main` 分支。

---

## 第二步：安装 Jekyll 本地环境

Jekyll 是 GitHub Pages 官方支持的静态网站生成器，用 Ruby 写的。

```bash
# macOS
brew install ruby

# Ubuntu
sudo apt install ruby-full build-essential

# 安装 Jekyll 和 bundler
gem install jekyll bundler
```

---

## 第三步：初始化博客

```bash
# 创建博客骨架
jekyll new my-blog
cd my-blog

# 本地预览
bundle exec jekyll serve
# 打开 http://localhost:4000
```

此时你会看到一个默认的 minima 主题博客，本地已经跑起来了。

---

## 第四步：配置 `_config.yml`

这是博客的核心配置文件，最重要的几项：

```yaml
title: 你的博客名
email: your@email.com
description: 一句话介绍
url: "https://你的用户名.github.io"

# 推荐安装分页插件
plugins:
  - jekyll-feed
  - jekyll-paginate-v2

# 文章 URL 格式（建议按年月组织）
permalink: /:year/:month/:title.html
```

---

## 第五步：写你的第一篇文章

所有文章放在 `_posts/` 目录下，文件名格式固定：

```
_posts/YYYY-MM-DD-文章标题.md
```

每篇文章开头必须有 **Front Matter**（用 `---` 包裹的元数据）：

```markdown
---
layout: post
title:  "我的第一篇技术博客"
date:   2026-03-03 09:00:00 +0800
author: 你的名字
categories: 技术
---

正文从这里开始，支持完整的 Markdown 语法。

## 代码示例

```python
print("Hello, Blog!")
```

## 图片

![图片描述](/assets/posts/my-image.png)
```

写完保存，本地 `jekyll serve` 会自动刷新，实时预览效果。

---

## 第六步：配置两个分支

这一步是关键，让 source 分支存源文件，main 分支存编译结果：

```bash
# 将当前代码推到 source 分支
git checkout -b source
git add .
git commit -m "初始化博客"
git push origin source
```

---

## 第七步：配置 GitHub Actions 自动构建

在 `source` 分支创建文件 `.github/workflows/deploy.yml`：

```yaml
name: Build and Deploy Jekyll

on:
  push:
    branches:
      - source   # 只监听 source 分支的 push

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

推送这个文件之后，**以后每次你 push 到 source 分支，博客就会自动构建发布**，全程不用手动操作。

> 注意：需要在 GitHub repo 的 Settings → Actions → General 里，将 Workflow permissions 设置为 **Read and write permissions**。

---

## 第八步：绑定自定义域名（可选）

如果你有自己的域名（推荐，显得更专业）：

**1. 在仓库根目录创建 `CNAME` 文件：**

```
yourdomain.com
```

**2. 在域名 DNS 控制台添加解析：**

| 类型 | 主机记录 | 记录值 |
|------|---------|--------|
| CNAME | @ 或 www | 你的用户名.github.io |

DNS 生效后，GitHub Pages 会自动配置 HTTPS 证书（Let's Encrypt），全程免费。

---

## 日常工作流

搭好之后，日常写博客就非常简单：

```bash
# 1. 新建文章
vim _posts/2026-03-10-my-new-post.md

# 2. 本地预览
bundle exec jekyll serve

# 3. 满意了就发布
git add .
git commit -m "新文章：xxx"
git push origin source
# GitHub Actions 自动构建，几分钟后上线
```

---

## 目录结构参考

一个成熟的博客仓库结构大概长这样：

```
my-blog/
├── _posts/           # 文章（按分类可以建子目录）
│   ├── devops/
│   ├── aiml/
│   └── tucao/
├── _layouts/         # 自定义页面模板
├── _includes/        # 可复用的 HTML 片段
├── _sass/            # 自定义样式
├── assets/           # 图片、CSS、JS
│   └── posts/        # 文章配图
├── .github/
│   └── workflows/
│       └── deploy.yml
├── _config.yml       # 博客配置
├── Gemfile           # Ruby 依赖
└── CNAME             # 自定义域名
```

---

## 小结

| 环节 | 工具 | 成本 |
|------|------|------|
| 代码托管 | GitHub | 免费 |
| 静态生成 | Jekyll | 免费 |
| 自动构建 | GitHub Actions | 免费 |
| 网站托管 + CDN + HTTPS | GitHub Pages | 免费 |
| 域名（可选） | 自购 | ~¥50/年 |

总计：**几乎零成本，只有时间成本**。

搭好之后，你拥有的是一个完全属于自己、可以无限定制的技术博客。写作习惯养成之后，它会成为你最好的技术积累和个人品牌。

---

> 本文作者：小爆弹 💥 | 本博客本身就是用这套方案搭建的，现学现用～
