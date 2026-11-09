# 0.8.43：牌库位置、按目标伤害与手选卡牌

本页优先于旧的“不支持”说明。原会话的澄清答案继续有效，未回答的具体意图仍需提问；不能把缺失细节当作缺失底层能力。

- 阵亡回手已支持：on_death 的 `transfer_card`，source:self、mode:move、destination:hand、selection:random、amount:1。手满默认烧毁；加 `overflow:"deck_top"` 则手满改放己方牌库顶。它取回准确的阵亡原卡，不是随机同名弃牌。也可 destination:deck 配 deck_position:top 或 bottom 或 random。牌库上限100，超限保留原区，不复制。临时在场状态不保留，永久强化保留。
- `transfer_card.selection:"chosen"` 可让玩家从自己的 deck、discard、hand、starting_deck 来源池选择符合 filter 的具体卡。例如阵亡从牌库召唤玉石阵营单位：source:deck、mode:move、destination:support、selection:chosen、amount:1、filter:{kind:"unit",faction_id:真实玉石阵营UUID}。不需要额外 ability.target。无候选或支援线满则不选择、不移出卡。候选仅本人可见。
- 单次伤害加成：`damage.bonuses:[{filter:{keyword_id:"core.guard"},amount:2}]` 对当前有守护的目标伤害+2；`filter:{unit_classes:["infantry"]}` 为步兵限定。与基础伤害合并成一个伤害包，再计算重甲等，不生成第二次伤害。filter可用卡名、名称包含、兵种、阵营、当前有效词条。
- **在“追加效果”模式增强已有固定伤害时**，不要重写固定 damage，也不要新增第二条 damage。在 card 顶层增加 `damage_bonuses:[{filter:{keyword_id:"core.guard"},amount:2}]`，card.abilities只含新的能力（没有则[]）。顶层修饰本卡所有效果伤害，不改变普通攻击伤害。例如已有“对全体敌军造成2伤害”，追加“对守护伤害+2”，应对守护一次造成4、其他一次造成2。若仅修改某条伤害，请澄清范围或用完整编辑模式。不得把这些能力误报为不支持。
- `damage.target:"all_units"` 一次对双方场上单位伤害，不含总部。群体目标快照，不把结算中新召唤的单位再次命中。
- 同组紧随最近 damage 后的 `if_killed:{per_unit:true,effects:[...]}` 按该次伤害直接消灭的单位数逐个执行子效果；省略per_unit只执行一次。例：damage(all_units,1)，if_killed(per_unit:true,[gain_hq_defense(owner,1)])；或子效果 summon(token_id,1)，统一召唤到己方支援线。只统计直接击杀，不计连锁阵亡或伤害前已死亡单位。不必用 repeat 预先猜存活单位数，也不必用 on_kill_summon（后者是死者所属方原位置替换）。满支援线不额外召唤。
- 手牌减费：`{"op":"modify_hand_cost","selection":"chosen","cost_delta":-1,"duration":"hand","filter":{"faction_id":"实际阵营UUID"}}`。所有类型牌可选，filter可限定kind/unit_class/card_name/name_contains/faction_id。selection可chosen/random/all，默认不应该改变玩家说的“选择”。duration:hand 离开手牌即失效（伏置反制仍视为隐藏手牌，触发或弃置后失效）；end_of_turn本回合且离手失效；match永久，离场再回手仍保留。可叠加，实付费用最低0。此操作独立于 modify_cards 的单位属性强化，也不需要 ability.target。
- 0费卡可以制作。生成输入与正式卡校验一致，不能强制制作者把0改成1。

简短描述示例：“阵亡：返回手牌；手牌满则置于牌库顶。”“对所有单位造成1点伤害，每击杀一个单位，己方总部防御+1。”“阵亡：选择一张元素阵营手牌，其留在手牌期间费用-1。”
