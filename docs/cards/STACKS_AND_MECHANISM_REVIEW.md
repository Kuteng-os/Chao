# 数值词条与机制复述（0.8.4）

## 数值层数

当前支持的状态类型是 `heavy_armor`（重甲）。已登记的 `standard.heavy_armor@1` 是参数模板，引用时使用 `params:{"x":2}` 即获得重甲2，无需重复登记重甲1、重甲2等独立词条。

```json
{"trigger":"on_play","effects":[{"op":"modify_stacks","target":"self","stack":"heavy_armor","amount":2,"duration":"battle"}]}
```

- `modify_stacks` 增减层数，amount 为 -10…10，不能为0；`set_stacks` 设定层数，amount 为0…10，0表示清除。词条模板允许 `{"param":"x"}`，参数全集必须合法。
- 有效层数按施加顺序逐层计算，每一步限制在0…10。设置覆盖之前的结果；其后的加减继续叠加。减少到0后不会累积负债。10是本项目自定义规则的安全上限，不宣称是 KARDS 的原版上限。
- `battle` 持续本次在场期间；`end_of_turn` 在当前全局回合结束移除该层，按仍有效的层恢复结果。每个单位全部修正层合计最多64；超限整次行动回滚。
- 重甲在普通攻击与反击的伤害倍率计算后减伤，最低0；不会随受击消耗，不增加生命，不阻止直接消灭，也不减少指令或其他能力 `damage`。双方反击仍同时结算。
- 可对自身、选择、随机或群体单位生效；范围与现有单位目标一致。总部没有重甲。衍生单位可在召唤后成为层数效果的目标，其初始模板也支持已登记的重甲等参数词条，见 GENERATED_CARDS.md。
- 场上 `stacks.heavy_armor` 显示当前层数；存档和联网状态包含 `stack_layers`。统计事件 `armor_blocked` 记录减免的战斗伤害，归属于承受攻击的卡牌版本。
- 这不是任意自定义状态脚本：其他状态行为、按层数触发条件、按层数计算任意公式仍需要对应底层实现，模型必须明确指出。

## 先复述，再生成

网页中卡牌附加效果与新词条都先提交 `POST /v1/mechanism-reviews`。模型使用官方 `deepseek-flash`、`thinking.type=enabled`、`reasoning_effort=high`；只向玩家展示最终结构化复述，不保存或展示内部 reasoning_content。

初始请求包含 request_id、kind（card/keyword）、source_text；卡牌还包含固定 card_blueprint，词条包含 suggested_name。通过 `/v1/card-generations/{generation_id}` 轮询，结束状态为 `awaiting_confirmation`，result 包含 formal_text、questions、missing_capabilities、result_hash。本阶段不会创建卡牌草稿或登记词条。

玩家可以多轮修改。继续请求包含 kind、parent_generation_id、review_hash，及 feedback/answers；服务器保留原始文本、冻结配置、先前完整复述与玩家反馈。每轮最多3个问题、最多20轮、历史24KiB。问题未解决或包含缺失机制时不能确认。

确认后通过既有 card-generations / keyword-proposals 请求携带 `mechanism_review:{generation_id,result_hash}`，source_text 必须与当前正式复述一致；基础配置与词条名称必须与冻结值一致。所有权、哈希、前后轮次、取消状态及一次消费在同一事务中检查。旧复述不能确认；改变基础配置需要重新讨论。同一 request_id 重试不会重复计费或创建任务。

编译后仍执行完整 Schema、语义、预算与参数全集校验；卡牌由“保存”提交，词条由“确认并登记词条”提交。旧版本 API 的直接生成请求保留兼容性；新网页统一走复述流程。单轮调用最多两次、总截止240秒、单次180秒；页面等待270秒，并允许取消。部署时 GENERATION_DEADLINE_MS 应设置为240000。

## 兼容

旧卡牌与已登记词条的源定义、版本及编译哈希不变。新状态牌组要求双方客户端 build804；LAN 协议 frontline-lan-3。发布使用现有 Windows/Android 0.8.1 安装包及0.8.4签名累积资源补丁。

规则参考：[KARDS 官方重甲说明](https://support.kards.com/hc/en-us/articles/360026532571-Unit-ability-Heavy-Armor)。思考参数参考：[DeepSeek 官方文档](https://api-docs.deepseek.com/guides/thinking_mode/)。
