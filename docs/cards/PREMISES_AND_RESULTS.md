# 单卡前提与结果 · 0.8.23

在“用文字添加效果”中完成需求、正式复述、问答、修正与确认。只有生成结果通过真实卡牌编译、固定字段和效果数值校验，页面才显示“通过”。通过表示效果加入草稿；点击保存才登记卡牌与可复用组件。缺少时机、目标、取整或持续时间时继续提问，不能擅自替玩家选择。

## 条件表达式

每个 ability 可有一个 `premise`。它在该次触发结算前读取战局、判断一次；不满足则整组不执行，满足后按 effects 顺序执行，不因中间状态变化重新判断。不同组依次读取当时状态。触发时选目标在条件通过后进行；部署时绑定延后目标仍按原绑定规则。条件反制在揭示、扣费前判断；所有组都不满足时继续伏置，不揭示、不扣费。

```json
{
  "trigger": "on_play",
  "premise": {
    "test": "compare",
    "left": {"stat": "enemy_unit_count"},
    "cmp": "gt",
    "right": {"stat": "friendly_unit_count"}
  },
  "effects": [{"op": "draw", "player": "owner", "amount": 2}]
}
```

`compare` 支持 `gt/gte/eq/ne/lt/lte`；`all/any` 使用 `items`（1～6项），`not` 使用 `item`。最多4层、24节点。左右数值可以是 -100～100 整数或白名单属性：

| 属性 | 含义 |
| --- | --- |
| enemy_unit_count / friendly_unit_count | 双方在场存活单位总数，包含前线和支援阵线，不含总部 |
| other_friendly_unit_count | 排除来源单位的友方单位数 |
| enemy_front_count / friendly_front_count | 前线单位数 |
| enemy_support_count / friendly_support_count | 支援阵线单位数 |
| enemy_hand_count / friendly_hand_count | 当前实际手牌区张数，不含已伏置反制 |
| enemy_deck_count / friendly_deck_count | 当前牌组张数 |
| enemy_hq_health / friendly_hq_health | 总部当前防御力 |
| enemy_kredits / friendly_kredits | 当前可用资源 |
| source_attack / source_health | 来源在场单位当前攻防，离场后为0 |
| source_base_health | 来源卡牌的初始防御力 |

视角始终以效果控制者为“己方”。部署结算时，来源单位已进入战场。普通效果组在支付部署费后判断；反制在支付触发费用前判断。持续光环 `while_active` 允许安全的战场计数条件；mechanics-49 另支持自身前线/后援线位置条件，具体限制见 [单位状态前提](UNIT_STATE_PREMISES.md)。光环随条件变化生效或消失，不得悄悄改成永久触发增益。条件不执行任意代码，也不支持未登记的外部状态或无界递归。

## 可复用组件

`GET /v1/mechanism-components` 返回经过确认的前提、结果目录，需要玩家登录。模型上下文 `component_catalog` 按复用次数提供最多128项。正式保存卡牌时，在同一事务中从已编译卡牌登记新组件；正文哈希生成不可变ID，重复内容复用同一ID。

生成与手工草稿阶段支持引用：

```json
{"test":"ref","id":"premise.<内容哈希前32位>","version":1}
```

```json
{"op":"use_component","id":"result.<内容哈希前32位>","version":1}
```

引用仅是编辑时简写，在服务端展开后按卡牌 Schema 校验。卡牌及历史修订存储展开后的固定内容，战斗不请求模板目录。新增组件不能运行脚本，也不能绕过每牌4组、每组4效果、总12操作的预算。涉及该牌衍生模板 token_id 的结果不进入全局复用目录。

## 战斗伤害

`set_combat_damage_multiplier` 保留原整数 `multiplier`，新增 `divisor`（1～8）、`rounding`（floor/ceil）、`ignore_armor`（布尔）。分母大于1时必须指定取整方式。旧牌省略新字段时语义与哈希保持不变。

例如经玩家确认“主动攻击和反击都造成攻击力一半、向上取整、无视重甲”：

```json
{"op":"set_combat_damage_multiplier","target":"self","against":"any","applies_to":"both","multiplier":1,"divisor":2,"rounding":"ceil","ignore_armor":true,"duration":"battle"}
```

先以当前攻击力乘分子除分母并取整，再减重甲；忽略重甲时减免为0，重甲层数不消耗，免疫依然有效。最近匹配的完整战斗伤害规则覆盖旧规则。技能/指令 damage 原本不受重甲减免，不能擅自将战斗倍率解释为所有附加伤害的倍率。玩家写“一般”时不能自行断定是“一半”。

## 后台报错

服务器持续收集生成失败、校验失败、缺失能力与待澄清项，按内容合并次数。迁移时补收已有生成记录。管理员在账号区“报错记录”中查看、下载JSON、标记处理；再次发生会重新打开。最多保留1000组，优先淘汰最久未出现项。记录只包括任务描述、阶段、卡名、错误详情、时间和次数，过滤令牌/密钥/密码，不保存认证请求体或模型思考过程。

部署新版本不会自动重试或收费，也不会静默修改已经保存的卡牌；旧的失败复述可重新发起理解。
