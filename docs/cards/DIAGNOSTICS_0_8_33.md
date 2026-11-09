# 0.8.33 机制补充（优先于历史中的“不支持”结论）

## 名称筛选和去重计数
`{count_units:{side:"ally|enemy|any",row:"any|front|support",card_name:"精确名称",name_contains:"包含文字",unit_classes:["infantry"],distinct_by:"name"}}` 可用于 premise 比较，以及 damage/heal.amount、modify_stats.attack_delta/health_delta。除 side 外字段均可省略，多个筛选取交集；按冻结卡名匹配，不按显示换行。只统计仍存活的场上单位，排除总部、手牌和牌组。distinct_by:name 按卡名去重，不按兵种，不填则每个实例计数。数值在每条操作开始、修改目标之前读取一次，0 合法。卡名最长64字。
例如己方每种“集团军”使全体友军永久+1/+1：modify_stats,target:all_friendly_units,attack_delta:{count_units:{side:"ally",name_contains:"集团军",distinct_by:"name"}},health_delta:相同表达式,duration:match。这是当前场上目标的一次快照加成，不会自动作用于之后入场的单位。若玩家未明确是否包括未来单位，应继续询问。

## 按名称筛选一批效果目标
所有具有单位 target 的普通触发操作可加 `unit_filter:{name_contains:"集团军"}` 或 `{card_name:"第4集团军犀牛"}`；还可 unit_classes，多个字段取交集。与 target 的阵营/战线范围共同生效；随机目标先筛选再随机。无匹配则本操作无效果。不能筛选总部，暂不用于 while_active 光环。
使名称含集团军的所有友方单位获得1重甲：`{op:"modify_stacks",target:"all_friendly_units",unit_filter:{name_contains:"集团军"},stack:"heavy_armor",amount:1,duration:"battle"}`。duration 必须以玩家答案为准，示例不代替澄清。本回合指定名字单位免疫可用 grant_keyword,keyword_id:core.immune,keyword_version:1,duration:end_of_turn 加 unit_filter.card_name。需澄清是全部同名还是玩家选一个、准确名称，以及后续入场是否生效。

## 抉择：只执行一个分支
`{op:"choose_effect",options:[{label:"简短选项名",effects:[...操作]},{label:"另一项",effects:[...操作]}]}`。2—3项，每项1—6条叶操作，每个 on_play 效果组最多1次抉择，不嵌套。控制者在结算时选择且只执行该项。分支内仍按顺序执行，共用本卡 play_target 或本能力 target（选单位发生在选择分支前，不因选择分支改变目标范围）。不能用两个无条件能力组代替二选一。各分支和抉择包装均计入12操作预算；整体仍4能力、单组4顶层操作。分支可以抽牌、随机伤害、增益、生成等已支持操作。没有独立卡池，也不创建衍生卡。
例“伤害友方2并抽2 / 伤害友方2再随机伤害敌方5”：play_target:{side:"ally",row:"any"}，on_play一个choose_effect，两个分支分别 damage chosen2+draw owner2 和 damage chosen2+damage random_enemy_unit5。不执行另一项，不同时结算两项。

## 下一次部署
指令支持 next_own_unit_deployed：本指令结算后，等待下一次己方从手牌打出单位，仅结算一次，之后移除；对手部署、直接召唤不算。target:trigger_unit 指该次部署的单位。即时压制单位和下一次部署获得闪击应使用两个能力组 on_play + next_own_unit_deployed，后者 grant_keyword trigger_unit core.blitz@1。若目标已离场，授予失效但该次预留已消耗。无每回合重置、不自行生成单位。授予的持续时间仍应询问，不得默认永久。所有延迟组前提在事件开始时统一判定，不满足也消耗。

所有新能力均经过结构和权威引擎校验；已知条件不完整仍列 questions。formal_text 只复述玩家规则，missing_capabilities 只记录真实缺失；不能沿用历史的名称筛选、去重计数、二选一、下一次部署不支持结论。
