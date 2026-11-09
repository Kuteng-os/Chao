# 单位词条与本次在场历史前提（mechanics-15）

可在 premise 的 all / any / not 中组合两类新叶节点，仍受最多 4 层、24 节点限制。

```json
{"test":"unit_keyword","target":"chosen","keyword_id":"core.shock","state":"printed"}
```

- printed：对局冻结版本卡面原生的内置词条。临时赋予不算；被消耗或抑制后仍能查询原生状态。
- current：当前有效词条，包括之后授予且仍有效的词条；考虑抑制、消耗及有效授予层。
- consumed：本次在场期间确实消耗过该词条。消耗不存在的词条不会留下历史；再次授予不清除历史。移除/抑制不等于消耗。

```json
{"test":"unit_state","target":"chosen","state":"has_attacked"}
```

has_attacked：本次在场期间曾进入主动战斗结算，包括打总部及 fight 效果，不含反击；被反制取消或在交战前被移除而未进入结算不算。回合切换、重置行动、压制、抑制不清除历史；离场、返手后重下、复活或复制生成的新实例重新开始。历史跟随当前战场实例，不写回卡牌定义。

target 可为 self、chosen、trigger_unit。self 仅用于在场来源单位，trigger_unit 仅用于具有触发单位的事件。chosen 本轮仅支持 on_play 共用 play_target，且不能包含总部；不支持能力组单独选择或延迟时重新选目标的状态前提。

mechanics-49 起，持续光环允许查询自身位置：`{"test":"unit_state","target":"self","state":"in_front"}` 或 `in_support`，可在 all / any / not 中组合。仍支持安全的战场计数条件；自身词条查询只允许原有的固定攻击力光环，不能用当前攻防、攻击历史或其他单位状态构造可能循环的光环条件。

例如“在前线时行动费为 0”使用 `while_active`、上述 `in_front` 条件与 `{"op":"modify_operation_cost","target":"self","cost_set":0,"duration":"battle"}`。离开前线后恢复原始费用及其他仍有效修正；移入前线的费用按移动前状态支付。

单位不存在、死亡或目标为总部时，整个包含其查询的条件树为假，即使查询在 not 内也不触发。共同 play_target 的登场条件组在该次结算开始时统一判定，再依次执行。只锁定真假，不冻结目标后续攻防；目标之后离场，其目标效果按原有规则失效。

“越冲越爽”的明确三分支可以使用两个效果组：原生冲击且未主动攻击 => +1/+2；原生冲击且已主动攻击 => 授予冲击、伏击、+1/+2；无原生冲击时两个条件均不成立，支付指令费用但不产生效果。首次/已消耗/当前有词条并不等价，助手须使用玩家确认的查询，不得擅自互换。
