# 0.8.63 当前机制，优先于历史限制

- gain_kredits 可用 allow_overflow:true 获得超资源槽的本回合资源；不增加资源槽，不跨己方回合积累。省略时维持恢复资源且不超槽，已有超槽点数不会被普通恢复削减。例：“己方回合开始获得1点额外指挥点（可超槽）”使用 own_turn_start + gain_kredits amount=1 allow_overflow=true。
- 单位筛选、转移筛选和新增的事件/手牌/出牌历史条件支持 sin:null（仅无罪孽）、sins:[...]（任选其一）、exclude_sins:[...]（排除列出的罪孽，未排除null时包含无罪孽）。和谐的记忆：while_active + modify_stats target=adjacent_to_self unit_filter={exclude_sins:["envy"]}, attack_delta=2 health_delta=0 duration=battle。相邻只按本单位所在一方同阵线左右邻位，无需6组重复效果。
- 通用 own_card_played/enemy_card_played 监听从手牌打出并成功结算的单位、指令、场地（效果从牌库部署或召唤不算打牌）；反制伏置不触发，公开触发结算后计入。premise {test:"event_card",filter:{sins:["wrath","lust","sloth","gluttony","gloom","pride"]}} 查询本次事件牌，可用于 own_order_played 等卡牌事件。不使用 trigger_unit 读取指令。咖啡香的回忆可用一组 own_card_played + event_card 筛选六罪孽，依次随机友方+1攻（battle）、敌总部1伤害、随机敌方1伤害；若作者限定单位或指令，用 premise all 的类型条件过滤。
- 仅免疫战斗伤害：on_play 或 while_active，modify_incoming_damage target=self amount=0 damage_kind=combat immune=true duration=battle。主动交战与反击受到伤害均为0；仍受技能、指令伤害及消灭/移除。不用重甲100或减伤-100冒充免疫。0.9.4起重甲上限100、固定减伤-100～100；免疫与固定减伤仍不同。
- previous_card 保持 kind/player，新增 card_name 与 this_turn:true。例 {test:"previous_card",kind:"order",player:"owner",card_name:"赫",this_turn:true}。on_play 查询的是本卡之前一张牌；己方历史独立，跨回合不误判。默认不填this_turn的旧牌规则保持不变。
- premise hand_contains 或 played_this_turn：{test:"hand_contains",player:"owner",filter:{card_name:"苍"},min:1}；后者查询本回合已打出的牌。all组合可查询同时有/已用过苍和赫。choose_effect.options每项允许 premise，不满足的选项不出现；全部不满足则跳过。这个能力已经实现，不要继续报缺失；仍应向玩家确认未指定的触发时机和每回合次数。
- 【苍】和【赫】使用时检查另一张是否为己方本回合上一张指令：分别在衍生卡 on_play 能力加上述 previous_card 前提，create_card 引用既有【茈】token_id。嵌套引用同一张牌的衍生池已支持，不另造token_id。
- 新建衍生指令/反制 abilities:[] 仅可在机制理解阶段作为待填空槽；模型可填其abilities/play_target，但不能改其名称、费用、罪孽、数值、词条或图像。保存时仍要求完整能力。已有非空衍生效果在append模式只读，修改它们要选择effect_mode=replace。
- effect_mode=replace：可以返回本体与已有衍生卡修改后的完整 abilities/play_target；身份、数值、罪孽、词条等基础字段保留。card.tokens省略的已有模板原样保留，返回的已有token必须使用原token_id，严禁复制一个新ID规避。
- 开发 source=deck/starting_deck 时只用 filter；source=tokens 时只用 token_ids。after_attacked 的 chosen 目标必须包含能力 target(side,row,timing=trigger)。
