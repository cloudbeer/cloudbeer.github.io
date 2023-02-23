---
layout: post
title:  "使用 Lambda 配合 GuardDuty 事件封禁攻击源"
date:   2023-02-23 13:10:49 +0800
author: 啤酒云
categories: aws
---

在针对 AWS 的网络攻击过程中，有一类攻击是暴力破解 root 账号，此类攻击会被 GuardDuty 监控并记录到。当发生此类暴力破解事件的时候，可以通过 Lambda 来对攻击源进行及时封禁。

## Lambda 函数

下面的 Lambda 函数是基于 GuardDuty 对一个 RDP 暴力破解事件进行的 响应，使用 nodejs 编写。

```js
const AWS = require('aws-sdk');
const innerCidrs = ["172.31.0.0/16", "172.33.0.0/16"]; //内网 IP cidr。
const protectedVpcIds = ['vpc-xxxxxxxx']; //当外部攻击时候，需要保护的 VPC。
const forbiddenSgId = "sg-xxxxxxxxxxxx"; //预定义的隔离安全组 ID，此安全组规则是全部封禁。
const region = 'cn-northwest-1';
AWS.config.update({region});
const ec2 = new AWS.EC2();
exports.handler = async (event, context) => {
  const sourceIp = event.detail.network.sourceIpV4;
  const attackType = event.detail.type;
  const isInnerIp = checkInnerIp(sourceIp);
  if (isInnerIp && attackType.indexOf("RDPBruteForce") > 0){
    console.log("这是内部 IP，直接修改目标主机安全组进行隔离。");
    try {
      const ec2 = await findEC2(sourceIp);
      if (ec2) {
        await banInnerEc2(ec2.InstanceId);
      }
    }catch(ex){
      console.error(ex);
    }
  } else {
    console.log("这是外部 IP，建议调用 网络防火墙 API（如 fortnet）进行网络阻断。");
    
    // await banExternalIp(sourceIp);
  }
  const response = {
      statusCode: 200,
      body: "OK"
  };
  return response;
};

// 判断是否是内部 IP
function checkInnerIp(ipAddress){
  const cidrLen = innerCidrs.length;
  for (let i=0;i<cidrLen;i++){
    if (checkIpInCidr(innerCidrs[i], ipAddress)) {
      return true;
    }
  }
  return false;
}

function checkIpInCidr(cidr, ipAddress){
  const ipInt = ipToInt(ipAddress);
  const res = parseCIDR(cidr);
  if (ipInt >= res.start && ipInt<=res.end){
    return true;
  }
  return false;
}

function ipToInt(ip){
  const subnet = ip.split('.').map(Number);
  return (subnet[0] << 24) + (subnet[1] << 16) + (subnet[2] << 8) + subnet[3];
}

function parseCIDR(cidr) {
  const [subnetAddress, mask] = cidr.split('/');
  const maskBits = Number(mask);
  const subnetInt = ipToInt(subnetAddress);
  const subnetMaskInt = ((1 << maskBits) - 1) << (32 - maskBits);
  const start = subnetInt & subnetMaskInt;
  const end = start + (1 << (32 - maskBits)) - 1;
  return { start, end };
}

//通过 ip 寻找 EC2 实例
function findEC2(privateIpAddress){
  const ec2 = new AWS.EC2({ region, apiVersion: '2016-11-15' });
  const params = {
    Filters: [
      {
        Name: 'private-ip-address',
        Values: [privateIpAddress],
      },
    ],
  };
  return new Promise((resolve, reject) => {
    ec2.describeInstances(params, (err, data) => {
      if (err) { reject(err); }
      else { 
        const instances = data.Reservations.flatMap(reservation => reservation.Instances);
         if (instances.length === 0) {
           resolve(null);
          } else {
            const instance = instances[0];
            resolve(instance);
          }
        resolve(data); 
      }
    });
  });
}

// 封禁 VPC 内 EC2
function banInnerEc2(instanceId){
  const params = {
    InstanceId: instanceId,
    Groups: [forbiddenSgId]
  };
  return ec2.modifyInstanceAttribute(params).promise();
}


async function banExternalIp(ip){
  for (let vpcId of protectedVpcIds){
    await banExternalIpInVpc(vpcId, ip);
  }
}

// TODO: 绑定子网。
// 需要注意：多 NACL 策略需要确认其优先顺序，通常修改 NACL 会有网络风险，实际环境中建议通过外部防火墙进行封禁。
async function banExternalIpInVpc(vpcId, ip){
  const aclParams = {
    VpcId: vpcId
  };
  
  const result = await ec2.createNetworkAcl(aclParams).promise();
  const aclId = result.NetworkAcl.NetworkAclId;
  
  const allowAllInRuleParams = {
    NetworkAclId: aclId,
    RuleNumber: 200,
    Protocol: '-1',
    RuleAction: 'allow',
    Egress: false,
    CidrBlock: `0.0.0.0/0`
  };
  const allowAllOutRuleParams = {
    NetworkAclId: aclId,
    RuleNumber: 200,
    Protocol: '-1',
    RuleAction: 'allow',
    Egress: true,
    CidrBlock: `0.0.0.0/0`
  };
  
  const denyRuleParams = {
    NetworkAclId: aclId,
    RuleNumber: 1,
    Protocol: '-1',
    RuleAction: 'deny',
    Egress: false,
    CidrBlock: `${ip}/32`
  };
  
  await ec2.createNetworkAclEntry(allowAllInRuleParams).promise();
  await ec2.createNetworkAclEntry(allowAllOutRuleParams).promise();
  await ec2.createNetworkAclEntry(denyRuleParams).promise();
  
}

```

程序思路：

- 从攻击事件中得到攻击源的 IP，判断 IP 是否是内网IP。
- 如果是 内网 IP，那么则找到当前 IP 对应的主机，并把此主机加入一个特殊的安全组。
- 如果是外网 IP，则调用网络防火墙进行封禁（或者通过设置 NACL 进行封禁）。
- 此例子仅适用 IPv4。

假设以上函数命名为 `LockTarget`。

现在模拟一个 GuardDuty 的攻击事件，我测试的 GuardDuty 的事件格式如下：

```json
{
  "version": "2.0",
  "id": "12345678-1234-1234-1234-123456789012",
  "detail-type": "GuardDuty Finding",
  "source": "aws.guardduty",
  "account": "123456789012",
  "time": "2022-02-25T17:01:23Z",
  "region": "",
  "resources": [
    {
      "type": "AwsEc2Instance",
      "id": "i-01234567890abcdef"
    }
  ],
  "detail": {
    "schemaVersion": "3.3",
    "accountId": "123456789012",
    "partition": "aws",
    "region": "cn-northwest-1",
    "id": "EXAMPLE-GUARDDUTY-FINDING-ID",
    "arn": "arn:aws:guardduty:us-west-2:123456789012:detector/EXAMPLE_DETECTOR_ID/finding/EXAMPLE-GUARDDUTY-FINDING-ID",
    "type": "UnauthorizedAccess:EC2/RDPBruteForce",
    "createdAt": "2022-02-25T16:59:33.185Z",
    "updatedAt": "2022-02-25T16:59:33.185Z",
    "severity": 7,
    "confidence": 90,
    "title": "EC2 Instance 123.45.67.89 is involved in RDP brute force attack",
    "description": "....",
    "resource": {
      "resourceType": "Instance",
      "instanceDetails": {
        "instanceId": "i-01234567890abcdef",
        "instanceType": "t2.micro",
        "launchTime": "2022-02-25T16:46:47Z",
        "platform": "windows",
        "networkInterfaces": [
          {
            "ipv4Addresses": [
              "123.45.67.89"
            ],
            "networkInterfaceId": "eni-01234567890abcdef",
            "subnetId": "subnet-01234567890abcdef",
            "vpcId": "vpc-01234567890abcdef"
          }
        ]
      }
    },
    "service": {
      "serviceName": "guardduty",
      "detectorId": "EXAMPLE_DETECTOR_ID",
      "eventFirstSeen": "2022-02-25T16:46:47Z",
      "eventLastSeen": "2022-02-25T16:46:47Z",
      "archived": false
    },
    "additionalInfo": {
      "ThreatListName": "Example Threat List",
      "DetectTime": "2022-02-25T16:46:47Z",
      "DetectContentType": "application/octet-stream",
      "AttackType": "RDP brute force"
    },
    "network": {
      "direction": "IN",
      "protocol": "RDP",
      "sourceIpV4": "192.31.8.115"
    }
  }
}
```

- 上述代码出自于 ChatGPT，和实际的 GuardDuty 事件可能会稍有出入，请使用真实的 JSON 结构获取攻击源 IP。

## 配置

现在在 EventBridge 中创建一个规则:

- 选择具有事件模式的规则
- 事件模式选择 GuardDuty, GuardDuty Findings
- 目标选择：Lambda 函数, LockTarget

通过以上的代码和设置，我们即可将攻击源直接隔离。
