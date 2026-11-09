# mechanics-25：击杀后召唤（CZ-000074 / CZ-000075）

已有 damage 操作新增可选 on_kill_summon: token_id。这是此伤害操作直接击杀该目标时的结果，不是所有阵亡、其他来源击杀或本回合任意击杀。普通伤害没有此字段时行为完全不变。只允许单位目标；目标原本存活且本次伤害使其防御降至0才成功，免疫、0伤害、生成者已离场导致伤害0、非致命伤害、间接连锁击杀均不召唤。

成功时先移除死者并登记正常阵亡触发，然后在死者所属玩家、原战线、原位置召唤1个指定衍生单位；队列中的阵亡能力仍按现有效果组顺序处理。支援线4单位、前线5单位及前线占有规则仍适用，无位置时不召唤，不转移到另一阵线或另一玩家。召唤只触发 on_summon，不触发普通 on_play。每个此操作按2条操作计入静态预算，召唤计入运行预算。不得为凑预算删除玩家要求。

示例：{"op":"damage","target":"chosen","amount":{"unit_stat":{"target":"creator","stat":"attack"}},"on_kill_summon":"jinye"}。amount 读取生成本指令的单位当前攻击力，其离场时为0。jinye 必须是同一 tokens 库中的 unit；可由衍生指令引用，不要生成循环模板。

CZ-000075完整链可实现：本体指令on_play前提 friendly_unit_count>=1，选择友方单位destroy chosen，然后summon luser。luser每个own_turn_start create_card daoguan amount3；while_active modify_stats self attack_delta={count_units:{side:enemy,card_name:津液}},health_delta=0,duration=battle。daoguan使用上述damage+on_kill_summon，play_target={side:enemy,row:any}；jinye为0费1行动1/1单位。无友方目标时本体指令其他独立组仍正常，但该组前提不成立，不召唤luser。
