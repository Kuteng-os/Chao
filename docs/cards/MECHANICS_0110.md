# 0.11.0 新增机制

本页对应 GitHub issue #49 #52 #55 #66 #67 #68 #80 #81 #85 #90 #91 #100 #102。旧版本客户端不认识这些写法，使用它们的卡需要 0.11.0 及以上版本。

## 费用上限（#66）

`cost`、`cost_override.value` 以及筛选里的 `min_cost` / `max_cost` 上限从 12 放宽到 20。实际费用仍不低于 0。

## 数值来源（#67 #80 #85）

以下 `{"stat": ...}` 可用于伤害、属性、条件比较等所有接受数值来源的地方：

| stat | 含义 |
| --- | --- |
| `friendly_draws_this_game` / `enemy_draws_this_game` | 本局己方 / 敌方抽牌数：包括开局抽牌、回合抽牌、效果抽牌；手牌满被烧掉的也算 |
| `friendly_units_played_this_game` / `enemy_units_played_this_game` | 本局己方 / 敌方从手牌打出的单位数；召唤不算。部署时已经把本张算进去，所以“本局打出的第一个单位”写作 `{"test":"compare","left":{"stat":"friendly_units_played_this_game"},"cmp":"eq","right":1}` |
| `hand_shortfall` | 己方手牌比敌方少的张数，`max(0, 敌方手牌 - 己方手牌)`；伏置的反制不算手牌 |

`draw.amount` 和 `gain_hq_defense.amount` 现在也接受数值来源，结算时计算，最多 10。例如“抽牌直到与敌方手牌数相同”：

```json
{"op":"draw","player":"owner","amount":{"stat":"hand_shortfall"}}
```

## 按抽牌减费（#67）

```json
"cost_reduction": {"per_draw": true, "amount": 1}
```

这张卡进入手牌之后，每抽一张牌（同样包括被烧掉的）费用减少 `amount`，最低 0；离开手牌后重新计数。`per_draw` 与原有的 `per_unit` 只能二选一。

## 按条件从牌组抽牌（#102）

`draw.filter` 除 `kind`、`unit_class` 外新增：

| 字段 | 取值 |
| --- | --- |
| `unit_classes` | 兵种数组，命中任一即可 |
| `faction_id` | 已登记阵营 |
| `sins` | 罪孽数组，`null` 表示无罪孽 |
| `min_cost` / `max_cost` | 费用范围（0–20） |
| `keyword_id` | 卡面带有该词条 |

从牌组顶部往下找第一张符合的牌（牌组本身是洗过的，相当于随机一张），抽完不重洗；找不到就什么都不发生；手牌满照常烧牌。

## 召唤（#80 #90）

- `token_ids`（2–4 个）代替 `token_id`：每召唤一个，随机从中选一个衍生单位。两者只能填一个。
- `position: "beside_hq"`：召唤到己方总部右侧相邻处；缺省 `end` 为原来的位置。
- 同一能力里召唤之后的效果可以用 `"summoned"` 指“刚召唤的单位”（`move_unit`、`grant_action`、`redirect_attack` 的 target，`fight` 的 `source`）。前面没有召唤会编译失败。

## 换位与移动（#91）

```json
{"op":"swap_position","target":"chosen","with":"self"}
{"op":"move_unit","target":"summoned","row":"front"}
```

- `swap_position`：本单位与一个友方单位互换位置，同阵线或跨前线、后援线都可以。只换位置，不算移动，不触发移动事件。需要本单位仍在场。
- `move_unit`：把单位放到指定阵线（按常规入场位置）。去前线须满足主动移动的阵线条件（敌方前线没有单位、前线不满 5 个），去后援线须后援线不满 4 个，不满足就不动。不算主动移动，不消耗行动，不触发移动事件。

## 攻击反制（#90）

- `redirect_attack`：只用于 `enemy_hq_attacked` / `enemy_unit_attacked` 反制。把本次攻击改为攻击指定的己方单位（`summoned` 或 `random_friendly_unit`），然后照常交战、反击。改向不受守护限制。
- `fight` 的 `source: "summoned"`：由刚召唤的单位发起交战，所以指令、反制和阵亡效果也能用。
- 反制（打出指令的反制除外）现在可以读取触发单位的数值，例如 `{"unit_stat":{"target":"trigger_unit","stat":"attack"}}` 读取攻击者的攻击力。

## 授予行动（#55）

```json
{"op":"grant_action","target":"self","action":"attack","attack_target":"trigger_unit"}
{"op":"grant_action","target":"self","action":"move"}
```

单位立即进行一次真正的攻击或移动（可以在对方回合）。不支付行动费、不占用攻击次数；部署等待、压制、射程、守护、烟幕、战斗机掩护照常生效，目标不合法就不行动。攻击照常反击，并触发攻击时、攻击后等事件；移动触发移动后事件。

`attack_target`：`trigger_unit`、`enemy_hq`、`random_enemy_unit`、`random_enemy_target`（单位或总部）。`action: "attack"` 必须填写，`move` 不能填写。

## 新的触发时机

### 单位与场地（#52 #68）

| trigger | 时机 |
| --- | --- |
| `own_counter_triggered` | 己方一张反制结算完成后（总部也可以监听） |
| `any_counter_triggered` | 任意一方的反制结算完成后 |
| `unit_attack_changed` | 任意单位的当前攻击力变化后（`trigger_unit` 为该单位） |

反制及其监听者结算期间不会再触发其他反制，即不支持反制连锁。

`unit_attack_changed` 可以加能力级的 `event_filter`，三个字段都可省略（缺省 `any`）：

```json
{"trigger":"unit_attack_changed","event_filter":{"side":"enemy","row":"front","direction":"down"},"effects":[...]}
```

`side`：`own` / `enemy` / `any`，相对监听者；`row`：`front` / `support` / `any`；`direction`：`up` / `down` / `any`。攻击力来自任何原因（属性修改、设定攻击力、光环出现或消失、层数）都算，只比较变化前后的数值。

### 反制（#49 #68）

| counter_trigger | 时机 | trigger_unit |
| --- | --- | --- |
| `enemy_unit_acted` | 对手单位主动攻击或主动移动完成后 | 行动的单位 |
| `enemy_unit_moved_to_front` | 对手单位主动移动到前线后；部署、召唤和效果移动不算 | 移动的单位 |
| `enemy_unit_ability_triggered` | 对手单位的一个能力结算完成后（持续光环不算） | 该单位 |
| `unit_attack_changed` | 对手回合里有单位攻击力变化后 | 该单位 |

这些时机都在结算之后，所以不能使用 `cancel_action`。`unit_attack_changed` 反制可以加卡牌级的 `counter_filter`（字段同上，`side` 相对反制持有者）。

## 构筑（#81 #100）

- 金卡（`rarity: elite`）如果有罪孽，只能放入主罪孽与它相同的牌组；无罪孽金卡不受影响。
- 卡库里标记为测试的阵营（`faction test` 命令设置）在组牌界面默认隐藏，打开“测试”开关后显示。这些阵营的卡不受主副罪孽和大小阵营限制，按通用牌计数。无阵营的卡同样默认隐藏；自己制作的卡始终显示。

## 卡面（#47）

大阵营的卡在上下边框有斜线纹样，小阵营在左右边框有圆点纹样，颜色取阵营色；手牌缩略尺寸只在四角保留一小段。悬浮详情在阵营名后写明“大阵营/小阵营”。
