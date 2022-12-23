---
layout: post
title:  "编写 Argo CD 人工部署 API"
date:   2022-12-23 17:53:33 +0800
author: 啤酒云
categories: devops, container, argocd
---

使用 ArgoCD 可以有效解耦 CI 和 CD。
想象这个场景：当 CI 流程将构建物打包完成，并更新了 Git 部署仓库，此时 CI 流程发通知给相关有审批人员，审批者通过点击链接就可以完成部署。
虽然可以通过登录 Argo CD 的 UI 界面可以完成此操作，但感觉还不够丝滑。

## 想法

我的想法是：

编写 2 个 API 暴露出来：

- 发邮件(或者发微信，slack 啥的) 的 API
- 封装 argocd sync 的 API

过程是：

CI 结束后 -> 调用 API 发邮件，邮件的内容，是一个带有时间戳签名的 Url -> 收到邮件的人，直接在邮件里点击此链接触发 argocd sync。
下面我来分解这一过程，并最后给出整体的代码。

本文的代码使用 C# 编写，为啥用 C#？因为好久没用过了。这个语言我不想忘记，他是最好的面对对象语言。

## 先看看 Argo CD API

通过这个地址阅读 Argo CD API 文档：`<argocd_server_url>/swagger-ui`

我们找到了我们需要的 API 有两个：

- SessionService_Create: `<argocd_server_url>/api/v1/session`，获取 Authorization token。
- ApplicationService_Sync: `<argocd_server_url>/api/v1/applications/{name}/sync`，同步应用。

请将 `<argocd_server_url>` 更换为您的 Argo CD 对外发布地址 (在 K8S 集群内对应的服务为：argocd-server)。

调用方法大约为：

```text
POST /api/v1/session

{
  "username": "admin",
  "password": "argocd-secret"
}
```

- 这里需要传入您的 Argo CD 的用户名和密码。

```text
POST /api/v1/applications/{name}/sync
Authorization: Bearer ${token}

{
  "appNamespace": "argocd"
}
```

- 其中必须的参数 url 中间的 name，这个就是创建的 ArgoCD 应用的名字。
- 注意 appNamespace 是 ArgoCD 应用的命名空间，不是你的业务应用的命名空间。

有了这 2 个 API，下面的操作就简单了。

## 发送更新邮件

下面这个方法映射了一个 URL 用于发送邮件：

```csharp
  public string sendEmail(string email, string appName){

    var email = new MimeMessage();

    email.Sender = MailboxAddress.Parse("cloudbeer@gmail.com");
    email.Sender.Name = "CD Bot";

    email.From.Add(email.Sender);
    email.To.Add(MailboxAddress.Parse(emails));
    email.Subject = $"Application {appName} is ready for deployment.";
    var sign = signApi(appName, 7200); 
    email.Body = new TextPart(TextFormat.Html) { 
      Text =  $@"
        Application Name: {appName}<br>
        Updated Date: {DateTime.Now}<br>
        <br>
        Click this link to approve the deployment in 2 hours.<br><br><br>
        <a href='http://localhost:9999/argo/deploy?name={appName}&sign={sign}' 
          style='padding:10px 30px;border:1px solid #ccc;border-radius:5px;'>
        Deploy Now
        </a>
        <br /><br><br>
        <br />请注意：上述链接 2 小时候有效。"
    };

    using (var smtp = new SmtpClient())
    {
        smtp.Connect("smtp.gmail.com", 465, true);
        smtp.Authenticate("cloudbeer@gmail.com", gmailPassword);
        smtp.Send(email);
        smtp.Disconnect(true);
    }
    return "OK";
  }
```

- 使用了 MailKit 发送邮件。
- 此 API 接受参数: email 和 appName
- 计算包含时间戳(2小时过期时间)的签名， 将部署链接 (http://localhost:9999/argo/deploy?name=?) 和签名作为邮件正文发送到目标邮箱。
- 此 api 应该由 CI 来调用。
- 点击邮件里面的链接，则会触发部署操作。

## 触发部署操作

先看代码：

```csharp

  public async Task<string> deploy(string name, string sign)
  {
    if (!verifyApi(name, sign)){
      return "签名验证失败，或者链接过期了";
    }

    var map = new Dictionary<string, string>();
    map.Add("username", argoUsername);
    map.Add("password", argoPassword);
    var pContent = JsonSerializer.Serialize(map);


    var request = new HttpRequestMessage(HttpMethod.Post, argoUrl + "/api/v1/session");
    request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
    request.Content = new StringContent(pContent, Encoding.UTF8);
    request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
    using (var httpClientHandler = new HttpClientHandler())
    {
      httpClientHandler.ServerCertificateCustomValidationCallback = (message, cert, chain, errors) => { return true; };
      using (var client = new HttpClient(httpClientHandler))
      {
        var response = await client.SendAsync(request);
        response.EnsureSuccessStatusCode();
        string responseBody = await response.Content.ReadAsStringAsync();

        var token = JsonSerializer.Deserialize<Dictionary<string,string>>(responseBody);

        var result = await this.syncApp(client, token["token"], "gateway");
        return result;
      }
    }
  }

```

- 首先验证签名。
- 通过调用 ArgoCD 的 `/api/v1/session` 去获取 Argo CD 的 临时 Authorization token。
- 调用应用同步 API。
- 调用成功则完成触发应用同步。

## 测试过程

1 邮件发送

```shell
curl http://localhost:9999/argo/sendemail?email=cloudbeer@gmail.com&appName=product
```

2 gmail 邮箱收邮件，点击 Deploy Now 链接。这个链接类似这样：

<http://localhost:9999/argo/deploy?name=product&sign=eyJl...1In0=>

3 点击上面的链接完成应用部署。

## 完整的代码

```csharp
using Microsoft.AspNetCore.Mvc;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using MailKit.Net.Smtp;
using MimeKit;
using MimeKit.Text;
using System.Security.Cryptography;

namespace ArgoTrigger.Controllers;

public class ArgoController : Controller
{
  private string argoUrl = Environment.GetEnvironmentVariable("ARGO_URL") ?? "http://host.docker.internal:8080";
  private string argoUsername = Environment.GetEnvironmentVariable("ARGO_USERNAME")?? "admin";
  private string argoPassword = Environment.GetEnvironmentVariable("ARGO_PASSWORD")??"uBGroHnh9TjSa7ud";
  private string gmailPassword = Environment.GetEnvironmentVariable("GMAIL_PASSWORD");
  
  public async Task<string> deploy(string name, string sign)
  {
    if (!verifyApi(name, sign)){
      return "签名验证失败，或者链接过期了";
    }

    var map = new Dictionary<string, string>();
    map.Add("username", argoUsername);
    map.Add("password", argoPassword);
    var pContent = JsonSerializer.Serialize(map);


    var request = new HttpRequestMessage(HttpMethod.Post, argoUrl + "/api/v1/session");
    request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
    request.Content = new StringContent(pContent, Encoding.UTF8);
    request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
    using (var httpClientHandler = new HttpClientHandler())
    {
      httpClientHandler.ServerCertificateCustomValidationCallback = (message, cert, chain, errors) => { return true; };
      using (var client = new HttpClient(httpClientHandler))
      {
        var response = await client.SendAsync(request);
        response.EnsureSuccessStatusCode();
        string responseBody = await response.Content.ReadAsStringAsync();

        var token = JsonSerializer.Deserialize<Dictionary<string,string>>(responseBody);

        var result = await this.syncApp(client, token["token"], "gateway");
        return result;
      }
    }
  }

  private async Task<string> syncApp(HttpClient client, string token, string appName)
  {
    var map = new Dictionary<string, string>();
    map.Add("appNamespace", "argocd");
    var pContent = JsonSerializer.Serialize(map);

    var request = new HttpRequestMessage(HttpMethod.Post, argoUrl + "/api/v1/applications/" + appName + "/sync");


    request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
    request.Content = new StringContent(pContent, Encoding.UTF8);
    request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");

    var response = await client.SendAsync(request);
    response.EnsureSuccessStatusCode();
    string responseBody = await response.Content.ReadAsStringAsync();

    return responseBody;
  }

  public string sendEmail(string emails, string appName){
    Console.WriteLine(emails);
    Console.WriteLine(gmailPassword);

    var email = new MimeMessage();

    email.Sender = MailboxAddress.Parse("cloudbeer@gmail.com");
    email.Sender.Name = "CD Bot";

    email.From.Add(email.Sender);
    email.To.Add(MailboxAddress.Parse(emails));
    email.Subject = $"Application {appName} is ready for deployment.";
    var sign = signApi(appName, 7200); //You should approve in 10 min.
    email.Body = new TextPart(TextFormat.Html) { 
      Text =  $@"
        Application Name: {appName}<br>
        Updated Date: {DateTime.Now}<br>
        <br>
        Click this link to approve the deployment in 2 hours.<br><br><br>
        <a href='http://localhost:9999/argo/deploy?name={appName}&sign={sign}' 
          style='padding:10px 30px;border:1px solid #ccc;border-radius:5px;'>
        Deploy Now
        </a>
        <br /><br><br>
        <br />请注意：上述链接 2 小时候有效。"
    };

    using (var smtp = new SmtpClient())
    {
        smtp.Connect("smtp.gmail.com", 465, true);
        smtp.Authenticate("cloudbeer@gmail.com", gmailPassword);
        smtp.Send(email);
        smtp.Disconnect(true);
    }
    return "OK";
  }

  private string signApi(string appName, int expireSecond){
    string cachedKey = "abcdefghijklmnop";
    DateTime expireAt = DateTime.Now.AddSeconds(expireSecond);
    string sign = sha256(cachedKey + appName + expireAt.Ticks);
    var signJson = new Dictionary<string, string>();
    signJson.Add("expireAt", expireAt.Ticks.ToString());
    signJson.Add("sign", sign);
    var jStrSign =  JsonSerializer.Serialize(signJson);
    Console.WriteLine(jStrSign);

    return base64Encode(jStrSign);
  }
  private bool verifyApi(string appName, string sign){
    string cachedKey = "abcdefghijklmnop";
    string jStrSign = base64Decode(sign);
    var signJson = JsonSerializer.Deserialize<Dictionary<string, string>>(jStrSign);
    long expireAt = long.Parse(signJson["expireAt"]);
    if(DateTime.Now.Ticks > expireAt){
      return false;
    }
    string signFromApi = signJson["sign"];
    string signFromCache = sha256(cachedKey + appName + signJson["expireAt"]);
    return signFromCache == signFromApi;
  }

  string sha256(string randomString)
  {
    using (SHA256 mySHA256 = SHA256.Create())
    {
      byte[] crypto = mySHA256.ComputeHash(Encoding.UTF8.GetBytes(randomString));
      string hash = String.Empty;
      foreach (byte theByte in crypto)
      {
          hash += theByte.ToString("x2");
      }
      return hash;
    }
  }
  string base64Encode(string plainText) {
    var plainTextBytes = System.Text.Encoding.UTF8.GetBytes(plainText);
    return System.Convert.ToBase64String(plainTextBytes);
  }
  string base64Decode(string base64EncodedData) {
    var base64EncodedBytes = System.Convert.FromBase64String(base64EncodedData);
    return System.Text.Encoding.UTF8.GetString(base64EncodedBytes);
  }
}

```

## 附：.NET Core 项目入门

下面记录了代码开始之前的工作，包括 .NET 运行环境配置，创建项目，开发配置等工作。我开始写这个文章的时候电脑还没有 .NET 环境。

我准备使用 .NET 镜像作为我的开发环境，先拉一下镜像：

```shell
docker pull mcr.microsoft.com/dotnet/sdk:7.0
```

### 创建一个项目

```shell
docker run --rm \
  -v ~/projects/cloudbeer:/app \
  mcr.microsoft.com/dotnet/sdk:7.0 \
  dotnet new webapp -o /app/ArgoTrigger --no-https -f net7.0
```

这个命令含义如下：

- 家目录的 /projects/cloudbeer 映射到容器的 /app
- 通过 dotnet 命令在子目录 ArgoTrigger 里生产一个 asp.net core 项目。

### 安装依赖包

安装 2 个依赖包，MailKit 和 MimeKit，用来发送通知邮件。

```shell
docker run --rm \
  -v ~/projects/cloudbeer:/app \
  mcr.microsoft.com/dotnet/sdk:7.0 \
  sh -c "cd /app/ArgoTrigger && dotnet add package MailKit"
```

```shell
docker run --rm \
  -v ~/projects/cloudbeer:/app \
  mcr.microsoft.com/dotnet/sdk:7.0 \
  sh -c "cd /app/ArgoTrigger && dotnet add package MimeKit"
```

### 启动项目

现在项目已经产生，可以打开 vscode 进行编辑了。

默认的 Web 开发 Url 是 localhost + 随机端口，但我们需要将 容器的 端口映射出来，需要一个 0.0.0.0 的固定端口，修改配置文件 appsettings.json，加入：`"Urls": "http://0.0.0.0:9999"`

appsettings.json 这个文件现在看起来应该是这样：

```json
{
  "Urls": "http://0.0.0.0:9999",
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*"
}
```

然后启动项目的开发模式：

```shell
docker run -it --rm -p 9999:9999 \
  -e DOTNET_WATCH_RESTART_ON_RUDE_EDIT=true \
  -e GMAIL_PASSWORD=$GMAIL_PASSWORD \
  -v ~/projects/cloudbeer:/app \
  mcr.microsoft.com/dotnet/sdk:7.0 \
  sh -c "cd /app/ArgoTrigger && dotnet watch -v"
```

- GMAIL_PASSWORD 是一个环境变量，是 Gmail 的临时登录 token，这个变量通过本机到容器，最终传入发送邮件的代码中。

现在可以打开 <http://localhost:9999/> 了。

> 没有 IDE 的代码提示，比较痛苦。不过，老夫是一把梭，一谷歌，一剪刀搞定一切。
