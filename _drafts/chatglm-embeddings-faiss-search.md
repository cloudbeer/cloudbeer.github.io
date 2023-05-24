---
layout: post
title:  "私有化知识库部署测试"
date:   1977-12-04 22:13:33 +0800
author: 啤酒云
categories: aiml
---

使用 ChatGLM 来提取 embeddings，faiss 进行临近搜索，并且让 ChatGLM 总结发言。

```python
import torch
import transformers

import numpy as np
import torch.nn.functional as F

def to_vec(tokenizer,model,text):
    input_ids = tokenizer.encode(text, return_tensors="pt").to(model.device)
    model_output = model(input_ids, output_hidden_states=True)
    data = (model_output.hidden_states[-1].transpose(0, 1))[0]
    data = F.normalize(torch.mean(data, dim=0), p=2, dim=0)
    return data.tolist()

```


```python
model_name = "/media/cloudbeer/PSSD/huggingface/chatglm-6b"
tokenizer = transformers.AutoTokenizer.from_pretrained(model_name,trust_remote_code=True)
model = transformers.AutoModel.from_pretrained(model_name,trust_remote_code=True).half()
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model.to(device)


def get_emb(text):
    return to_vec(tokenizer, model,text)
```

```python
import faiss 
index = faiss.IndexFlatL2(4096) 
print(index.is_trained)
```

```python
texts = [
   '''
他伸出手，用指腹轻柔地擦去她眼角的泪，柔声道：
“错的是在路上飙车的人，不是你。你也无需将别人的人生往自己身上揽，你不是灾星。这世上没有谁是灾星，只是运气不够好罢了，
但运气这件事，从来不是一成不变的
''',
'''
次日清晨，段正淳与妻、儿话别。听段誉说木婉清昨晚已随其母秦红棉而去，段正淳呆了半晌，叹了几口气，问起崔百泉、过彦之二人，却说早已首途北上。随即带同三公、四护卫到宫中向保定帝辞别，与慧真、慧观二僧向陆凉州而去。段誉送出东门十里方回。
''',
'''
这是午后，保定正在宫中裥房育读佛经，一名太监进来禀报：“皇太弟府詹事启奏，皇太弟世子突然中邪，已请了太医前去诊治。”保定帝本就担心，段誉中了延废太子的毒后，未必便能安然清除，当即差两名太监前去探视。过了半个时辰，两名太监回报：“皇太弟世子病势不轻，似乎有点神智错乱。”
''',
'''保定帝暗暗心惊，当即出宫，到镇南王府亲去探病。刚到段誉卧室之外，便听得砰嘭、乒乓、喀喇、呛啷之声不绝，尽是诸般器物碎裂之声。门外侍仆跪下接驾，神色甚是惊慌。保定帝推门进去，只见段誉在房中手舞足蹈，将桌子、椅子，以及各种器皿陈设、文房玩物乱推乱摔。两名太医东闪西避，十分狼狈。保定帝叫道：“誉儿，你怎么了？”''',
'''段誉神智却仍清醒，只是体内真气内力太盛，便似要迸破胸膛将出来一般，若是挥动手足，掷破一些东西，便略略舒服一些。他见保定帝进来，叫道：“伯父，我要死了！”双手在空中乱挥圈子。''',
'''刀白凤站在一旁，只是垂泪，说道：“大哥，誉儿今日早晨星还好端端地送他爹出城，不知如何，突然发起疯来。”保定帝安慰道：“弟妹不必惊慌，定是在万劫谷所中的毒未清，不难医治。”向段誉道：“觉得怎样？”''',
'''段誉不住的顿足，叫道：“侄儿全身肿了起来，难受之极。”保定帝瞧他脸面与手上皮肤，一无异状，半点也不肿胀，这话显是神智迷糊了，不由得皱起了眉头。''',
'''一名太医道：“启奏皇上，世子脉搏洪盛之极，似乎血气太旺，微臣愚见，给世子放一些血，不知是否使得？”保定帝心想此法或许管用，点头道：“好，你给他放放血。”那太医应道：“是！”打开药箱，从一只磁盒中取出一条肥大的水蛭为。水蛭善于吸血，用以吸去病人身上的瘀血，是为方便，且不疼痛。那太医捏住段誉的手臂，将水蛭口对准他血管。水蛭碰到段誉手臂后，不住扭动，无论如何不肯咬上去。那太医大奇，用力按着水蛭，过得半晌，水蛭一挺，竟然死了。那太医在皇帝跟前出丑，额头汗水涔涔而下，忙取过第二只水蛭来，仍是如此僵死。'''
]


results = []
for txt in texts:
    results.append(get_emb(txt))

index.add(np.array(results).astype('float32'))
```


```python
def pretty(q, a):
    prompt = f'''
    阅读下面的问答，总结之后直接给出答案，如果信息不足需要回答 "没有相关信息":
    问题:{q}
    答案:{str.strip(a)}
    '''
    print("总结提示词", prompt)
    response, history = model.chat(tokenizer, prompt, history=[])
    return response

def search(query):
    D, I = index.search(np.array([get_emb(query)]).astype('float32'), 2)
    return texts[I[0][0]] + "。 \n\n " + texts[I[0][1]]
```

```python
stext = '谁的真气很足?'
res = search(stext)
pre_res = pretty(stext, res)
print("<------------\n", pre_res, "\n-------------->")
```

输出为：

```text
总结提示词 
    阅读下面的问答，总结之后直接给出答案，如果信息不足，回答 "没有相关信息":
    问题:谁的真气很足?
    答案:段誉神智却仍清醒，只是体内真气内力太盛，便似要迸破胸膛将出来一般，若是挥动手足，掷破一些东西，便略略舒服一些。他见保定帝进来，叫道：“伯父，我要死了！”双手在空中乱挥圈子。
。 

 段誉不住的顿足，叫道：“侄儿全身肿了起来，难受之极。”保定帝瞧他脸面与手上皮肤，一无异状，半点也不肿胀，这话显是神智迷糊了，不由得皱起了眉头。
    
<------------
 段誉在《天龙八部》中体内真气内力很足。 
-------------->
```