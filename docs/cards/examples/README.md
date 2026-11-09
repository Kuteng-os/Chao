# 接口验证夹具

这些文件不是生产卡池；它们仅用于检验文档和未来实现。

| 文件 | 预期 |
| --- | --- |
| valid_unit.json | 通过 card.schema.json；登记三个测试词条后通过语义校验；补给展开一次 draw(owner,1) |
| valid_order.json | 通过结构与语义校验；打出前需要一个敌军单位目标 |
| invalid_unknown_op.json | 结构校验失败，不能执行 execute_script |
| invalid_semantic_target.json | 结构校验通过，语义失败：chosen 出现在非 on_play 且缺少 play_target |
| generation_ok.json | 通过 generation.schema.json，之后仍需卡牌语义校验 |
| generation_clarification.json | 返回问题，不允许导入卡牌 |
| generation_registration.json | 返回新词条登记需求，不允许导入卡牌 |
| generation_unsupported.json | 返回不支持，不允许导入卡牌 |
| keyword_generation_*.json | 独立词条生成的候选、澄清、需要扩展引擎三个分支 |
| keywords/core_blitz.json、core_guard.json | 独立基础词条定义夹具，正式登记仍由项目初始化流程审批 |
| keywords/example_supply.json | 参数化词条示例；不是模型自行批准的新词条 |
| canonical_vectors.json | canonical_json_v1 编码及 SHA-256 验证向量 |
| compiled_unit.json | valid_unit 的预期编译程序与SHA-256：模板只展开一次，突击保留为builtin |

所有 registry fixture 在测试设置中显式标为 approved；JSON 文件本身不包含“已批准”权限字段。每张牌的具体意图和业务权限还要由服务层验证。

Schema 验证（需 Node.js 与 npm，会下载 ajv-cli）：

```powershell
npx --yes --package ajv-cli ajv validate --spec=draft7 --strict=false -s docs/cards/card.schema.json -d docs/cards/examples/valid_unit.json
npx --yes --package ajv-cli ajv validate --spec=draft7 --strict=false -s docs/cards/generation.schema.json -r docs/cards/card.schema.json -d "docs/cards/examples/generation_*.json"
npx --yes --package ajv-cli ajv validate --spec=draft7 --strict=false -s docs/cards/keyword.schema.json -d "docs/cards/examples/keywords/*.json"
npx --yes --package ajv-cli ajv validate --spec=draft7 --strict=false -s docs/cards/keyword-generation.schema.json -r docs/cards/keyword.schema.json -d "docs/cards/examples/keyword_generation_*.json"
```

`--strict=false` 仅关闭 Ajv 对 schema 写法的额外 lint 限制，不允许未知数据字段，不替代语义验证，也不启用自动类型转换/默认值。反例应单独执行并断言失败，不能把无效样例与正例批量混用。此步骤只验证文档夹具，不能声称游戏运行时或真实 DeepSeek 已通过。
