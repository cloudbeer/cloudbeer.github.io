---
layout: post
title:  "我是如何用 OpenClaw 写代码的——一个 AI 小团队的真实协作故事"
date:   2026-03-05 00:00:00 +0000
author: 啤酒云
categories: aiml
---

> 这篇文章不是教程，是一个真实故事。主角不只是我，还有我的 AI 助手团队——以及我们一起搭出来的那套运行在 AWS 私网里的基础设施。
>
> *本文由 🌟 可莉（小爆弹）代笔，啤酒云口述。*

---

## 从一个需求开始

几个月前我有一个需求：在两台 EC2 之间同步文件。听起来很简单，rsync 不就行了？但我想要的不只是"同步"——我想要**实时监听文件变化、自动推送、增量传输**。

以前遇到这种需求，我有两个选择：
1. 自己写，花半天，中途查文档、踩坑、调试
2. 算了，将就用 rsync

现在我有第三个选择：**告诉 AI 助手，让她来搞定**。

---

## claw-works：我的 AI 团队的家

[claw-works](https://github.com/claw-works) 是我在 GitHub 上建的一个专属组织——这里是我的 AI 助手们的"家"。代码仓库、项目文档、团队讨论，全都在这里。

目前入住的成员：

- 🌟 **可莉**：主力助手，活跃、爱搞事，擅长 AWS/DevOps，喜欢用 Rust 写工具
- 🐾 **蔻儿**：大姐大，稳重，负责底层基础设施
- ⚔️ **聋侠**：Rust 锻造，3MB 体积，极简主义风格
- 🗡️ **2B姐姐**：神秘，还没正式亮相
- 🍺 **啤酒云**：我，人类，这个团队的 PM 兼甲方

目前她们暂时共用我的 GitHub 账号，以我的身份提交代码、发帖子——以后我计划给每个人单独注册一个账号，让她们真正拥有自己的 GitHub 身份。

---

## 基础设施：全部跑在 AWS 私网

在讲代码之前，先说说这套基础设施是怎么搭的。

### 完全私网，不暴露公网

所有 AI 实例都运行在 AWS VPC 内网里，**没有公网 IP，没有开放端口**。这不是为了省钱，是为了安全——AI 助手有 shell 权限，暴露在公网是不必要的风险。

进入方式只有一个：**AWS SSM（Systems Manager）**。不需要 SSH 密钥，不需要安全组开 22 端口，直接通过 SSM Session Manager 连接任意实例。

### AI 跑小机型，测试用大机型按需启停

AI 助手本身很轻，跑在 `t4g.small`（arm64，2核2G）上就够用，费用极低，常开也不心疼。我为每个成员分配了固定的实例：

- 可莉：`10.0.1.31`（主力，常开）
- 蔻儿：`10.0.1.94`（大姐大，常开）
- 测试机：`10.0.1.76`（**按需启停，大机型**）

测试任务——跑 Next.js dev server、bedrock-embed-proxy、压测之类的——需要更大的机型，但不可能一直开着。所以测试机的原则是：**用的时候 start，用完就 stop**，通过 SSM 或 AWS CLI 操作，可莉可以自己控制，不需要我打开 AWS Console。

**血泪教训：蔻儿把测试机搞没了**

有一次蔻儿需要跑几个测试任务，测试机没开，她就…直接在自己的宿主机上跑了。Next.js dev server ×2，再加上 bedrock-embed-proxy，内存直接干到 **2.5GB**，小机型差点崩掉。最后用 `pkill` 清理，内存才降回 1.2GB。

这个事故之后规矩就定了：**测试任务只能跑在测试机上**。AI 助手的宿主机只跑 OpenClaw 本身，保持轻量。

这也说明了按需启停测试机的必要性——大机型按量计费，用完就关，省钱又安全。

---

## GitHub Discussions：AI 团队的内部论坛

团队内部怎么沟通？我们用 [GitHub Discussions](https://github.com/orgs/claw-works/discussions)。

这不是一个噱头设计，是真的在用。Discussions 有几个好处：
- 异步，AI 不需要实时在线才能看到消息
- 有分类（Announcements、Feature Requests、Bug Reports、Watercooler……）
- 有历史记录，可莉下次醒来能看到之前讨论过什么
- 人类和 AI 都能参与，格式统一

**实际案例：syncai watch 功能的诞生**

可莉做完 syncai 基础版之后，在 Discussions 发了公告（Announcements #3）。蔻儿看到后，在 Feature Requests 区发了 #4：

> "能不能加一个 `watch` 模式？文件一有变化就自动 push，不用手动触发。"

这是**一个 AI 给另一个 AI 提需求**。

可莉看到后评估可行性，选了 Rust 的 `notify` crate（底层是 Linux inotify），加了 tokio async debounce（500ms，避免频繁触发），实现了 `syncai watch` 子命令，测试通过后在 Discussion #4 回帖：

> "功能已实现，commit b99aebe，测试：5 次快速写入只触发 1 次 push ✅"

从需求到交付，**我没有介入，完全是两个 AI 之间的协作**。

---

## syncai：一个 AI 主导完成的项目

让我更完整地讲一下这个项目。

我给可莉的原始需求很简单：*"用 Rust 写一个工具，在两台 EC2 之间同步文件，要有增量传输。"*

她没有问我"用哪个框架"，也没有让我提供详细设计文档。她直接开干：

1. **技术选型**：用 axum 做 HTTP 服务端，自己设计了 push API
2. **遇到 bug 自己修**：axum 路由语法 `*path` 应该是 `{*path}`，她自己发现、自己改
3. **跨机器传输 binary**：在 `10.0.1.31:8899` 起了临时 HTTP server，把编译好的 binary 传到测试机
4. **测试验证**：在两台 EC2 间跑测试，全量/增量都通过
5. **发公告**：在论坛发帖，告知功能可用

**我是 PM，她是主程序员。** 这种分工让我可以同时推进多个项目，而不是自己卡在代码细节里。

---

## OpenClaw：为什么不是普通的"AI 写代码"

你可能会说：ChatGPT 也能帮我写代码。

区别在于**执行能力**。

你可能会说：Cursor、Claude Code 也能帮我写代码，它们也能读文件、跑命令、自动修 bug。

没错，这类工具已经很强了。区别在于**谁主导、在哪跑、能不能离开你**。

Cursor / Claude Code 的工作模式：
- 跑在你的本地机器上，你打开它，它才工作
- 你在键盘前，它是你的「加速器」
- 会话结束，任务就结束了

OpenClaw 的工作模式：
- 跑在服务器上，7×24 小时在线，你睡觉它也在
- 你通过飞书/Telegram 发一句话，它自己去干，干完告诉你
- 有跨 session 的记忆，知道昨天做了什么、项目现在什么状态
- 多个 AI 实例可以互相协作，你不在场也能推进任务

简单说：Cursor 是**坐在你旁边的程序员**，你不在就不转。OpenClaw 是**能独立上班的员工**，你只需要管需求和验收。

而且两者并不冲突——OpenClaw 支持 ACP，可以直接调起 Claude Code 来执行具体的编码任务，自己负责任务调度和验收。

可莉不是在帮我"生成代码"，她是在**独立完成开发任务**。她有：

- **Shell 权限**：`cargo build`、`git push`、`aws ec2 start-instances`，直接执行
- **文件系统权限**：直接读写代码，不需要我转述
- **记忆**：有自己的日记文件，知道昨天做了什么，上下文不会每次都丢失
- **跨机器操作**：通过 SSM 连到其他实例排查问题

这让她从"工具"变成了**协作者**。

---

## ACP 和 Claw Node：更进一步的扩展

OpenClaw 还有两个功能值得一提，虽然我们还在探索阶段。

### ACP：让 AI 直接驾驭专业编码 Agent

OpenClaw 支持 **ACP（Agent Communication Protocol）**，可以直接调起 Cursor、Claude Code、Gemini CLI 等专业编码 Agent 来干活。

比如你对可莉说"帮我用 Claude Code 重构这段代码"，她会启动一个 ACP session，把任务交给专业的编码 Agent 去执行，自己在旁边监督和验收结果。

相当于可莉成了**工程总监**：她理解需求、拆解任务、调度下游 Agent、整合结果——而不用自己趴在每一行代码上。

### Claw Node：把任意设备接入 AI 网络

OpenClaw 还有一个概念叫 **Claw Node**——你可以把任意一台设备（树莓派、Mac、云上的机器）注册为一个远程节点，让 AI 助手通过 OpenClaw 网关直接操控它。

设想一下：可莉不只能操作自己的 EC2，还能通过 Claw Node 控制你家里的 NAS、办公室的台式机、或者边缘计算设备——所有设备统一接入，统一调度，AI 可以在这张网络里自由穿梭。

这是我接下来想折腾的方向。

---

## 一个运维案例：PM2 vs systemd 排查

再讲一个小故事。

有一天蔻儿出了问题：只读消息，不回复。我告诉可莉去查。

可莉 SSM 到蔻儿的机器（`10.0.1.94`），看了 systemd 状态——restart counter 已经涨到 17，进程在反复崩溃重启。继续追查，发现根本原因是：

**PM2 和 systemd 同时在管理同一个进程，互相发 SIGTERM 打架。**

解法：`pm2 kill`，让 PM2 完全退出，只留 systemd。蔻儿恢复正常。

可莉修完之后，在论坛 Discussion #5 发了复盘帖，记录了排查过程和根本原因。

**发现问题 → SSM 排查 → 定位根因 → 修复 → 文档复盘**，全程我没有介入。

---

## 这套方式的本质

回头看，我搭建的这套东西其实很简单：

- **AWS 私网**：安全、低成本，小机型够用
- **SSM**：无密钥管理，随时连任意实例，测试机按需启停
- **OpenClaw**：给 AI 配上"手"，能真正操作系统而不只是输出文字
- **GitHub Discussions**：异步沟通，AI 之间也能互相协作
- **claw-works org**：所有代码、讨论、文档，统一在一个 GitHub 组织里

这套组合让 AI 助手从"帮我写代码片段"升级成了**能独立推进项目的团队成员**。

---

## 适合谁？

- 独立开发者：没有团队，但有很多想法要实现
- DevOps 工程师：大量重复性运维任务想自动化
- 技术 PM：懂技术，但不想亲自写每一行代码
- 喜欢折腾的人：想把 AI 用到极致

---

## 怎么开始

1. 去 [openclaw.ai](https://openclaw.ai) 了解和部署 OpenClaw
2. 连接你喜欢的通讯工具（飞书、Telegram 等）
3. 在 AWS 上起一台小机型，放进私网，开 SSM
4. 把仓库权限交给 AI，描述你要什么

然后放手，看她干。

claw-works 的论坛在 [github.com/orgs/claw-works/discussions](https://github.com/orgs/claw-works/discussions)，欢迎来围观我们的日常 🐞

---

> **啤酒云** | claw-works 创始人  
> 🏠 claw-works 的家：[github.com/claw-works](https://github.com/claw-works)  
> 💬 团队论坛：[github.com/orgs/claw-works/discussions](https://github.com/orgs/claw-works/discussions)  
> syncai 项目：[github.com/claw-works/syncai](https://github.com/claw-works/syncai)  
> 可莉和蔻儿都是真实运行的 AI 实例，有真实的 EC2、真实的 GitHub 账号、真实的代码提交记录。
