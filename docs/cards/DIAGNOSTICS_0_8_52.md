# 0.8.52 逐卡配置词条（优先于旧说明）

- 玩家要登记“解放”这类通用名义、具体前提/攻防/即时效果在每张卡填写的词条，已支持 implementation:{kind:"configurable"}，parameters:{}。保留名称和精简说明即可，不必把逐卡待填的内容视为缺失能力或强行追问具体数值。
- 引用这种词条时，keywords 条目必须包含 abilities:[完整能力组]，每张卡独立填写、独立编译冻结；所有前提和效果使用已有卡牌 DSL。它们与本体能力合并计入每卡8组/24操作及全部衍生96操作的预算。不允许任意脚本。普通 template/builtin 引用不能带 abilities。
- 若玩家正在制作具体卡牌，逐卡的触发、前提和结果仍须明确；空 abilities 不能保存。可以继续多轮提问，但不要称为引擎缺失。可在网页“词条—本卡配置”里使用与普通卡相同的效果编辑器；衍生卡也支持。
- 新触发 when_condition：单位在场，某个结算检查点首次满足 premise 时，触发一次。在同一次在场期间不会反复触发；条件不再满足也不撤销已经得到的强化。返回手牌再部署是新的在场周期，可再次触发。不能设置 limit/limit_scope/occurrence。前提只查当前场面或自身，不能查尚未确定的 chosen/trigger_unit/attack_target 或 event_damage。
- when_condition 需要选目标时用能力 target:{side,row,timing:"trigger"}。无合法目标跳过依赖该目标的部分，其他效果正常执行。默认“解放”攻防强化用 modify_stats self duration:battle，其他即时效果可同组组合；返手不保留这些在场强化。已有明确写永久的效果仍按 match 保留。
- 示例词条：{"schema_version":"1.0.0","ruleset_version":"frontline-1","id":"custom.release","version":1,"name":"解放","aliases":[],"description":"满足本卡条件时解放；回手后恢复原型。","parameters":{},"implementation":{"kind":"configurable"}}。
- 示例引用：{"id":"custom.release","version":1,"params":{},"abilities":[{"trigger":"when_condition","premise":{"test":"compare","left":{"stat":"enemy_unit_count"},"cmp":"gt","right":{"stat":"friendly_unit_count"}},"effects":[{"op":"modify_stats","target":"self","attack_delta":2,"health_delta":1,"duration":"battle"},{"op":"draw","player":"owner","amount":1}]}]}。

- 生成蓝图中 abilities:[] 的逐卡词条表示待填写，可以由助手补全这些空槽（包括衍生卡）；保持 id/version/params 不变。已有非空配置不可覆盖。最终卡牌所有槽必须完整并通过编译才能保存。
