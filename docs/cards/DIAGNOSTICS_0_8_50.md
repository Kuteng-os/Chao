# 0.8.50 规则增补（优先于历史能力说明）

以下均为已支持的白名单，不得再次报告为底层缺失。仍需询问真正缺少的目标、持续时间等，不能擅自补写玩家没给出的规则。

- 老兵是预设形态替换，不是普通加攻防。单位主定义增加 `veteran:{token_id:"veteran"}`，引用本卡 tokens 中的单位。形态可以有独立攻防、行动费、词条、能力、卡图与音效。升级条件用普通触发器＋premise，结果为 `{op:"become_veteran",target:"self"}`。指令可用 chosen 等目标直接晋升；没有老兵形态、已经是老兵时无事发生。
- 例如进入前线后升级：`{trigger:"after_move",premise:{test:"unit_state",target:"self",state:"in_front"},effects:[{op:"become_veteran",target:"self"}]}`。攻击后用 after_attack；消灭单位后用 after_attack + compare source_destroyed_count > 0。己方回合开始位于前线用 own_turn_start + in_front。支持 `unit_state` 的 is_veteran/in_front/in_support；单位筛选和计数支持 `is_veteran:true/false`。
- 升级是原位置、原实例换形态。按新形态重置攻防、伤害、词条和附加强化（包括永久强化），不再触发登场/召唤/阵亡，不刷新已用攻击次数或移动状态。新形态可使用 on_veteran；其他单位和总部可监听 own_unit_became_veteran/enemy_unit_became_veteran。老兵返回手牌时还原升级前的原卡形态，可再次满足条件升级；不会恢复升级时清除的旧强化，升级后新获得的永久强化仍可随回手保留。该规则是本项目的明确行为。
- 主动攻击前 `on_attack`，结算后 `after_attack`；`attack_target` 为本次被攻击的单位。伤害后单位还在场才能影响它，离场不重新选目标；读取其本次战斗快照可使用 `{unit_stat:{target:"attack_target",stat:"attack"或"health"或"base_attack"或"base_health"}}`。数值在对应效果执行时读取，不可把它误写成来源数值。
- 可用 `{op:"set_attack",target:"all_friendly_units",value:{unit_stat:{target:"effect_target",stat:"health"}},duration:"battle"}` 将每个单位的攻击分别设为其当前防御；先写防御增加效果，再写 set_attack，即为一次性锁定。它不是持续光环。
- 单位组 `unit_filter`、play_target、效果组target以及 count_units 可按 row、keyword_id、attack/health:{cmp,value}、attack_parity:even/odd、is_veteran 筛选。count_units 还可用 adjacent_to:self/chosen；相邻判定遵循当前阵线顺序，总部会隔开两侧单位。例如友方守护存在：count_units:{side:"ally",keyword_id:"core.guard"} > 0。
- 多数单位群体操作支持 all_units；双方防御少于2：target:all_units,unit_filter:{health:{cmp:"lt",value:2}}。撤退前线敌军：retreat all_enemy_units + unit_filter:{row:"front"}。
- `source_destroyed_count` 是来源卡在本次行动中实际消灭的单位数量（不会把已死亡单位、其他卡的击杀计算进来）。可用于 on_play、after_attack、after_action 的后续效果组 compare 前提。不要把它写在先行消灭操作所在组的 premise：应先消灭，再在后续组判断数量。
- 阵亡前提 `{test:"destroyed_by",unit_classes:["infantry","tank","artillery"]}` 为被陆军消灭，空军为 fighter/bomber；无单位来源的消灭不符合这两种条件。击杀者即使同时阵亡也有快照。
- 可附加 `{op:"grant_ability",target:"chosen",ability:{trigger:"after_attack",effects:[{op:"gain_hq_defense",player:"owner",amount:3}]},duration:"battle"}`。持续时间可 battle/end_of_turn/match；match 会随永久强化复制。不能将“总部恢复”擅自改为“增加总部最大防御”，先澄清。
- `take_control` 支持目标单位，duration 可 end_of_turn/next_own_turn_start/battle；转入新控制者支援阵线，保留该单位伤害，入场当回合通常不能立即行动。临时控制到期返回原控制者，满支援阵线时返回其手牌。
- 本回合每次入场抽牌：on_play effects 中使用 `{op:"schedule",trigger:"next_own_unit_entered",repeat:"each_event",lifetime:"turn",effects:[{op:"draw",player:"owner",amount:1}]}`。入场包含部署、召唤、复活、控制权转入；仅部署用 next_own_unit_deployed。本回合每次友方攻击敌方总部抽牌用 next_own_unit_attacked_hq。each_event 可按 times 限制；lifetime:turn 在当前回合结束时到期。
- 单位/总部在场监听有 own_unit_entered/enemy_unit_entered 和 own_unit_attacked_hq/enemy_unit_attacked_hq。入场不由刚入场者自己监听；用 on_play/on_summon 实现自身入场。
- 事件能力支持 limit + limit_scope:turn（每回合上限），默认为 battle（本次在场总上限）。例如 enemy_unit_died,limit:1,limit_scope:turn 可实现每回合一次亡语监听。
- 手牌可以移动回牌库：transfer_card source:hand,destination:deck,mode:move,selection:chosen,amount:1。是真实移动不是复制，然后再写 draw amount:5。draw 固定数值范围现为1—10。
- choose_effect 的各分支可使用同一个 play_target。只要任一分支使用 chosen，卡牌应保留 play_target；不能因为主效果无需目标而删除它。若没有合法目标，仅跳过依赖目标的操作，其余效果继续。

描述用精简主句；不要把实现边界、重复的时限解释堆到卡面。老兵卡的主句可写“进入前线后，升为老兵。”新形态内容由形态预览承担。不可输出未确认的新词条、自定义脚本或任意代码。
