# 玩家基础配置与 AI 附加机制合同

更新：2026-09-24。本文件记录用户最新确定的制卡方式：**基础数值由玩家填写，普通牌选择已登记词条即可；DeepSeek 主要理解新词条或卡牌的附加效果。** 此流程优先于早期文档中“模型补齐基础数值”的默认交互；完整 CardSpec 与战斗规则没有改变。

## 两条入口

没有附加效果文本时，客户端将玩家表单组合为完整 CardSpec，调用 `POST /v1/card-drafts`，显示预览并等待玩家确认。普通牌加词条不需要语言模型。含模板词条的卡牌会在校验阶段展开，不能再手工复制相同能力造成双重执行。

有附加效果文本时，客户端调用 `POST /v1/card-generations`，在原有必填字段外增加 `card_blueprint`。`source_text` 只承载希望模型完善的机制要求；基础数值、兵种、既有词条不从该文本反推。

```json
{
  "request_id": "4d96cbee-a708-40f4-b6ce-92e4ded748f7",
  "editor_revision": 1,
  "source_text": "登场时抽1张牌。",
  "clarification_answers": [],
  "schema_version": "1.0.0",
  "ruleset_version": "frontline-1",
  "card_blueprint": {
    "kind": "unit",
    "unit_class": "artillery",
    "cost": 3,
    "operation_cost": 0,
    "attack": 2,
    "health": 1,
    "keywords": [{"id": "core.guard", "version": 1, "params": {}}],
    "name": "玩家命名的火炮"
  }
}
```

上面的 JSON 是 API 合同示意，不作为默认卡牌随游戏发放。

## Blueprint 字段

| 字段 | 类型与要求 |
| --- | --- |
| `kind` | 必填，`unit`、`order` 或 `counter` |
| `unit_class` | 必填，单位为 `infantry/tank/artillery/fighter/bomber`，指令为 `null` |
| `cost` | 必填，整数 1–12 |
| `operation_cost` | 必填，单位整数 0–4，指令固定 0 |
| `attack` | 必填，单位整数 0–20，指令固定 0 |
| `health` | 必填，单位整数 1–20，指令固定 0 |
| `keywords` | 必填，0–8 个已登记的 `{id,version,params}` 引用，不允许同 ID 重复；参数严格匹配固定版本 |
| `rarity` | 可选，standard/limited/special/elite；玩家填写，模型只读 |
| `counter_trigger` | 反制必填；enemy_unit_deployed/enemy_order_played/enemy_hq_attacked；模型只读 |
| `name` | 可选，非空时最多 32 个 Unicode 码点并冻结；省略、空字符串或全空白时由模型命名 |
| `abilities` | 可选，玩家已组合的固定能力，格式同 CardSpec；触发、目标、参数和执行顺序全部冻结 |
| `play_target` | 可选，固定选定目标阵营/战线；存在 chosen 时必须提供 |
| `tokens` | 可选，已使用的固定衍生单位，最多3种 |
| `effect_mode` | 可选，只支持 `append`，此模式必须包含 abilities 数组 |

拒绝未知字段、数字字符串、未登记词条与指令上的单位专用词条。客户端不能填写身份、哈希或可信标记。

## 参数化效果组合

“抽 X 张牌”使用 `{"op":"draw","player":"owner","amount":X}`，由界面填写 X，并选择 `on_play`、`own_turn_start`、`own_turn_end` 或 `on_death`。常用组合器还提供己方总部回复、敌方总部伤害和本回合指挥点。抽牌及指挥点范围 1–3，回复及伤害范围 1–10；指令只支持打出时的效果。

固定能力放入 `card_blueprint.abilities`，例如 `[{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":2},{"op":"heal","target":"own_hq","amount":3}]}]`。没有其他机制文本时直接编译预览，不调用模型。效果只是白名单规则数据，词条仍独立登记，模板词条可以组合这些效果并暴露参数。

每个能力最多 4 个效果，展开后总计最多 4 个能力、12 个效果。固定能力和已选模板先编译检查；支持依赖 `play_target` 的 `chosen` 和依赖 `tokens` 的 `summon`，必须同时提供合法依赖。网页组合器根据同一份 Schema 提供全部当前操作。

网页使用 `effect_mode=append`。模型返回的 `card.abilities` 只描述本次额外能力；适配层只恢复基础字段，业务层恰好追加一次固定能力。允许已有抽2张再追加抽1张，也保留有意重复的相同能力。不得在模型输出重复复制既有能力；玩家可以在生成后的表单中调整分组和顺序。固定能力组不被扁平化或自动合并。额外能力和模板展开共同受预算限制。

已有非空 `play_target` 不可被模型修改，全部登场 chosen 共用它；阵亡 chosen 使用各能力组的 target；新召唤只能增加不重名 token 或引用既有精确定义，冲突分别返回 `BLUEPRINT_TARGET_CONFLICT` / `BLUEPRINT_TOKEN_CONFLICT`。未指定 append 的旧请求仍使用完整去重/固定槽冲突校验，保持旧客户端兼容。

## 冻结、合并与澄清

服务端先验证 Blueprint，再创建任务；验证失败不会调用模型。模型上下文包含服务器保存的基础配置，提示词要求原样复制固定字段，不对已填写的基础数值追问。

模型返回 `ok` 时，适配层在结构校验前、业务层在编译前再次将基础字段写回候选。即使模型误写攻击 99，玩家填写的攻击 2 仍会成为最终定义。非空玩家名称也保留，外观兵种图标由固定牌种决定。

词条先保留玩家数组顺序，再追加模型从附加要求识别的已登记词条。完全相同引用只保留一次；同 ID 的版本或参数与玩家选择冲突时返回 `INVALID_KEYWORD_PARAMS`，不能覆盖玩家选择。新增命名词条仍走独立提案、澄清、玩家确认、自动登记流程。

附加效果里的伤害、抽牌、属性增减等数值独立于基础数值。例如基础攻击 2、机制要求“登场造成 4 点伤害”，最终必须保留攻击 2 与伤害 4，不能混用。存在 Blueprint 时不再用原文数字正则核对基础字段，只核对可确定的附加机制数值；正式规则文本仍从编译后的 DSL 渲染。

澄清回答通过 `parent_generation_id` 继承 Blueprint。后续请求不带该字段时自动继承；带该字段时规范化后的内容必须一致，否则返回 409 `REVISION_CONFLICT`。改变基础配置意味着新编辑意图，应取消旧任务并创建新根任务。独立词条批准后自动恢复卡牌也必须保留该 Blueprint 与原编辑修订。

`needs_clarification` 仅用于仍不清楚的机制、触发、目标或效果数量；`needs_keyword_registration`、`unsupported` 和 `ready` 的结构沿用原合同。`ready` 只创建未发布草稿，仍需玩家确认导入。

## 旧客户端兼容

`card_blueprint` 在 HTTP 层保持可选。缺少它时保留完整文本编译，但只执行保守的显式数值校验。兼容提取器按完整属性片段顺序处理 `3费部署0行动，攻击2防御1`，得到部署费 3、行动费 0、攻击 2、生命 1；开头“炮”可识别为 `artillery`。不能从零散重叠正则把后面的行动费误归到部署费。

新 UI 应发送 Blueprint，普通牌与既有词条应走不收费的直接预览入口；兼容路径不是继续让模型设计玩家基础数值的理由。

## 验证

后端测试覆盖原报错描述与前后缀/标点变体、基础数值冻结、模型遗漏守护的补回、词条冲突拒绝、技能数值不被基础数值覆盖、澄清继承以及词条批准后的自动恢复。默认使用模拟模型，无真实 API 费用。

反制蓝图允许在生成前暂时没有效果；最终必须展开出 on_reveal 能力。完整规则见 [卡牌类型与版本](COUNTERS_AND_VERSIONS.md)。
