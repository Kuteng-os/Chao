# 当前能力补充（0.8.34）

本节是当前能力，优先于旧版“不支持按名称计数/重复/指令减费”的说明。

## 按数量逐次结算

能力组可带 `repeat`，为 1—16 的整数，或 `{ "count_units": { "side":"ally", "card_name":"第4集团军“兔子”" } }`。沿用 count_units 的 side（ally/enemy/any）、row、unit_classes、card_name、name_contains、distinct_by:name。

例：`{"trigger":"on_play","repeat":{"count_units":{"side":"ally","card_name":"第4集团军“兔子”"}},"effects":[{"op":"damage","target":"all_enemy_units","amount":1},{"op":"damage","target":"enemy_hq","amount":1}]}`。

组开始、选择目标后统计并锁定次数，0 次不执行。每次依次执行整个 effects，伤害是独立的一次；每次仍单独计算对应的伤害减免和免疫（重甲沿用仅战斗伤害生效的规则），完整一组后处理阵亡及受伤触发，再进入下一次。随机目标每次重选，chosen 沿用同一个实例，离场后不换目标。中途单位数量改变不改变已锁定的次数；对局结束立即停止。持续光环 while_active 不允许 repeat。重复结算受每行动 256 操作预算限制。

必须澄清计数哪一方、准确卡名、“所有敌方目标”是否含总部，以及逐次伤害还是合并伤害。多个单位各造成一次伤害不能改写成一次总伤害。

## 本卡动态减费

卡牌及衍生卡定义顶层可带 `cost_reduction:{"per_unit":{"side":"ally","card_name":"第4集团军“兔子”"},"amount":2}`。per_unit 是上面相同的单位计数选择器；amount 为每个符合单位减少的费用，1—12。

基础 cost 必须保留玩家填写的值。手牌实时显示 `max(0,cost-计数×amount)`；打出前按当前场面计算并扣费，然后才结算出牌效果。该减费只影响本卡打出费用，不改行动费用，不增加资源，也不永久改变基础 cost。反制伏置时核对当前费用，触发时重新计算并扣费。场上符合条件的单位消失后费用恢复。

例：7 费指令对一个敌方单位造成 6 点伤害，每个友方【兔子】减 2 费：保留 cost:7，添加上述 cost_reduction、play_target:{side:"enemy",row:"any"}，on_play damage chosen amount:6。不要用 gain_kredits 或 modify_operation_cost 代替。

蓝图已有 cost_reduction 时必须原样保留，缺失时可以为本次机制新增。明确费用指的是打出费用、统计哪一方、准确卡名，仍未明确的内容继续对话，不擅自选择。

CZ-000068、CZ-000069 的 RATE_LIMITED 是制卡额度限制，与卡牌机制是否支持无关。不能将调用额度用尽解释成机制不支持。默认每账号每天 500 次上游尝试，每分钟 5 轮，单轮最多 2 次，按北京时间零点恢复；部署可用 MODEL_DAILY_LIMIT 配置。
