# 0.8.48 / mechanics-32：进化、跨回合效果与反制预备

以下覆盖历史版本的“不支持”结论。玩家历史中的答案仍有效；不要重新询问已经明确的规则，也不凭空补足尚未定义的进化条件或衍生卡卡面。

## 延迟与重复效果

`schedule` 现可放入单位、指令等合法触发组，不能用于 while_active。字段：trigger=next_own_turn_start 或 next_opponent_turn_start；after_turns=1..99（默认1）；effects 为1..4条非递归操作；repeat=once（默认）或 each_turn；可选 times=1..999，仅用于 each_turn，省略表示持续重复。

登记时冻结来源实例、自身卡牌以及当前 chosen/trigger_unit；后续结算不会再次让玩家选目标，也不会换成同名的新单位。默认 lifetime：单位来源为 source，非单位且引用 chosen 为 target，其余 match。可明确 lifetime=source（来源在场且未抑制）、target（原先所选单位仍在场）、match（本场对局独立保留）。离场再入场是新实例。重复每回合从 after_turns 指定的首次回合开始，之后每个匹配回合各结算一次。单位自身数值在触发瞬间读取；固定数值不会自行变化。

“点燃：每个己方回合开始，对所选单位造成3伤害”：on_play 的 effects 包含 `{op:"schedule",trigger:"next_own_turn_start",repeat:"each_turn",lifetime:"target",effects:[{op:"damage",target:"chosen",amount:3}]}`，卡牌有 play_target。无合法目标时这部分不登记，其余效果仍正常；原目标离场后结束，不能追踪返手后重下的新实例。目标暂时不可指定时该次指定效果失效。没有要求持续次数时不得自行变成仅一次；“下回合”与“每回合”不同。

“犀牛每累计损失2防御，下回合重甲+1”：on_damaged,damage_step:2，effects 使用 schedule，trigger 为玩家确认的哪方下回合，lifetime:source，内层 modify_stacks self heavy_armor +1 duration:battle。每达到一次阈值分别预约一次；余数保留，非当场加甲，离场后不作用于复制或重新部署的单位。阵亡复制继承范围仍遵守原卡明确的 inherit_from，不因本修复扩大。

事件触发组 limit 现在允许1..999，留空不限总次数；这是本次在场期间累计触发次数，绝不是同一事件重复执行次数。damage_step 保持1..10，能力/效果数量及单次执行预算保持有界。

## 原位进化

`{op:"transform",target:"self",token_id:"evolution",inherit:"none"}`：把目标替换为当前卡 tokens 中指定的单位模板，新实例占据原阵线与原位置。原卡进入弃牌区，不触发阵亡、不算击杀。新卡按召唤处理，触发 on_summon，不触发 on_play 的部署奖励，当回合遵守正常召唤行动限制。受损、装备、临时强化与旧行动记录不继承；inherit=permanent 时仅复制原卡的永久属性、费用变化及附加能力，不叠加复制临时状态。

target 还可为 chosen、trigger_unit 或所支持的自动单位目标；不可将指令/反制/场地当作进化单位。衍生卡不明确时继续询问，不能生成假的卡面。

“玉化：入场后第三个己方回合开始，进化为本卡指定的衍生单位”：在 on_play 和 on_summon 各放一次 schedule（after_turns:3,lifetime:source），内层 transform self token_id:evolution inherit:none。在每张带此词条的卡中定义同一个约定标识 evolution 的实际衍生单位；词条可共享，实际模板由各卡分别提供。离场取消，召唤新卡清除旧状态，不结算旧卡阵亡。若作者只要求部署后而不包括召唤，只使用 on_play。

## 下一张敌方指令无效

`{op:"prepare_counter",duration:"match"}` 预约取消敌方下一张指令，在其任何效果、选中目标奖励、结算后事件之前取消，费用不返还，指令进入弃牌区。一次只消耗最早的一个预备，不同时耗掉其余预备或伏置反制。duration:match 跨回合保留且不依赖来源仍在场；battle 仅来源单位在场未抑制时有效；end_of_turn 本回合有效。duration 必须明确。不存在的有效期或原玩家未要求的额外扣费不可擅自添加。

复述仍采用简洁卡面语言，如“部署：使敌方下一张指令无效。”“入场后的第三个己方回合开始：进化为【…】。”“每个己方回合开始：对所选单位造成3点伤害。”细节放详细说明，不把上述实现协议搬上卡面。
