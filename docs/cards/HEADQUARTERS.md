# 总部卡（0.8.35 / mechanics-23）

每副牌组单独选择一张 `kind: "hq"` 的已登记卡，保存冻结版本引用。总部不计入40张牌组，不进入手牌，不消耗部署费用，也不算单位。未选择时保持默认：20防御，每回合抽1张。

总部定义沿用 CardDefinition 的作者、版本、阵营、卡面、音效、词条与效果组合流程。`health` 为1至100；`cost`、`attack`、`operation_cost` 为0；`unit_class` 和 `play_target` 为null；`appearance.emblem` 为 `hq`。不能将总部作为衍生模板、反制或场地。总部不被新场地替换。

```json
{
  "kind": "hq",
  "health": 30,
  "draw_rule": {
    "base": 1,
    "adjustments": [{
      "premise": {
        "test": "compare",
        "left": {"count_units": {"side": "enemy"}},
        "cmp": "gt",
        "right": {"count_units": {"side": "ally"}}
      },
      "delta": 1
    }]
  }
}
```

以上是字段片段，完整定义仍须包含标准必填字段。

`draw_rule.base` 为0至5；最多4条调整，每条 `delta` 为-5至5的非零整数。己方回合开始、常规触发组之前，一次性按同一局面判定所有条件并相加，最后限制在0至10张，再逐张抽牌。沿用手牌上限、烧牌和疲劳规则；致命疲劳立即终止。起手发牌不受此规则影响。条件沿用通用前提，可查询双方单位数、兵种、手牌、总部生命等；不能引用选中/自身/触发单位状态。

血量、基础抽牌和表单中的条件调整属于玩家固定配置。AI追加效果时必须保留这些内容，不能重复生成同一条抽牌变化。额外抽牌也可用 `own_turn_start + premise + draw` 表达，这类效果发生在基础抽牌后，不应冒充“基础抽牌规则”。

驻场能力支持 `while_active`、`own_turn_start/end`、`opponent_turn_start/end`、`own/enemy_unit_deployed`、`own/enemy_order_played`、`own/enemy_unit_died`。总部不部署、不阵亡，不使用 `on_play/on_death`。`self` 指单位，不能用于总部；治疗总部使用 `own_hq`。选单位时在效果组设置 `target.timing: "trigger"`。开局就出现的选择支持暂停、继续和超时处理，不重复发起手牌或回合抽牌。

`while_active` 可以给所有友方或所有敌方单位固定攻防、行动费或重甲增减，沿用光环校验，不能混入抽牌等即时操作。事件监听可设置整场次数 `limit`，总部计数独立于各单位。

牌组本地保存 `headquarters_id`；共享和权威对战传输独立的 `headquarters: {card_id, revision, definition_hash}`（或null）。权威端从已登记目录加载并重新编译，不信任客户端程序。局域网同样重新编译双方总部。历史记录保留总部版本，统计可按 `kind=hq` 查询驻场贡献。

## 同版本规则修复

- 目标选择不是整张牌的出牌前提。有合法目标必须选择；无合法目标时可正常出牌，只有依赖 `chosen` 的结果失效，其他结果照常结算。明确写入 `premise` 的前提仍按定义判定。
- 步兵、坦克、炮兵、战斗机、轰炸机均可移入前线；部署等待、压制、行动费、敌方占领和五单位容量限制仍有效。
