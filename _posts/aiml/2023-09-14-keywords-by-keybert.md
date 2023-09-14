---
layout: post
title:  "使用 KeyBERT 进行关键字提取"
date:   2023-09-14 17:10:49 +0800
author: 啤酒云
categories: aws, aiml
---

在知识库搜索/问答场景中，用户输入的搜索内容有可能是一个完整的句子，在这个情况下，进行向量化之前，一般建议要进行关键字提取或者意图识别。在专业领域，一般可以训练一个模型来进行此项工作。使用模型提取关键字，可以使用 KeyBERT 这个库来完成。

## 开始

首先安装依赖库: keybert

## 英文提取

```python
from keybert import KeyBERT

doc = """
      Can you tell me how much the newest tesla model3?
      """
kw_model = KeyBERT()
kw_model.extract_keywords(doc)

```

结果为：

```text
[('tesla', 0.5866), ('model3', 0.519), ('newest', 0.315), ('tell', 0.1536)]
```

貌似还不错。

## 试试中文

改下 doc 的值。

```python
from keybert import KeyBERT

doc = """
      你能告诉我最新款的特斯拉model3的价格吗?
      """
kw_model = KeyBERT()
kw_model.extract_keywords(doc)

```

结果为：

```text
[('你能告诉我最新款的特斯拉model3的价格吗', 0.953)]
```

这...

## 原来可以中文

<https://maartengr.github.io/KeyBERT/guides/countvectorizer.html#tokenizer> 可以支持 jieba 进行分词。

安装依赖：jieba，sklearn

```python
from keybert import KeyBERT
import jieba
from sklearn.feature_extraction.text import CountVectorizer

def tokenize_zh(text):
    words = jieba.lcut(text)
    return words

vectorizer = CountVectorizer(tokenizer=tokenize_zh)


doc = """
      你能告诉我最新款的特斯拉model3的价格吗?
      """

kw_model = KeyBERT()
kw_model.extract_keywords(doc, vectorizer=vectorizer)
```

结果为：

```text
[('model3', 0.5499),
 ('最新款', 0.5385),
 ('的', 0.4434),
 ('告诉', 0.3991),
 ('价格', 0.3991)]
```

可以啊！

## Sentence Transformer

可以直接加载  Sentence Transformer 模型

```python
from keybert import KeyBERT
import jieba
from sklearn.feature_extraction.text import CountVectorizer

def tokenize_zh(text):
    words = jieba.lcut(text)
    return words

vectorizer = CountVectorizer(tokenizer=tokenize_zh)


doc = """
      你能告诉我最新款的特斯拉model3的价格吗?
      """

kw_model = KeyBERT(model="sentence-transformers/paraphrase-multilingual-mpnet-base-v2")
kw_model.extract_keywords(doc, vectorizer=vectorizer)
```

结果为：

```text
[('特斯拉', 0.6761),
 ('model3', 0.5485),
 ('最新款', 0.4465),
 ('价格', 0.4168),
 ('告诉', 0.292)]
```

从排序看，感觉 paraphrase-multilingual-mpnet-base-v2 更合我意啊。

Sentence Transformer 也可以这么用：

```python
model = SentenceTransformer('sentence-transformers/paraphrase-multilingual-mpnet-base-v2', device='cuda')
kw_model = KeyBERT(model=model)
```

输出结果和上面的一样。

## 更多模型的支持

参考这里，<https://maartengr.github.io/KeyBERT/guides/embeddings.html#hugging-face-transformers>

真是个好东西。

## Next

然后，只需要把提取出来的关键词丢给向量模型，剔除了干扰词的向量，搜索出来的结果质量肯定会大大提高。

---
参考

<https://maartengr.github.io/KeyBERT/>
