extends RefCounted
## Practice-only commands. No script evaluation, network endpoint or file writes.
const HELP := "费用 12 [己方/敌方] · 抽牌 2 [己方/敌方] · 总部 20 [己方/敌方]\n卡库 [名称] · 手牌 卡号 [己方/敌方] · 召唤 卡号 [己方/敌方]\n状态 · 单位 UID · AI 暂停/继续/步进 · 撤销\n召唤直接放入后援线，不触发部署；想测试部署，请用手牌命令。\n卡号来自下方卡库列表。控制台打开时 AI 自动暂停。"
var undo_states: Array = []

func execute(controller: Node, line: String, catalog: Array) -> String:
	if controller.mode != "solo" or controller.spectating or controller._engine == null:
		return "控制台仅限单人练习。"
	var words := line.strip_edges().split(" ",false)
	if words.is_empty(): return HELP
	var command := str(words[0]).to_lower()
	var aliases := {"帮助":"help","状态":"status","卡库":"cards","单位":"unit","费用":"credits","抽牌":"draw","总部":"hp","手牌":"give","召唤":"summon","撤销":"undo"}
	command = aliases.get(command,command)
	var game = controller._engine
	if command == "help": return HELP
	if command == "status":
		var text := "回合 %d · 行动方 %s · AI %s" % [game.state.turn,"己方" if game.state.active_player==0 else "敌方","暂停" if controller.debug_ai_paused else "自动"]
		for seat in 2:
			var p: Dictionary = game.state.players[seat]
			text += "\n%s：总部 %d/%d · 费用 %d/%d · 手牌 %d · 牌库 %d" % ["己方" if seat==0 else "敌方",p.hp,p.max_hp,p.credits,p.max_credits,p.hand.size(),p.deck.size()]
		for unit in game.state.units: text += "\nUID %d · %s · %s · %d/%d" % [unit.uid,"己方" if unit.owner==0 else "敌方",game._unit_definition(unit).name,unit.attack,unit.hp]
		return text
	if command == "cards":
		var lines := PackedStringArray()
		var query := " ".join(words.slice(1)).to_lower()
		for i in catalog.size():
			if query.is_empty() or query in str(catalog[i].definition.name).to_lower(): lines.append("%d · %s" % [i+1,catalog[i].definition.name])
		return "\n".join(lines) if not lines.is_empty() else "没有匹配卡牌。"
	if command == "unit":
		if words.size()!=2 or not words[1].is_valid_int(): return "用法：单位 UID（状态命令可查看 UID）"
		var unit: Dictionary = game._unit(int(words[1]))
		return JSON.stringify(unit,"  ") if not unit.is_empty() else "单位不存在。"
	if command == "ai":
		if words.size()!=2: return "用法：AI 暂停 / 继续 / 步进"
		match str(words[1]).to_lower():
			"暂停","pause": controller.debug_ai_paused=true
			"继续","resume": controller.debug_ai_paused=false
			"步进","step":
				controller.debug_ai_paused=true
				var needs_redraw: bool=game.state.has("mulligan") and not game.state.mulligan.confirmed[1]
				if game.state.winner!=-1 or (not needs_redraw and int(game.state.get("pending_choice",{}).get("owner",game.state.active_player))!=1): return "当前不需要 AI 行动。"
				var action: Dictionary = game.ai_action(1)
				var error: String = game.apply_action(1,action if not action.is_empty() else {"type":"end_turn"})
				controller._refresh_views()
				return "AI 已行动。" if error.is_empty() else error
			_: return "用法：AI 暂停 / 继续 / 步进"
		return "AI 已暂停。" if controller.debug_ai_paused else "关闭控制台后 AI 继续。"
	if command == "undo":
		if undo_states.is_empty(): return "没有可撤销的调试修改。"
		var seq := int(game.state.state_seq)+1
		game.state=undo_states.pop_back();game._reset_budget();game.state.state_seq=seq
		controller._refresh_views()
		return "已恢复到上一次调试修改前。"
	if command not in ["credits","draw","hp","give","summon"]: return "未知命令。输入 帮助 查看用法。"
	if game.state.winner!=-1: return "对局已结束，可撤销修改或重新练习。"
	if game.state.has("mulligan"): return "请先完成开局换牌。"
	if game.state.has("pending_choice"): return "请先完成当前选择，再修改局面。"
	if words.size()<2 or words.size()>3 or not words[1].is_valid_int(): return "用法：%s 数值 [己方/敌方]" % words[0]
	var seat := 0
	if words.size()==3:
		if words[2] in ["敌方","enemy","1"]: seat=1
		elif words[2] not in ["己方","self","0"]: return "对象应为 己方 或 敌方。"
	var value := int(words[1])
	var bounds := {"credits":[0,12],"draw":[1,10],"hp":[1,999],"give":[1,catalog.size()],"summon":[1,catalog.size()]}
	if value<bounds[command][0] or value>bounds[command][1]: return "数值范围：%d–%d。" % bounds[command]
	var card: Dictionary = {}
	if command in ["give","summon"]:
		card=catalog[value-1]
		if not card.get("ok",false): return "该卡规则校验失败。"
		if command=="give" and card.definition.kind=="hq": return "总部不进入手牌。"
		if command=="give" and game._held_cards(seat).size()>=10: return "手牌已满。"
		if command=="summon" and card.definition.kind!="unit": return "只能直接召唤单位牌。"
		if command=="summon" and game._count_row(seat,"support")>=4: return "后援线已满。"
	var before: Dictionary = game.state.duplicate(true)
	game._reset_budget()
	match command:
		"credits": game.state.players[seat].max_credits=maxi(value,int(game.state.players[seat].max_credits));game.state.players[seat].credits=value
		"hp": game.state.players[seat].hp=value;game.state.players[seat].max_hp=maxi(value,int(game.state.players[seat].max_hp))
		"draw":
			for i in value: game._draw(seat)
		"give": game._receive_card(seat,card,"debug")
		"summon": game._new_unit(seat,card,"",true)
	game._checkpoint();game._drain_deaths()
	if not game._fault.is_empty():
		game.state=before;game._reset_budget()
		return "修改需要交互选择或超出规则预算，已撤回。请用正常出牌流程测试该效果。"
	undo_states.append(before)
	if undo_states.size()>20: undo_states.pop_front()
	game.state.state_seq+=1
	game.state.log.append("练习调试："+line)
	controller._refresh_views()
	return "已执行："+line
