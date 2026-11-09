# 0.8.51 规则增补（优先于旧说明）

以下能力已实现。理解、复述、补充提问、生成和有限修复均应使用这些规则，不要再将其报告为底层缺失。玩家尚未指定的选择、触发次数和持续时间仍需澄清。

- 本体及每个衍生模板最多8个能力组、24个操作，本体与全部衍生合计96操作。普通组最多4个操作，抉择分支最多6个操作；全部分支都计预算。不能为省组数改变结算顺序。
- 单位筛选（unit_filter、play_target、能力target、count_units）可用 sin（七种罪孽ID）、cost:{cmp,value}；kind:"unit"可省略。`unit_matches` 查询 self/chosen/trigger_unit/attack_target 是否符合 filter；`unit_side` 查询单位所属 ally/enemy。例如先移除chosen，再在下一组以 `{test:"unit_side",target:"chosen",side:"ally"}` 判断其原归属并抽2牌；离场目标的身份来自本次选择快照。
- 随机敌方目标含总部用 damage/heal target:random_enemy_target；友方用 random_friendly_target。仅单位仍用 random_enemy_unit/random_friendly_unit，不能混淆。
- 反制 on_reveal 可用 trigger_and_adjacent 或 adjacent_to_trigger 指向触发单位与相邻单位；若反制需要玩家另选目标，配置能力target:{side,row,timing:"trigger"}及chosen。enemy_order_played没有触发单位，不能使用依赖触发单位的目标。
- 逐目标数值可写 `{unit_stat:{target:"effect_target",stat:"attack"}}`；stat也可 health/base_attack/base_health/operation_cost/cost/max_health。用于damage/heal/modify_stats/modify_stacks/set_stacks，每个目标独立读取。damage的max_amount为统一上限，caps:[{filter:{unit_classes:["fighter","bomber"]},amount:1}]为分类上限；先算数值与加伤，再取上限，然后结算防护。例如各目标承受自身攻击力伤害，最多2点、空军最多1点。
- 攻击后前提可用 `{test:"unit_matches",target:"attack_target",filter:{unit_classes:["fighter","bomber"]}}`，目标同时阵亡仍可读取本次攻击快照。`set_combat_damage_multiplier` 除against/applies_to/multiplier/duration外，可带target_filter（如keyword_id:"core.guard"）或target_attack_compare:"gt"，以及attack_delta/bonus_damage。target_attack_compare比较本次交战前双方当前攻击；applies_to:"attack"仅主动攻击，both包含反击。
- 在场监听新增own_unit_attacked/enemy_unit_attacked、own_unit_retreated/enemy_unit_retreated、own_unit_returned/enemy_unit_returned。攻击后包含监听者自身；撤退指retreat，普通return_to_hand只触发returned。在场事件可用occurrence指定第几次符合条件（1—999），配合limit_scope:"turn"时须同时有limit。第1次坦克部署抽牌、第2次自身强化可用两个组，同样的trigger_unit兵种前提，各填occurrence:1或2。不是限制最多发生1次/2次。
- 受到伤害后on_damaged，可用 `{stat:"event_damage"}` 获取本次实际损失防御，作为modify_stats或heal的数值。不会把过量伤害算入实际损失。
- `trigger_death target:chosen` 等：不消灭单位，执行目标当前的阵亡效果。`trigger_evolution`：立即执行该目标本次已安排的自身transform，形态来自该目标自己的模板，消耗对应延迟任务；没有已安排进化则跳过。不得猜测任意卡名为升级形态。
- `temporarily_remove`：target，return_when:"end_of_turn"，destination:"original_position"，暂时移除并于本回合结束回原位，保留伤害和已用行动。若原阵线不可容纳则回支援阵线，再满则回手牌。或return_when:"source_leaves",destination:"hand",return_cost:0，由一个仍在场的单位拘留目标，来源任何方式离场时归还；return_cost仅返手适用。不是阵亡、不会触发亡语。on_leave用于单位任何离场，每次离场一次，不填limit/occurrence。
- `transfer_card source:"hand",destination:"support",mode:"move"` 可从手牌召唤，真正移走那张手牌。按准确名称筛选用filter.card_name。`summon_origin amount:1` 用于衍生单位，召唤其最初母卡原型；母卡图/音效与原定义保留，默认不继承临时强化。
- 复用进化词条时，parameters可登记form:{type:"token"}，模板transform.token_id写{param:"form"}。每张卡引用词条时params.form必须填写本卡tokens已有的准确token_id，界面可选形态；不能输出不存在的同名模板。数值参数仍是integer及minimum/maximum。不支持任意脚本或任意能力参数。
- choose_effect.options每项可有独立target:{side,row,unit_classes...}，该项effects使用chosen。先选择分支，再选择该分支目标，不需共用play_target；若无合法目标只跳过依赖目标的部分。没有分支target则沿用原来的共同目标语义。
- `{test:"deck_top",player:"owner",parity:"even"}` 查询己方牌库顶费用奇偶；空牌库不满足且不移动牌。draw后的if_drawn分支，可用transfer_card source:"drawn",destination:"deck",mode:"move",selection:"top",amount:1,deck_position:"random"，只把本组刚抽到且仍在手牌的实际实例洗回；不会误取之前同名手牌。
- modify_stats 的health_mode:"max_only"表示仅增加防御上限，不恢复当前防御，需要正整数health_delta；之后可以正常治疗到新上限。缺省both仍增加当前及最大防御。
- `{stat:"friendly_turn_number"}`/enemy_turn_number为各自已开始的第几个回合，首回合为1，与指挥点上限无关。`lose_kredits player:"opponent",amount:2`扣除当前指挥点，最低0；配合next_opponent_turn_start实现下个敌方回合开始扣费，多扣部分放独立有条件的组。

用精简卡面描述。保留必要的目标、数值、触发和时限；细节放详细说明。不要生成已存在模板之外的token_id；未填写进化形态时继续询问或提示补全，不把缺少模板误称为引擎不支持。
