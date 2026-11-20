# 0.12.0 新增机制

本页对应 GitHub issue #108 #116 #126 #128 #131 #132 #133。旧版本客户端不认识这些写法，使用它们的卡需要 0.12.0 及以上版本。

## 禁止打出牌种（#126）

```json
{"op":"forbid_play","player":"opponent","card_kinds":["order","field"]}
```

- `player`：`opponent` 或 `owner`。`card_kinds`：`unit`、`order`、`counter`、`field` 中的 1–4 种。
- 被指定的玩家**下一个自己的回合**不能从手牌打出这些牌种。期限和 `forbid_deploy` 相同：对手回合里生效的话，就是对手的下个回合。
- `unit` 同时禁止从手牌部署单位；召唤不受影响。
- `counter` 只禁止把反制伏置下去；已经伏置的反制照常触发。
- 被禁止的牌留在手牌，不扣费。
- 这是一次性效果，不能放进持续光环。

《乱魔》的新效果写作 `forbid_play`，`player: opponent`，`card_kinds: ["order","field"]`。

## 打出费用光环（#131）

```json
{"trigger":"while_active","effects":[{"op":"modify_play_cost","cost_delta":-1,"filter":{"kind":"order"},"first_each_turn":true}]}
```

- **使用范围：** 只能放在 `while_active`（在场期间）里，来源可以是单位、场地或总部。只影响来源控制者自己打出的牌。
- **`filter`：** 和 `modify_hand_cost.filter` 相同，可写 `kind`、`unit_class`、`card_name`、`name_contains`、`faction_id`、`keyword_id`、`without_keyword`。不写就是所有牌。
- **`cost_delta`：** -5 到 5，不能为 0。最终费用最低 0。
- **`first_each_turn: true`：** 只对本回合第一张符合 `filter` 的牌生效。打出第一张之后，同回合后面的牌按原价。
  - 反制在**触发时**才算打出，伏置不算。
  - 卡牌费用明细里会显示来源单位。
- **叠加：** 多个来源会叠加，例如两张《黄金》就是 -2。

## 获得资源槽（#132）

- **时机：**
  - 新单位/总部时机 `own_kredit_slot_gained`、`enemy_kredit_slot_gained`。`modify_kredit_slots` 让己方或敌方的资源槽**实际增加**之后触发。
  - 每次效果触发一次。
  - 回合开始的自然 +1 不算；已经 12 槽时不会增加，也不触发。
- **数值来源：** 新增 `friendly_kredit_slots`、`enemy_kredit_slots`，表示当前资源槽数，可用于条件和数值。

《钻石》写作：

```json
{"trigger":"own_kredit_slot_gained","effects":[{"op":"draw","player":"owner","amount":1}]}
```

## 反制返回手牌（#128）

- **时机 `own_counter_returned`：** 单位、总部都能用。己方伏置的反制没有触发、在己方回合开始时返回手牌，每张触发一次。
  - `event_card` 是这张反制。
  - 对方看不到这个事件，所以没有敌方版本。
- **`modify_hand_cost` 新增 `selection: "event_card"`：** 只能用于 `own_counter_returned`，只改刚返回手牌的那一张。
- **`modify_hand_cost` 新增 `cost_set`（0–20）：** 费用直接变为这个数。与 `cost_delta` 二选一，必须且只能写一个。
- **反制的费用：** 在触发时支付。`duration: "hand"` 的费用变化会一直留着，直到这张牌下次触发或离开手牌；重新伏置不会清掉它。

《流水钳蟹》写作：

```json
{"trigger":"own_counter_returned","effects":[{"op":"modify_hand_cost","selection":"event_card","cost_set":0,"duration":"hand"}]}
```

另外，`modify_hand_cost` 的规则文本现在会写出 `filter` 里的牌种、兵种和卡名。例如“所有己方手牌中的反制费用-5”，不会再显示成对所有手牌生效。

## 失去能力（#108）

```json
{"op":"remove_abilities","target":"chosen","trigger":"on_death","duration":"battle"}
```

- **作用：** 目标失去指定时机的**全部**能力，包括卡面上的和之后获得的。
- **`trigger`：** 可选 `on_death`、`on_leave`、`on_attack`、`after_attack`、`on_attacked`、`after_attacked`、`on_damaged`、`on_kill`、`after_move`、`after_action`、`own_turn_start`、`own_turn_end`。
- **`duration`：**
  - `battle`：本次在场期间。
  - `end_of_turn`：只到本回合结束。
- **`target`：** 和 `remove_keyword` 相同，另外可用 `selected_units`。
- **不能用在持续光环里。**

《MAGIC》（失去守护、烟幕、亡记）写作同一组里的三个效果：两个 `remove_keyword`，加上 `remove_abilities`（`trigger: on_death`）。

## 选择不同的单位（#133）

要“选三个不同的敌方单位，各造成 3 点伤害”，先用 `select_units`，再把 `selected_units` 当作目标：

```json
[{"op":"select_units","side":"enemy","min":3,"max":3},{"op":"damage","target":"selected_units","amount":3}]
```

- **可用的操作：** `selected_units` 现在可用于 `damage`、`heal`、`modify_stats`、`grant_keyword`、`remove_keyword`、`suppress`、`return_to_hand`、`remove_abilities`（原来只有 `destroy`）。
- **选择方式：** `select_units` 每次只能选还没选过的单位。敌方单位不足 3 个时，有几个选几个。
- **不要拆成多个能力组：** 几个能力组各自用 `chosen` 不会自动排除已选单位，可能选到同一个单位。

## 卡面自带词条（#116）

- **会被拒绝的写法：** 单位卡的部署能力（`on_play`）没有前提、没有目标选择，却在本次在场期间或永久给自己：
  - 重甲层数（`modify_stacks` / `set_stacks`，`stack: heavy_armor`）。
  - 一个词条（`grant_keyword`）。
- **改法：** 写成卡面自带词条，例如 `standard.heavy_armor`，参数 `x: 2`，卡面显示“重甲 2”。
- **仍然允许的写法：**
  - 有前提或抉择的写法。
  - 只到本回合结束的写法。
  - 给其他单位的写法。
  - 阵亡、受伤等其他时机。
- **对现有卡没有影响：** 卡库现有的卡都没有这种写法；自带重甲词条展开后的效果不受影响。
