# 0.8.42：已实现的结果分支与目标限定

此说明覆盖先前关于下列能力“不支持”的旧说明。生成和复述必须以当前 schema 为准。原会话玩家已回答的问题继续有效，未确认的装备加成、持续时间或覆盖/追加意图仍需澄清，不能擅自补数值。

- 击杀追加：同一个效果组用 `damage`、普通 `draw`、`if_killed` 顺序表达。示例：`[{"op":"damage","target":"chosen","amount":2},{"op":"draw","player":"owner","amount":1},{"op":"if_killed","effects":[{"op":"draw","player":"owner","amount":1}]}]`。`if_killed` 检查本组最近一次伤害是否直接消灭至少一个单位，只执行一次，不能以总部伤害、连锁阵亡或单纯目标已离场代替。每次重复效果组重新记录结果。
- 限定阵营单位：`play_target`、能力 `target` 和效果 `unit_filter` 都可加 `faction_id`，使用 FACTION_CATALOG 的真实 UUID。例：`{"side":"ally","row":"any","faction_id":"实际阵营UUID"}`。阵营和罪孽是独立字段，不能用罪孽、名称或占位 UUID 代替。阵营单位限定不能同时包含总部。
- 抉择里的延迟效果：`schedule` 可放在 `choose_effect.options[].effects` 中，只登记选中的分支。例如总部分支：`[{"op":"gain_hq_defense","player":"owner","amount":7},{"op":"schedule","trigger":"next_own_turn_start","after_turns":1,"effects":[{"op":"gain_hq_defense","player":"owner","amount":2}]}]`。另一个分支抽2牌；选择抽牌时不会登记总部强化。`after_turns` 省略即1，范围1—6；支持己方/敌方后续回合开始。仅指令使用时可登记。延迟子效果使用自动目标，不保留所选单位或自身来源单位；不能嵌套抉择、schedule、if_killed、if_drawn。选择分支时不能额外生成独立的延迟能力，否则会让未选分支也生效。
- 阵亡原卡回手：单位 `on_death` 使用 `{"op":"transfer_card","source":"self","mode":"move","destination":"hand","selection":"random","amount":1}`。这是取回刚阵亡的原卡，不是复制、随机取同名弃牌或复活。退场时清除临时在场状态（损伤、压制、抑制等），只保留仍有效的整局永久强化；手牌满则烧毁原卡。此形式不带 filter 或 inherit_from；每个死去的实体最多取回一次。

上述操作计入既有操作预算：每卡最多4个能力、12条展开操作；结果分支最多4个子操作，schedule 每次只触发一次。展示文本简短，例如“使用时：造成2点伤害，抽1张牌；若击杀，再抽1张”。不得把玩家缺失细节误报为底层不支持。
