# 0.8.55 已实现机制（覆盖旧能力说明）

## CZ-000215 精确回手减费
`return_to_hand` 现可同时指定 `cost_delta`（-12..12，非0）和 `duration`（end_of_turn / hand）。
例：`{"op":"return_to_hand","target":"chosen","cost_delta":-2,"duration":"end_of_turn"}`。
表示：将所选单位回手，本回合内该牌下次打出费用-2。费用最低0。
这会绑定成功返回的那一个实例，不按名称查找，不影响同名手牌，无需第二次选择。
打出后消耗该次减费；再次回手不会继承。end_of_turn 到本回合结束失效；hand 留在手牌期间有效，离开手牌即失效。满手烧毁则不会把减费转移给其他牌。
cost_delta/duration 必须成对；不减费时都省略。普通回手仍正常支持。
复述中“将其回手，使其减费”已明确指同一张牌，不要再问是否能给另一张牌减费，不能用另选手牌的 modify_hand_cost 偷换。

## CZ-000216 上一己方回合的部署历史
新增前提 `{"test":"deployed_last_turn","player":"owner","filter":{"sin":"gloom"}}`。
player=owner/opponent，查指定玩家最近一个已经结束的己方回合。若正在该玩家回合内，则查上一个己方回合；从未轮到过的首回合不成立。
filter 可为空，或组合 sin（七种罪孽）、unit_classes（五兵种数组）、faction_id、card_name、name_contains。
记录部署当时的属性；后来死亡、回手、变形不改变历史。普通召唤不计，明确免费“部署”计；在对方回合发生的部署不算该玩家的己方回合。
示例：部署时，若己方上回合部署过忧郁单位，撤退一个所选敌方单位。使用 on_play、上面 premise 和 retreat chosen，并设置敌方单位选择器。无合法目标只跳过该目标效果。
“忧郁单位”指 sin=gloom，不是阵营名。未指定回合归属时应澄清；已确认“己方上回合”不得重复询问。
保持卡面简短，详细结算边界仅放详细说明，不宣称这些已实现的能力缺失。
