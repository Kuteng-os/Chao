# 当前机制补充：0.8.61 / mechanics-42

本文件覆盖旧版本提示中的同项限制。重新审查历史对话时，依据当前能力判断；不能复用历史中“暂不支持”的结论。复述只写玩家的机制，缺失信息放入 questions，不自行决定取整、持续时间或替换已有能力。

- compare 增加 right_offset（-100..100）：先计算左右值，再将偏移加在右侧比较。例如己方总部至少比敌方高8防御：`{test:"compare",left:{stat:"friendly_hq_health"},cmp:"gte",right:{stat:"enemy_hq_health"},right_offset:8}`。
- 单位筛选、count_units、unit_matches 支持 is_liberated:true/false（是否已经解放）、without_keyword（当前不具有某内置词条）、generated_by:"salvage"（通过缴获得到的牌）。解放和老兵是独立状态，不能相互代替。缴获来源过滤可用于 ability.premise 判断 trigger_unit，不要同时给 self_and_trigger 的自身也加来源限制。
- 青春岁月：按忧郁筛选的坦克检索及依次牌库→弃牌→手牌回退已支持；transfer_card 用 filter.sin:"gloom"、unit_class:"tank"、fallback_sources:["discard","hand"]。指令结束后整局继续监听部署使用 schedule，trigger:"next_own_unit_deployed",repeat:"each_event",lifetime:"match"。其内层 trigger_unit 指未来部署单位，不是现在使用指令的单位。不能再报“指令没有触发单位”。
- 上述 schedule 可添加 once_per_card:"tank_defense"（1..48字符，仅字母数字下划线）。同一来源卡、同一玩家、同一标识对同一张实际卡整局最多执行一次；返手重下保持标记，新复制卡另算；多次打出相同来源牌不重复强化同一张卡。仅在内层目标通过筛选时记账。是否需要此限制必须遵从玩家。
- while_active 的 modify_incoming_damage 可作用 all_friendly_units/all_enemy_units/all_units/own_hq/enemy_hq。amount 为固定整数，damage_kind:combat/effect/both，duration:battle；source_kind 可选 unit/order/counter/field/hq，source_side 可选 ally/enemy/any（相对光环控制者）。多个光环相加，来源离场或抑制立即撤销。固定兵种、罪孽、卡名等筛选可用，不可用攻防、当前词条等会造成反馈的筛选。
- all_other_friendly_units 排除来源自身。self_and_trigger 是自身与触发单位的集合，相同实例只执行一次。
- after_attacked 在普通攻击整次交战后触发，即使受到0伤害也触发；必须存活，反击不另计“被攻击”。own_unit_moved/enemy_unit_moved 在主动推进前线完成后触发，含来源自身，可用 event_scope:self/other；trigger_unit 是移动单位。after_move 仍只监听自身。
- on_kill：在场来源单位消灭敌方单位后触发，包含主动攻击、反击和自身造成的效果伤害；同归于尽的来源不能继续在场触发。trigger_unit_snapshot/event_card 是被消灭者。`{op:"transfer_card",source:"event_card",destination:"hand",mode:"copy",selection:"top",amount:1}` 可复制死者入手，保留其永久强化。event_card 只支持 copy，并仅用于 on_kill/own_unit_died/enemy_unit_died。
- `{op:"become_trigger_unit",target:"self",inherit:"none"|"permanent"}` 仅在 on_kill 使用：原位置变为死者卡面形态，保留控制者，不继承死者临时强化；permanent 额外保留变化者自身永久强化。不是把死者转化，也不复制死者的损伤/行动次数。
- set_combat_damage_multiplier 可选 attack_base:"opponent"：与单位交战时基数取对方当前攻击，对总部仍取自身；再应用已有 attack_delta、multiplier/divisor/rounding。applies_to:"both" 覆盖主动攻击和反击；不改面板。分母>1仍必须明确向上/向下取整，不能猜测。
- 本回合阵亡计数可引用 enemy_deaths_this_turn/friendly_deaths_this_turn。卡面可加 `cost_override:{premise:合法条件,value:0..12}`；满足时最后覆盖实际打出费用，条件失去即恢复其他费用规则。没有把暂时0费永久写入卡牌。
- 单位能力可选 zone:"hand"，仅允许 own_unit_died/enemy_unit_died，效果仅限 modify_hand_cost selection:"self"。只修改这张手牌，不监听伏置反制。场上能力仍是默认 zone:"battlefield"，可另组改变自身行动费。不同区域不能混成一个效果组。
- modify_hand_cost selection:"drawn" 只影响同一效果组这次实际抽入手牌的实例，结合 draw.filter.kind:"counter" 可实现“抽2张反制，这次抽到的费用-1”；不会修改旧手牌、烧毁的牌或下一次抽牌。
- develop source:"deck" 从当前实际牌库抽取最多3种符合筛选的候选，选择后将该张原牌移入手牌；另外候选不离开牌库。source:"starting_deck" 则继续生成起始牌组样本的复制，不能混用。
- choose_effect 不再仅限 on_play，可用于 when_condition 解放后抉择、其他受支持触发时机；每组最多一个，不用于 while_active。先解放再选关键词仍作用于同一单位。
- temporarily_remove 的 return_when 支持 next_own_turn_start/next_opponent_turn_start/next_own_turn_end/next_opponent_turn_end，after_turns:1..99。own/opponent 相对于施放者，当前回合不算后续回合。reset:none 默认完整保留；temporary 清除临时强化、恢复原生规则和永久强化，保留受伤与行动次数；temporary_and_damage 另清损伤。均不触发再次部署。归還到手牌仍按返手规则处理。
- modify_stats health_mode:"max_only" 的 health_delta 可为负但不能为0；只改上限，当前防御不会超过新上限。
- core.order_untargetable@1（指令不可指定）：仅不能被双方指令指定，单位技能与普通攻击仍可指定；范围/随机效果正常。core.untargetable 仍同时防指令和技能。
- 同阵线战斗机保护其他单位及总部不受轰炸机普通攻击；战斗机自己可被轰炸机攻击。core.ignore_fighter_cover@1（突破空防）允许轰炸机绕过该保护；不忽略费用、部署等待、压制或烟幕。
- user.card_template_catalog 为被提到的已登记卡牌及其冻结衍生模板。需要生成已有【偶遇】等卡时，直接引用其中准确 token_id。服务端填入冻结定义，不能发明同名卡效果、改写模板，不能将卡名当关键词。模板总数仍最多12。没有匹配或有同名多个作者/版本时，先询问具体对象。

既有效果是固定配置；“把已有抽1改成抽坦克”不能在 append 模式暗中叠加。需先在编辑器删改原组，再添加新组。未明确的最多选择N个单位、烟幕消失等机制不得冒充已经实现。
