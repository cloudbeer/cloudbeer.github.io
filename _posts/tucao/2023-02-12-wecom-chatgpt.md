---
layout: post
title:  "企业微信集成 ChatGPT 开发笔记"
date:   2023-02-12 18:09:44 +0800
author: 啤酒云
categories: tucao
---

原来是想使用企业微信的机器人来集成 ChatGPT，但... 这玩意不支持收消息，只能推送消息，所以只能另寻他法。

## 思路

可以收消息的途径：企业应用。

可以发消息的：企业应用的推送，群机器人。

## 过程及重点代码

步骤如下：

### 新建企业应用

限制条件：必须是认证的企业，有认证过的相关域名。

新建一个企业微信的企业内部应用，并启用接收消息的 API 功能。

第一步必须有一个认证的过程，需要验证有效性，你必须把他的结果解密出来发给他。这个过程是他发送 GET 请求到你预定的 URL 的。

相关的验证代码如下：

```js
const qiwei = {
  //计算签名，如果计算结果和他给的结果一致就是有效的
  computeSign: (token, timestamp, nonce, msg_encrypt) => {
    const tmpArr = [token, timestamp, nonce, msg_encrypt];
    return sha1(tmpArr.sort().join(''));
  },
  decode: (data, encodingAESKey) => {
    let aesKey = Buffer.from(encodingAESKey + '=', 'base64');
    let aesCipher = crypto.createDecipheriv("aes-256-cbc", aesKey, aesKey.subarray(0, 16));
    aesCipher.setAutoPadding(false);
    let decipheredBuff = Buffer.concat([aesCipher.update(data, 'base64'), aesCipher.final()]);
    decipheredBuff = PKCS7Decoder(decipheredBuff);
    let len_netOrder_corpid = decipheredBuff.subarray(16);
    let msg_len = len_netOrder_corpid.subarray(0, 4).readUInt32BE(0);
    const result = len_netOrder_corpid.subarray(4, msg_len + 4).toString();
    return result; 
  },
}


function sha1(str) {
  const md5sum = crypto.createHash('sha1');
  md5sum.update(str);
  const ciphertext = md5sum.digest('hex');
  return ciphertext;
}


function PKCS7Decoder(buff) {
  var pad = buff[buff.length - 1];
  if (pad < 1 || pad > 32) {
    pad = 0;
  }
  return buff.slice(0, buff.length - pad);
}


class QiWeiController extends Controller {

  async verifySignature() {
    const { ctx, app } = this;
    const { msg_signature, timestamp, nonce, echostr } = ctx.query;
    const { QIWEI_TOKEN, QIWEI_ENCODING_AES_KEY } = app.config;
    const mySign = computeSign(QIWEI_TOKEN, timestamp, nonce, echostr);
    if (mySign != msg_signature) {
      ctx.body = "Invalid signature.";
      return false;
    } else {
      const result = decode(echostr, QIWEI_ENCODING_AES_KEY);
      ctx.body = result;
    }
  }
}
```

- 请注意，上述代码有可能并不在一个代码文件中。

### 接收消息

这个应用创建了之后，在客户端的工作台能看到这个应用，你可以和这个应用聊天，发给这个应用的消息都会被接受。发送的信息会被 Post 到你定义的 URL。

接收信息代码如下：

```js
const qiwei = {
  decodeIncomingMsg: (encMsg, key) => {
    const ptToUserName = /<ToUserName><!\[CDATA\[(.*?)\]\]><\/ToUserName>/;
    const ptFromUserName = /<FromUserName><!\[CDATA\[(.*?)\]\]><\/FromUserName>/;
    const ptContent = /<Content><!\[CDATA\[(.*?)\]\]><\/Content>/;
    const realMsg = qiwei.decode(encMsg, key);

    const resMsg = {
      ToUserName: realMsg.match(ptToUserName)[1],
      FromUserName: realMsg.match(ptFromUserName)[1],
      Content: realMsg.match(ptContent)[1],
    };
    //这里可以修改到 MQ 中，并最终落盘
    qiwei.incomings.push(resMsg)
    return resMsg;
  },
}


class QiWeiController extends Controller {

  async incoming() {
    const { ctx, app } = this;
    const { msg_signature, timestamp, nonce } = ctx.query;
    const { QIWEI_TOKEN, QIWEI_ENCODING_AES_KEY } = app.config;
    const body = ctx.request.body;
    const ptEncMsg = /<Encrypt><!\[CDATA\[(.*?)\]\]><\/Encrypt>/;
    const found = body.match(ptEncMsg);
    if (found) {
      const mySign = computeSign(QIWEI_TOKEN, timestamp, nonce, found[1]);
      if (mySign == msg_signature) {
        decodeIncomingMsg(found[1], QIWEI_ENCODING_AES_KEY);
      }
    };
    ctx.body = "OK";
  }
}
```

- 接收到信息之后，讲信息解码出来，放到一个数组(队列) 中，供其他 deamon 方法调用。

### 请求 ChatGPT

使用了 chatpgt 这个 npm 包，调用非常简单。

```js

const qiwei={

  chatdeamon: async (app, paimon) => {
    while (true) {
      const tarMsg = qiwei.incomings.shift();
      // tarMsg && console.log(tarMsg);
      if (tarMsg) {
        conversationId = tarMsg.ToUserName;
        let chatOpts = {
          timeoutMs: 2 * 60 * 1000,
          conversationId
        };
        if (qiwei.parentMessageId) {
          chatOpts.parentMessageId = parentMessageId;
        };
        console.log("输入:", tarMsg.Content, "堆积量:", qiwei.incomings.length);
        const result = await paimon.sendMessage(tarMsg.Content, chatOpts);
        parentMessageId = result.id;
        console.log("投送结果：", result.text);
        await qiwei.sendToPerson(app, result.text, tarMsg.FromUserName);
        await qiwei.paimonSendToRoom(app, tarMsg.Content, result.text, tarMsg.FromUserName);
      } else {
        await sleep(1000);
      }
    }
  },
}


function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

```

- 写了死循环处理消息，这里 的 app 是 eggjs 的上下文的，用于取配置。
- ChatGPT 的 API 经常限流，这里处理成了同步调用，一条一条往下进行。
- 代码中 paimon 是一个 ChatGPT 实例。

### 分发消息

上面的代码可以看到拿到结果后分别分发到了个人和机器人。

发送到个人可以在直接在单聊对话中看到结果，同时可以让企业微信机器人分发到群里。

分发到个人的代码如下：

```js
const qiwei = {
  getAccessToken: async (app) => {
    if (qiwei.access_token.hasOwnProperty("access_token") && qiwei.access_token.hasOwnProperty("expire_time")) {
      const expire_time = qiwei.access_token.expire_time;
      const current = Math.floor(Date.now() / 1000);
      const isExpire = expire_time < current ? true : false
      if (!isExpire) {
        return qiwei.access_token.access_token;
      }
    }

    let access_response = await app.curl(`https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=${app.config.QIWEI_CORP_ID}&corpsecret=${app.config.QIWEI_APP_SECRET}`, {
      dataType: 'json'
    });
    let { data: {
      access_token, expires_in
    } } = access_response;

    if (access_token) {
      qiwei.access_token = {
        access_token,
        expire_time: Math.floor(Date.now() / 1000) + expires_in
      };
      return access_token;
    } else {
      console.log(`获取 access_token 失败`);
      console.log(access_response.data.toString());
      return null;
    }
  },
  sendToPerson: async (app, a, to) => {
    const access_token = await qiwei.getAccessToken(app);
    const url = `https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token=${access_token}`;
    const msg = {
      touser: to,
      msgtype: "text",
      agentid: app.config.QIWEI_APP_AGENT_ID,
      text: {
        content: a
      }
    };

    const res = await app.curl(url, {
      method: 'POST',
      contentType: 'json',
      data: msg,
      dataType: 'json',
    });
    console.log("个人投送完成！");
  },
}

```

- 直接调用 信息发送 API 完成。

使用群机器人完成发送

```js
const qiwei = {

  paimonSendToRoom: async (app, q, a, to) => {
    const msg = {
      msgtype: "markdown",
      markdown: {
        content: `${to}: **${q}**
---
<font color="warning">${a}</font>`,
      }
    };
    await app.curl(app.config.QIWEI_BOT_WEBHOOK, {
      method: 'POST',
      contentType: 'json',
      data: msg,
      dataType: 'json',
    });
    console.log("机器人投送完成！");

  },
}
```

- 这个 API 很简单，直接把消息组装好丢给 webhook 就行了。表扬一下这个 API。

## 总结一下

就不画时序图了。

整体的过程是：

- 用户给企业微信 APP 发信息。
- APP 收到信息丢入队列中，包含了文本，发送人等信息。
- 另一个进程获取从队列中获取一个记录，调用 openai API 得到结果。
- 使用企业微信的消息发送 API 将结果发给问问题的人。
- 使用群机器人的 WebHook 将结果发送给相应的群。

## 吐槽

1 隔壁的钉钉和飞书的机器人都能直接收发消息，为啥你不行。

2 企业微信的 API 设计，有 XML 的，有 Json 的，API 调用方式也是千奇百怪。收消息的那个签名验证搞那么复杂，示例和 SDK 还不全。

3 文档真乱，要到处去找。

4 哈哈，我的机器人名字叫 派萌/pimon。

---

参考链接：

<https://developer.work.weixin.qq.com/document/path/91770>

<https://developer.work.weixin.qq.com/document/10514>

<https://www.npmjs.com/package/chatgpt>

<https://developer.work.weixin.qq.com/document/path/90236>

<https://github.com/WecomTeam/InnerAppCodeSample/tree/main/server>
