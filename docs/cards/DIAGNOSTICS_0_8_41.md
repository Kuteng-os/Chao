# 0.8.41 当前机制能力（优先于旧提示中的能力限制）

机制复述、澄清和生成共用以下能力，不得再把这些能力列为缺失。

## 当前回合归属

任意事件能力可用 `premise: {"test":"turn_owner","side":"owner"}` 限制为本卡控制者回合，`side:"opponent"` 限制为对手回合。可组合 all/any/not。例：友方回合中友方单位阵亡时抽1张并获得1指挥点，使用 own_unit_died + 上述 premise + draw(owner,1) + gain_kredits(1)。统计阵亡事件是否含自身如未明确仍需澄清，不能替玩家决定。

## 按攻击力差减伤

`modify_incoming_damage` 的 amount 除固定非零整数，还支持 `{"attack_gap":{"step":2,"reduction":1}}`。每次伤害独立读取受伤单位与伤害来源单位的当前攻击力，减少 `floor(max(0,受伤者攻击-来源攻击)/step)*reduction` 点，最低伤害为0。step为1—30，reduction为1—10。例：每高2攻击减2伤害，用step=2,reduction=2。damage_kind为combat/effect/both，按玩家意图确定；普通指令和总部没有来源单位时不产生攻击力差。该操作支持 self/chosen/其他现有合法目标及 battle/match 等既有持续时间。

持续固有自减伤用 on_play + target:self + duration:battle，召唤的单位也会初始化该被动。动态差值每次受伤重新计算，不要锁定部署时数值。与已有先手 set_combat_priority 可并用，不能说缺少攻击差表达式。只有玩家没指定的范围、倍率等需提问。

## 无额外效果的指令

明确要求“花费3费、无其他效果”的指令用 on_play + `{"op":"noop"}`。仍照常付费、进入弃牌区并触发打出指令事件；不改变其他状态。不要伪造永远不满足的前提、增加抽牌、返还费用或要求玩家强加效果。空白编辑草稿仍需先填写效果；只有明确的noop才代表无效果指令。

## 复制强化来源

transfer_card mode:copy 默认保留全部 duration:match 的永久强化，不继承临时强化。可加 `inherit_from:[{"card_id":"来源卡的稳定UUID","name":"来源卡名"}]`，只保留这些来源的永久攻防、行动费、层数、附加能力等；空数组表示不继承。离场返回的是原卡，不受复制筛选影响。跨版本以card_id匹配，name仅显示；同名异ID不匹配。

user.card_reference_catalog 提供已登记卡的真实ID与名称，仅用于此引用，不可编造。R公司自我阵亡复制若限定只保留“最后的孵化”的永久强化，使用该卡真实ID作为inherit_from；本体基础数值/固有词条保留，其他来源永久强化和临时强化排除。不要给其他未提出来源限制的复制默认增加此限制。

## 已有能力与字段

core.untargetable@1 已支持“不可被指令及技能指定”，不阻止普通攻击、范围、随机及自动效果。无需新造关键词。总部初始防御力范围1—100，单位1—20；超限必须提示具体字段范围并保留输入，不能绕过校验或自动截断。

## 本轮追加报告 82—88

- 按牌种抽牌：draw 可加 filter:{kind:"order"} 或 {kind:"unit",unit_class:"fighter"}。从牌库顶部依次抽取匹配牌，其他牌原序保留；不足只抽实际张数，无匹配不产生疲劳。这是抽牌，保留draw统计，手满照常烧牌。无filter的draw维持原来的普通抽牌/疲劳规则。“法术”含义已回答为order时不要重复询问。
- 按刚抽的牌费用判定：同一效果组内先执行一到多条draw，再执行 {op:"if_drawn",parity:"even",match:"any",effects:[{op:"gain_hq_defense",player:"owner",amount:5}]}。仅检查本组本次执行通过draw实际取得的己方牌，包括手满烧毁的牌；费用取卡面打出费用，0为偶数；没有抽到牌则不触发。any至少一张满足便执行一次，all需实际抽到的牌全部满足。parity也可odd。不是每张分别触发，不包括其他能力/开局/回合自动抽牌，也不会读取敌方手牌。分支不可嵌套，与抉择共用现有操作预算。
- CZ-82/83 已确认例子：同一个 on_play 组按序 draw(owner,1,filter:{kind:"unit"})、draw(owner,1,filter:{kind:"order"})、上述if_drawn。不能把抽牌和if_drawn拆成两个组；不要把“本组抽牌结果”当打出前条件。
- 上一张打出的牌：premise:{test:"previous_card",player:"owner",kind:"order"}。比较打出本牌之前己方最后打出的牌；跨回合保留，单位/指令/场地均会更新，反制伏置不会更新或泄密；无前牌为false。player:opponent检查对方最近打出的牌。新牌不会把自己当作上一张；可以放入all/any/not组合。已有取消指令仍然算已打出的牌。
- 按装备来源阵营计数：modify_stats attack_delta/health_delta 支持 {equipment_faction:"阵营真实UUID",scale:2}。equip执行时记录该装备来源卡的faction_id；按件计数，unequip按同tag最早装备先移除。本单位while_active+self+battle可随当前装备数动态增减，不靠名称猜阵营。未标阵营装备不匹配；阵营ID用faction_catalog，罪孽不是阵营。原有 {equipment:"名称标签",scale:2} 保持按标签计数。
- 延迟第N个回合：next_own_turn_start/next_opponent_turn_start 可加 ability.after_turns:1..6，缺省1；2表示“下下个”该方回合开始，跳过第一个；一旦到时仅结算一次，多组各自计数。不要把after_turns放到effect。条件在到时判定，目标继续沿用已有延迟选择规则。
