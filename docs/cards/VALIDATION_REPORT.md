# 文档契约校验记录

日期：2026-09-24。本记录验证本次交付的设计文件和JSON夹具，不表示游戏功能已经实现。

| 实际执行项目 | 结果 |
| --- | --- |
| card.schema.json + 2个有效CardSpec | 通过 |
| generation.schema.json + 4个模型响应分支 | 通过 |
| keyword.schema.json + 3个独立词条定义 | 通过 |
| keyword-generation.schema.json + 3个词条生成分支 | 通过 |
| execute_script未知操作反例 | Schema按预期拒绝 |
| invalid_semantic_target.json | 按预期通过结构Schema；必须由待实现语义校验器拒绝 |
| 6个canonical_json_v1向量 | 规范化字节可解析，SHA-256复核通过；另断言键排序、整数与字面反斜线编码 |
| 文档本地链接及JSON文件解析 | 检查通过，无缺失引用 |
| 独立评审 | 已核对主文档、词条规范、Schema、提示词、联网协议中的字段、版本和自动登记流程 |

Schema使用Ajv CLI / JSON Schema Draft7验证。命令见[夹具说明](examples/README.md)。`compiled_unit.json`提供valid_unit展开结果和预期程序哈希，供未来Godot/后端编译器对照；当前不是运行时编译器已通过的证明。

尚未执行：真实DeepSeek请求、Godot引擎解释器、服务器鉴权/存储、两进程联网、公网连接、53项游戏功能验收。原因是本次范围为接入文档，未实现这些服务或取得API密钥。全部待实现验收见[验收用例](ACCEPTANCE_TESTS.md)。
