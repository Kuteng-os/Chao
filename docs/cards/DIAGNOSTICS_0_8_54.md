# mechanics-36：本节覆盖旧提示中的限制

- 反制新增 counter_trigger: enemy_unit_attacked。敌方正式攻击友方单位、交战前触发；trigger_unit 是攻击者，attack_target 是被攻击者。可分别 destroy 两者，正常结算阵亡。不要改成部署反制，也不要要求玩家虚构能力来代替该时机。固定蓝图若仍选其他触发，提醒玩家改下拉框，不能偷偷改蓝图。
- 单位无条件 while_active 可对 all_friendly_units / all_enemy_units / all_units / adjacent_to_self 提供固定 modify_stats、modify_operation_cost、modify_stacks。modify_stats health_mode:max_only 仅增加上限、不治疗。场地及单位光环可用 grant_keyword，keyword_id 限 core.guard/core.blitz/core.fury/core.immune，必须填写正确 keyword_version 和 duration:battle。来源离场或抑制立即撤销；后续入场也生效。持续条件仍限不会自我反馈的战场数量，条件光环不增加防御。
- 场地 while_active 可使用 {op:unit_limit,player:owner/opponent/both,amount:1..9}。限制当前在场数量达到上限后继续部署或召唤；不消灭超额的既有单位。只在场地生效期间有效。
- {op:reshuffle_zones,player:owner/opponent/both,zones:[hand,discard,battlefield]} 将所选区域所有牌洗回各自牌库；总部、场地本身不在范围内，在场单位离场但不是阵亡，临时强化清除，永久强化保留。不用受 amount:1..3 限制的 transfer_card 假装全区域洗牌。
- transfer_card 增加可选 player:opponent（默认 owner；明确从哪一方卡池取，交由那一方选择并进入那一方区域）。增加 entry:deploy，仅允许 source:deck,mode:move,destination:support，免费部署、触发部署效果与部署反制；默认 entry:summon 仍为召唤。可以给双方各一条 selection:chosen,amount:1,filter:{kind:unit}。不要漏掉对手的选择或把部署当作召唤。
- 单位自身撤退/回手事件：own_unit_retreated/own_unit_returned 增加 event_scope:self；event_scope:other 排除自身。scope 缺省保持原监听语义。退前线回后援与退后援回手都能判断自身；回手的自身事件在离场前结算，临时强化随即清除。
- 解放：{op:liberate,target:self,token_id:本牌已定义的衍生单位}。原地改变卡面属性、行动费、词条与能力，替换为该模板；不触发部署/召唤/阵亡，不重置行动、压制、损伤。额外强化仍在，每次在场只可解放一次。返手、入牌库或复制时恢复待解放原形，永久强化照常保留。需要待解放/解放显示时，给衍生模板明确的解放名称。配置词条 abilities 中可写 when_condition+premise+liberate 或自身事件+liberate。形态放 card.tokens，不能只写没引用的属性；未指定形态属性继续提问，不能擅自设计。
- 动态额外打出费：card.cost_surcharge:[{premise:前提,amount:1..12}]，最多4档，匹配多档只取最大 amount。与现有固定费/减费合并，打出前显示并检查完整费用，不足不能打出。前提仅查询出牌前状态，不支持自身、目标或事件。己方回合序号 stat:friendly_turn_number，5回合起+1、8回合起+2可以两条 gte 前提。不能用结算后 lose_kredits 冒充额外费用门槛。已有蓝图的 cost_surcharge 必须保留。

复述写清玩家规则即可，卡面语言精简，技术限制和边界说明放提问/详细信息，不塞入正式机制。旧对话“不支持”不代表当前规则不可执行。
