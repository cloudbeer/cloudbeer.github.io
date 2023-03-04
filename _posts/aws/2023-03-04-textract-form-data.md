---
layout: post
title:  "使用 Java 组装 Amazon Textract 解析出来的键值对"
date:   2023-03-04 13:10:49 +0800
author: 啤酒云
categories: aws, tucao
---

Amazon Textract 就是 OCR, 针对国际单据啥的识别有奇效，看控制台的 Demo 觉得很受惊，居然有 KV 键值对的显示。但用 Java 代码咋获取键值对呢？他的 KEY_VALUE_SET 类型的 Block 使用方法 .text() 啥都没有哇。

## Java 的 Block 输出

先打印一下看看:

```java
for (Block block : blocks) {
    System.out.println("The block type is " + block.blockType().toString());
    System.out.println(block);
    System.out.println("----------\n");
}
```

下面是打印的原始 Block 部分信息（实际上有一大坨，这里一个类型留了一个）：

```text

The block type is PAGE
Block(BlockType=PAGE, Geometry=Geometry(BoundingBox=BoundingBox(Width=0.8405368, Height=1.0, Left=0.09841533, Top=0.0), Polygon=[Point(X=0.09841533, Y=0.0), Point(X=0.9389521, Y=0.0), Point(X=0.9229099, Y=1.0), Point(X=0.11533637, Y=1.0)]), Id=bbede76c-e163-45ee-81d4-82afc8bad5ad, Relationships=[Relationship(Type=CHILD, Ids=[e694910a-dc8c-4bd4-9b4e-d6262b549705, c959f258-1e33-4591-8394-dce960cc7e55, 82c3e843-c149-4f8b-b3bc-0e3299f6d551, 4932758c-12a7-4bc3-90a4-87a135c54d6e, 01aa9893-ccb2-4b0a-b2a0-ea954b35fe4b, 2975d587-f5de-4436-92f3-480f1c9aa656, 951fca1a-7f9d-475b-8aff-e9e0ef9000d5, ....])])
----------

The block type is LINE
Block(BlockType=LINE, Confidence=70.37652, Text=xxxxxxxxxxx - mail@frankonia.de, Geometry=Geometry(BoundingBox=BoundingBox(Width=0.2087112, Height=0.023847194, Left=0.58435017, Top=0.03585644), Polygon=[Point(X=0.58439976, Y=0.03585644), Point(X=0.7930614, Y=0.036802612), Point(X=0.7928248, Y=0.059703637), Point(X=0.58435017, Y=0.058780655)]), Id=e694910a-dc8c-4bd4-9b4e-d6262b549705, Relationships=[Relationship(Type=CHILD, Ids=[3d1c10aa-9ee9-4efa-8f24-eb4487fcc927, 7e653065-ecf4-47a5-9518-aa4b70fcd7ea, d103f1ac-25ab-48cf-9824-0ff6277e59e2])])
----------

The block type is WORD
Block(BlockType=WORD, Confidence=98.42162, Text=Fax, TextType=PRINTED, Geometry=Geometry(BoundingBox=BoundingBox(Width=0.018412054, Height=0.01635857, Left=0.6832591, Top=0.061593868), Polygon=[Point(X=0.68335754, Y=0.061593868), Point(X=0.7016712, Y=0.061674744), Point(X=0.70156115, Y=0.07795244), Point(X=0.6832591, Y=0.07787301)]), Id=66db8d1e-a1b6-40c4-8a77-afc4fc250870)
----------

The block type is WORD
Block(BlockType=WORD, Confidence=98.718414, Text=€, TextType=PRINTED, Geometry=Geometry(BoundingBox=BoundingBox(Width=0.0076815123, Height=0.018535566, Left=0.8544621, Top=0.87233585), Polygon=[Point(X=0.8547062, Y=0.87233585), Point(X=0.8621436, Y=0.8723405), Point(X=0.86189395, Y=0.8908714), Point(X=0.8544621, Y=0.8908674)]), Id=db9dcabb-8aa6-4bb7-b924-5f91add0530b)
----------


The block type is KEY_VALUE_SET
Block(BlockType=KEY_VALUE_SET, Confidence=86.59171, Geometry=Geometry(BoundingBox=BoundingBox(Width=0.08317889, Height=0.024558436, Left=0.6154753, Top=0.7993664), Polygon=[Point(X=0.6155607, Y=0.7993664), Point(X=0.6986542, Y=0.79944664), Point(X=0.69848675, Y=0.8239249), Point(X=0.6154753, Y=0.82385427)]), Id=89664d58-b1eb-4ad3-912f-705500e4b08b, Relationships=[Relationship(Type=VALUE, Ids=[0df283e1-7079-46ef-baea-fafedc580ee4]), Relationship(Type=CHILD, Ids=[11a76d29-860a-43f4-bf8a-816b5993ae9c, 47f62df8-6fb1-4b09-b4ff-ac8901f230a3])], EntityTypes=[KEY])
----------

The block type is KEY_VALUE_SET
Block(BlockType=KEY_VALUE_SET, Confidence=86.59171, Geometry=Geometry(BoundingBox=BoundingBox(Width=0.056614958, Height=0.023218233, Left=0.81078696, Top=0.7957822), Polygon=[Point(X=0.8110504, Y=0.7957822), Point(X=0.8674019, Y=0.7958376), Point(X=0.8670859, Y=0.8190004), Point(X=0.81078696, Y=0.8189512)]), Id=0df283e1-7079-46ef-baea-fafedc580ee4, Relationships=[Relationship(Type=CHILD, Ids=[2f71d668-e883-40dc-9d73-0a50d5954e84, 904205cd-0eeb-4bd6-a4e1-05c1dd168182])], EntityTypes=[VALUE])
----------

```

## 数据结构分析

这真是个费眼睛的活儿，对比 python 的代码，分析出 KEY_VALUE_SET 部分的结构为：

- `KEY_VALUE_SET` 分类 `KEY` 和 `VALUE`, 这个记录在 `blockType()` 为 `KEY_VALUE_SET` 的 `EntityTypes` 字段里了。
- 通过 `KEY` 的 block 的 `Relationships` 中的 `CHILD` 的 `Ids` 去找到对应的 `WORD`，`text()` 就是 `KEY` 的值了。
- `KEY` block 的 `Relationships` 里有一个 `VALUE` 的关系，value block 的 `Ids` 就存在这里。
- 通过上面的 id 匹配 block 的 `Id` 字段得到对应的 value block。
- 然后通过 value block `Relationships` 的 `CHILD` 再寻找为 `WORD` 类型的 block 的值。
- `LINE` 类型暂时没用上。

## 完整代码

然后就可以写出 java 对应的代码：

```java
package aws.cloudbeer;

import software.amazon.awssdk.auth.credentials.ProfileCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.textract.TextractClient;
import software.amazon.awssdk.services.textract.model.*;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;


public class Main {
    public static void main(String[] args) {

        Region region = Region.US_EAST_1;
        TextractClient textractClient = TextractClient.builder()
                .region(region)
                .credentialsProvider(ProfileCredentialsProvider.create())
                .build();
        analyzeDocS3(textractClient, "cloudbeer-textract", "1.jpg");
        textractClient.close();
    }


    public static void analyzeDocS3(TextractClient textractClient, String bucketName, String docName) {
        try {
            S3Object s3Object = S3Object.builder()
                    .bucket(bucketName)
                    .name(docName)
                    .build();

            Document myDoc = Document.builder()
                    .s3Object(s3Object)
                    .build();


            List<FeatureType> featureTypes = new ArrayList<FeatureType>();
            featureTypes.add(FeatureType.FORMS);
//            featureTypes.add(FeatureType.TABLES);
//            featureTypes.add(FeatureType.QUERIES);
//            featureTypes.add(FeatureType.SIGNATURES);


            AnalyzeDocumentRequest analyzeDocumentRequest = AnalyzeDocumentRequest.builder()
                    .featureTypes(featureTypes)
                    .document(myDoc)
                    .build();

            AnalyzeDocumentResponse analyzeDocument = textractClient.analyzeDocument(analyzeDocumentRequest);

            List<Block> docInfo = analyzeDocument.blocks();

            HashMap<String, Object> kvSets = new HashMap<>();


            for (Block block : docInfo) {
                if (block.blockType() == BlockType.KEY_VALUE_SET && block.entityTypes().contains(EntityType.KEY)) {

                    StringBuilder key = new StringBuilder();
                    StringBuilder val = new StringBuilder();

                    for (Relationship relationship : block.relationships()) {
                        // 通过 KeySet  的关系中的 CHILD 去找Key的的值
                        if (relationship.type() == RelationshipType.CHILD) {
                            List<String> ids = relationship.ids();
                            key.append(findKeyWord(docInfo, ids)).append(" ");
                        }
                        // 通过 KeySet 的关系中的 VALUE 去找 VALUE 的 block，在通过 VALUE 的 CHILD 去找值
                        if (relationship.type() == RelationshipType.VALUE) {
                            List<String> ids = relationship.ids();
                            for (String id : ids) {
                                val.append(findValueWord(docInfo, ids.get(0))).append(" ");
                            }

                        }
                    }
                    kvSets.put(key.toString(), val.toString());
                }
            }

            System.out.println(kvSets);


        } catch (TextractException e) {

            System.err.println(e.getMessage());
            System.exit(1);
        }
    }

    private static String findValueWord(List<Block> blocks, String keyId) {
        StringBuilder rtn = new StringBuilder();
        Optional<Block> valBlock = blocks.stream().filter(s -> s.blockType() == BlockType.KEY_VALUE_SET && keyId.equals(s.id())).findFirst();
        if (valBlock.isPresent()) {
             Block block = valBlock.get();
            for (Relationship relationship : block.relationships()) {
                // 通过 KeySet  的关系 儿子去找Key的的值
                if (relationship.type() == RelationshipType.CHILD) {
                    List<String> ids = relationship.ids();
                    rtn.append(findKeyWord(blocks, ids)).append(" ");
                }
            }
        }
        return rtn.toString();
    }

    private static String findKeyWord(List<Block> blocks, List<String> ids) {

        StringBuilder rtn = new StringBuilder();
        for (String id : ids) {
            List<Block> vBlocks = blocks.stream().filter(s -> s.blockType() == BlockType.WORD && id.equals(s.id())).collect(Collectors.toList());
            if (vBlocks.size() > 0) {
                rtn.append(vBlocks.get(0).text()).append(" ");
            }
        }
        return rtn.toString();
    }

}

```

---
参考：

Textract JAVA Demo <https://github.com/awsdocs/aws-doc-sdk-examples/tree/main/javav2/example_code/textract>

Python Extract KV Pairs <https://docs.aws.amazon.com/textract/latest/dg/examples-extract-kvp.html>
