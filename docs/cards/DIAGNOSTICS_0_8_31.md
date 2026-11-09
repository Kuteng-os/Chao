# 最新能力 mechanics-20（优先于旧提示与历史报错）

这些能力已可编译和运行，不能继续报告为缺失；以下语义不明确时仍应提问，不擅自设计。

## 交战先手
`{op:"set_combat_priority",target:"self",applies_to:"both",duration:"battle"}` 放在 on_play。applies_to 为 attack/retaliation/both，可选任意单位目标和 battle/end_of_turn/match。
先手先结算普通战斗伤害，重甲、免疫、倍率照常；对方若被击杀，不结算其战斗伤害。主动攻击、被攻击、fight 都适用。双方都有先手（含有效伏击）则普通同时交战。不会强迫本来不能反击的轰炸机、被冲击者等反击，不增加攻击次数，也不是额外效果伤害。召唤时同样初始化无条件、自身、battle 的该规则。

## 主动行动后
单位 trigger 可用 after_attack、after_move、after_action。成功完成有偿主动攻击、移动后，若自身仍在场则触发；反击、被取消的攻击、fight 强制交战、部署、被迫移动不算。after_action 是两种的并集，只触发一次。
例如 after_action + `{op:"modify_operation_cost",target:"self",cost_delta:2,duration:"battle"}`。本次先付旧费用，下一次用新费用，运行时行动费允许0..12；卡面基础费用仍0..4。持续到本次离场、本回合、整场对局必须按玩家明确回答决定，不明确时提问。limit 可设1..9，计数沿用本次在场。

## 阵亡监听
own_unit_died / enemy_unit_died 监听相应阵营单位阵亡；单位或场地可用。不是自身 on_death 的替代。包括召唤单位，移除、返回手牌、抑制不算。own_unit_died 包括自身（若需“其他友方”请先澄清，目前没有排除自身开关）。同批死亡时，所有原本在场的监听者先锁定事件，之后结算，因此同时阵亡仍触发。抑制者不触发。可配抽牌、gain_kredits 等普通结果。阵亡单位已离场，不能作为 trigger_unit 的仍存活目标或属性查询；event_card 可供事件卡筛选。

## 多兵种身份
`{op:"grant_unit_class",target:"self",unit_class:"fighter",duration:"battle"}` 放 on_play，表示“也算战斗机”。原兵种仍保留；只增加兵种筛选、单位计数与针对兵种的伤害修正身份，移动/攻击距离/能否反击仍按卡面主兵种。群体计数每单位至多一次。召唤也初始化；抑制移除，match 可随返手保留。无条件自身 battle/match 的身份也用于手牌、牌组筛选。可用于任意单位目标。

## 易伤和指令选中奖励
`{op:"modify_incoming_damage",target:"chosen",amount:2,damage_kind:"both",duration:"end_of_turn"}`：combat/effect/both，-10..10非零，多个变化相加。战斗伤害先倍率与取整，再加减易伤，再减重甲；免疫仍为0。零伤害不会因易伤变成伤害。不改变攻击力。
`{op:"grant_order_target_reward",target:"chosen",amount:1,duration:"end_of_turn"}`：挂上标记，此后标记控制者的指令正式选中该目标时，给标记控制者1..3指挥点，仍受资源槽上限限制。每条标记对同一指令同一目标最多一次；本指令不触发自己刚挂的标记；攻击、鼠标悬停、群体/随机效果不算。被反制取消的指令不触发。目标离场失效，match 标记随返手保留。
这两种操作支持单位或总部（play_target include_hq:true,row:any）；可用 own_hq/enemy_hq。目标阵营和是否含总部、伤害范围仍需玩家指定。战术集火作者已确认奖励仅限指令选中，不包括攻击。

## 衍生卡
本牌 tokens 可以保存尚未被效果引用的模板，仍会列入衍生卡库，默认不能加入牌组。不得为了通过校验擅自增加召唤或生成效果。未知 token_id、重复 ID、非法数值及执行预算继续拒绝。自引用/互相引用的合法模板可编译，运行执行预算防止无限循环。
