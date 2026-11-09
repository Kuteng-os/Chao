# 0.8.27 组合规则补充（优先于旧版限制）

卡牌、衍生卡、词条名称最多64字符；名称显示两行，保留最小字号。
duration:battle = 本次在场期间，离场清除，绝不是本场对局。end_of_turn = 当前回合结束。match = 永久：随同一张牌保留整场对局，返回手牌、入牌组、进弃牌区再入场都保留；不跨局，不改变原始卡库定义。复制卡牌保留原定义版本并继承已有永久属性层及永久附加能力，不继承本次在场/本回合效果、伤害或行动历史；抑制仍主动清除包括永久加成在内的增益层。永久可用于已有所有带duration的触发操作；while_active仍只允许battle。

兵种前提：compare的left/right支持 {count_units:{side:"ally"|"enemy"|"any",row?:"any"|"front"|"support",unit_classes?:["infantry","tank","artillery","fighter","bomber"]}}。数组为并集，side/row/兵种为交集；仅统计存活在场单位，不含总部。空军=fighter+bomber；陆军=infantry+tank+artillery；有某兵种用gte1，没有用eq0，可all/any/not组合，也可比较双方不同兵种数量。五种兵种逐一可用；单位持续攻击条件也允许此计数。不要误报“有空军/坦克”无法实现。

play_target和能力组target都可加unit_classes数组，指定可选择兵种，可在指令、部署、阵亡选择和其他已有选择时机使用。不得同时include_hq:true。例如仅指定敌方坦克：play_target:{side:"enemy",row:"any",unit_classes:["tank"]}，效果target:chosen。

相邻效果目标adjacent_to_self或adjacent_to_chosen，指同一阵线中心单位左右紧邻的单位，不包括中心和总部，不跨过总部、不跨阵线。adjacent_to_chosen与chosen一样需要play_target/能力组target，并继承部署时绑定或触发时选择；中心先离场则失效，不重新选。adjacent_to_self仅来源单位可用；阵亡按离场时左右邻居。伤害、治疗、增益、重甲、消灭等群体操作均可使用。单位while_active可用adjacent_to_self的固定攻防、行动费、重甲；附带条件的光环不允许改防御，以免循环。邻居移动或来源离场立即撤销光环。

复述要求：用简明卡牌语言，把同一时机合并成一段，避免反复“然后”“本局游戏”。不要为精简改动程序的操作顺序、重新判定条件的时点、目标、倍率或期限。有顺序依赖仍标明“随后”；对多个条件逐组判定，不假称互斥或一次性快照。永久必须明确，不与在场期间混淆。

登场共用目标优先使用play_target，包括指定兵种的指令；Blueprint的play_target:null表示尚未设置，不是禁止新增目标。只有原值非空才必须原样保留。玩家要求“使用时先选择，随后判定条件”时，不能改为有条件才弹出能力组target选择。
若同一个效果同时作用于“所选单位及其相邻单位”，使用 target:chosen_and_adjacent，目标名单在该操作开始时一次锁定，同一操作全部目标结算后才清理死亡。不要拆成先杀死中心再查询邻居的两条操作，否则中心离场会使邻接目标失效。chosen_and_adjacent和chosen共用选择规则、兵种只筛中心，左右邻居不额外筛兵种。
