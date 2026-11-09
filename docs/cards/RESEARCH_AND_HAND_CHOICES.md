# 研发、开发与手牌选择（mechanics-19）

本节覆盖旧摘要中的“仅随机弃牌”“最多3个衍生模板”等旧限制。每张牌最多12个衍生模板，主体与全部模板合计仍最多48条操作、32 KiB展开程序。不可生成或执行任意代码。

## 弃牌及同名强化

`discard` 原有字段不变，可加 `selection:"random"|"chosen"`（缺省random）及 `filter`。filter支持 card_name准确名称、name_contains名称包含文字、kind、unit_class；组合为交集。不支持正则。chosen由被弃牌的手牌持有者选择，不是施法者查看对手手牌。随机和选择都包含伏置但仍计入手牌的反制。没有符合条件的牌则不弃；后续独立抽牌仍执行。

示例，以下两个操作必须在同一个效果组中按顺序出现：

```json
[
  {"op":"discard","player":"owner","amount":1,"selection":"chosen","filter":{"kind":"unit","name_contains":"集团军"}},
  {"op":"modify_cards","player":"owner","zones":["battlefield","hand","deck"],"filter":{"same_as_discarded":true},"attack_delta":2,"health_delta":2,"operation_cost_delta":-1,"duration":"match","grant_abilities":[{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]}
]
```

本组最近一次**成功弃置一张**的原卡名称作为 same_as_discarded 参照；不是模糊匹配，不跨效果组记忆，不会把被弃牌本身从弃牌区取回。没有弃成功，依赖同名的强化不执行。随机弃一张同样可作为参照，不能把选择弃牌擅自改随机。

modify_cards仅用于单位，player可owner/opponent/both；zones可battlefield/hand/deck组合；filter还可准确卡名、名称包含、兵种。属性变化为攻击/防御-5..5、行动费用-4..4。duration=match永久保留本场对局，包括返手再部署；duration=battle在本次或下一次在场期间生效，离场消失。不会修改卡库定义。范围与持续时间不明时应提问，不擅自填永久或双方。

grant_abilities可追加最多2个能力，trigger支持on_play/on_death/own_turn_start/own_turn_end，效果为有界的draw/damage/heal/gain_kredits/gain_hq_defense/modify_stats/modify_operation_cost/pin/suppress/repair。效果内不选择新目标、不引用衍生模板，不递归授予能力。单位最多16条附加能力。部署抽牌仅下次真正从手牌部署触发，不在获得能力时或直接召唤时立即抽。

## 分阶段研发

`{"op":"research","token_ids":["reward_a","research_stage_2"]}`：展示2至3张指定衍生卡，由控制者选一张加入手牌，其他不获得。下一阶段本身是指令衍生卡，使用时再research其成果或更高阶段。各阶段费用由制作者填写；选择不会自动打出候选牌，也不会额外扣候选费用。衍生模板可含指令、反制、场地或单位，通常generated_only不得主动入组。每次只能取得所选一个结果，支付下一阶段费用发生在之后使用它时。全链条模板放在根卡tokens中，引用准确token_id。

## 三选一开发

`{"op":"develop","source":"tokens","token_ids":["result_a","result_b","result_c","result_d"]}` 从指定衍生卡池无放回随机展示最多3个候选，选一张加入手牌。或者 `{"op":"develop","source":"starting_deck","filter":{"kind":"unit"}}` 从本场己方起始牌组的冻结版本去重卡池开发，不消耗实际牌组中的原牌；同名去重。不能把该池说成全服务器卡库。无候选无效果、不足3种展示实际数量，1种仍可确认。手牌满按既有烧牌规则。研发与开发对手仅知道正在选择，不知道候选与选择结果；卡牌正常打出后才公开。

## 显示语义

on_play是通用“从手牌打出后”时机，单位文案“部署时”，指令“使用时”，场地“生效时”；反制on_reveal“触发时”。指令没有进入单位阵线的部署步骤。机制复述、提问与卡牌描述须按卡牌种类区分，不要让玩家误以为指令部署成单位。已有on_play数据无需迁移。
