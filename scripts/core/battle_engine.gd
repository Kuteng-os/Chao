class_name BattleEngine
extends RefCounted
## Authoritative deterministic interpreter. An action commits once or has no effect.
const Runtime = preload("res://scripts/core/card_runtime.gd")
var state: Dictionary = {}
var _budget: Dictionary = {}
var _fault := ""
var _action_kills: Dictionary = {}
var _deaths: Array = []
var _summons: Array = []
var _events: Array = []
var _counter_canceled := false
var _choice_answers: Array = []
var _choice_cursor := 0
var _resolution_id := ""

func setup(deck0: Array, deck1: Array, seed_value: int = 0, headquarters: Array = [], opening_redraw: bool = false) -> String:
	if not headquarters.is_empty() and headquarters.size()!=2: return "双方各需一个总部"
	for hq in headquarters:
		if not hq is Dictionary: return "总部格式无效"
		if not hq.is_empty() and (not hq.get("ok",false) or hq.get("definition",{}).get("kind")!="hq" or Runtime.sha(hq.get("source",{}))!=hq.get("definition_hash")): return "总部卡校验失败"
	for deck in [deck0, deck1]:
		if deck.size() != DeckRules.DECK_SIZE:
			return "牌组必须恰好有 40 张牌，总部不计入"
		var copy_error := DeckRules.check_copies(deck)
		if not copy_error.is_empty(): return copy_error
		for card in deck:
			if not card is Dictionary or not card.get("ok", false) or not card.has("source") or not card.has("definition"):
				return "牌组包含未编译的卡牌"
			if Runtime.sha(card.source) != card.get("definition_hash", ""):
				return "卡牌定义哈希不匹配"
	var actual_seed := seed_value if seed_value != 0 else int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
	actual_seed = abs(actual_seed) % 2147483646 + 1
	state = {"field": {}, "players": [], "units": [], "turn": 1, "active_player": 0, "winner": -1, "log": [], "state_seq": 0, "rng_state": actual_seed, "seed": actual_seed, "next_uid": 1, "next_hand_id": 1, "next_modifier_id": 1, "private_log": [], "discard": [], "telemetry": [], "telemetry_truncated": false, "scheduled": [], "suspended": [], "order_intercepts": [], "starting_decks": [deck0.duplicate(true),deck1.duplicate(true)]}
	for deck in state.starting_decks:
		for card in deck: card.erase("match_layers"); card.erase("creator_uid"); card.erase("pending_layers"); card.erase("match_abilities"); card.erase("match_ability_sources"); card.erase("pending_abilities")
	_reset_budget()
	state.active_player = _random_index(2)
	state["first_player"] = int(state.active_player)
	for deck in [deck0, deck1]:
		var pile: Array = deck.duplicate(true)
		for card in pile: card.erase("match_layers"); card.erase("creator_uid"); card.erase("pending_layers"); card.erase("match_abilities"); card.erase("match_ability_sources"); card.erase("pending_abilities")
		for i in range(pile.size() - 1, 0, -1):
			var j := _random_index(i + 1)
			var temporary: Variant = pile[i]
			pile[i] = pile[j]
			pile[j] = temporary
		state.players.append({"hp": 20, "max_hp": 20, "credits": 0, "max_credits": 0, "deck": pile, "hand": [], "fatigue": 0, "burned": [], "counters": []})
	for owner in 2:
		var hq: Dictionary = {} if headquarters.is_empty() else headquarters[owner].duplicate(true)
		state.players[owner]["headquarters"] = hq
		state.players[owner]["hq_event_counts"] = {}
		if not hq.is_empty():
			state.players[owner].hp = int(hq.definition.health)
			state.players[owner].max_hp = int(hq.definition.health)
	for player in [0, 1]:
		for i in 4:
			_draw(player)
	_draw(1 - int(state.active_player))
	_log("对局开始，玩家 %d 先手" % (int(state.active_player) + 1))
	if opening_redraw:
		# Opening-hand statistics describe the kept hand, after both decisions.
		state.telemetry=state.telemetry.filter(func(event):return event.kind!="opening_draw")
		state["mulligan"]={"confirmed":[false,false]}
		state.state_seq=1
		return ""
	return _begin_opening_turn()

func _begin_opening_turn() -> String:
	var sequence:=int(state.state_seq)+1
	var opening := state.duplicate(true)
	_choice_answers=[]
	_choice_cursor=0
	_resolution_id=str(sequence)
	_start_turn()
	if _fault=="AWAITING_CHOICE":
		state["_resolution"]={"origin":opening,"player":int(opening.active_player),"action":{"type":"setup_turn"},"choices":[],"id":str(sequence)}
	elif not _fault.is_empty(): return _fault
	state.state_seq = sequence
	return ""

func _confirm_mulligan(player: int, ids: Array) -> String:
	var origin:=state.duplicate(true)
	_reset_budget()
	var returned: Array=[]
	var hand: Array=state.players[player].hand
	var deck: Array=state.players[player].deck
	# Draw replacements before putting rejected copies back into the deck.
	for i in hand.size():
		if hand[i].instance_id not in ids: continue
		returned.append(hand[i].card)
		hand[i]={"instance_id":"h"+str(state.next_hand_id),"card":deck.pop_back()}
		state.next_hand_id+=1
	deck.append_array(returned)
	if not returned.is_empty():
		for i in range(deck.size()-1,0,-1):
			var j:=_random_index(i+1)
			var temporary: Variant=deck[i];deck[i]=deck[j];deck[j]=temporary
	state.mulligan.confirmed[player]=true
	state.state_seq+=1
	if state.mulligan.confirmed.all(func(v):return v):
		for seat in 2:
			for entry in state.players[seat].hand:_stat("opening_draw",seat,entry.card)
		state.erase("mulligan")
		var error:=_begin_opening_turn()
		if not error.is_empty():state=origin;_reset_budget();return error
	return ""

func _stat(kind: String, owner: int, card: Dictionary = {}, amount: int = 1, detail: Dictionary = {}) -> void:
	if state.telemetry.size() >= 20000:
		state.telemetry_truncated = true
		return
	var event := {"kind": kind, "owner": owner, "amount": amount, "turn": int(state.turn), "seq": int(state.state_seq) + 1}
	if not card.is_empty():
		var origin: Dictionary = card.get("generated_origin", card)
		event["definition_hash"] = origin.get("definition_hash", "")
		event["card_ref"] = origin.get("telemetry_ref", {})
		event["name"] = card.definition.name
		if card.definition.has("media"): event["media"] = card.definition.media.duplicate(true)
		if card.has("generated_origin"):
			event["generated"] = true
			event["generated_token_id"] = card.generated_token_id
			if kind in ["play", "deploy"]: event.kind = "generated_" + kind
	# Only already-public orders and revealed counters carry a display face.
		if (kind == "play" and card.definition.kind in ["order","field"]) or kind == "counter_reveal":
			event["display_card"]={"definition":Runtime.display_definition(card),"art_id":card.get("art_id","")}
	event.merge(detail, true)
	state.telemetry.append(event)

func _damage_stat(owner: int, card: Dictionary, amount: int, hp: int, target_owner: int, target_uid: int, target_card: Dictionary = {}) -> void:
	var actual := mini(amount, maxi(0, hp))
	_stat("damage", owner, card, actual, {"attempted": amount, "target_owner": target_owner, "target_uid": target_uid, "hq": target_uid < 0})
	if not target_card.is_empty(): _stat("damage_taken", target_owner, target_card, actual)
	if hp > 0 and amount >= hp and target_uid > 0: _stat("kill", owner, card, 1, {"target_owner": target_owner})

func _reset_budget() -> void:
	_budget = {"ops": 0, "events": 0, "visits": 0, "random": 0, "cleanup": 0}
	_fault = ""
	_action_kills = {}
	_deaths = []
	_summons = []
	_events = []
	_counter_canceled = false

func _spend(kind: String, amount: int = 1) -> void:
	_budget[kind] += amount
	var limits := {"ops": 256, "events": 2048, "visits": 4096, "random": 512, "cleanup": 32}
	if _budget[kind] > limits[kind]:
		_fault = "RULE_BUDGET_EXCEEDED"

func _log(message: String) -> void:
	_spend("events")
	state.log.append(message)

func _random_index(size: int) -> int:
	# Rejection sampling avoids modulo bias (LCG state spans 1 through m-1).
	var range_size := maxi(size, 1)
	var ceiling := 2147483646 - (2147483646 % range_size)
	while true:
		_spend("random")
		if not _fault.is_empty(): return 0
		state.rng_state = (int(state.rng_state) * 48271) % 2147483647
		if int(state.rng_state) <= ceiling: break
	var outcome := (int(state.rng_state) - 1) % range_size
	state.private_log.append({"kind": "random", "size": size, "result": outcome})
	return outcome

func _unit(uid: int) -> Dictionary:
	for unit in state.get("units", []):
		if unit.uid == uid:
			return unit
	return {}

func _hand(player: int, hand_id: String) -> Dictionary:
	for entry in state.players[player].hand:
		if entry.instance_id == hand_id:
			return entry
	return {}

func _unit_definition(unit: Dictionary) -> Dictionary:
	if unit.token_id.is_empty() or unit.card.has("generated_origin"):
		return unit.card.definition
	for token in unit.card.definition.tokens:
		if token.token_id == unit.token_id:
			return token
	return {}

func _has_keyword(unit: Dictionary, keyword_id: String) -> bool:
	if unit.is_empty(): return false
	var consumed: int = int(unit.get("consumed_keywords",{}).get(keyword_id,-1))
	if not unit.get("suppressed",false) and consumed < 0:
		for keyword in _unit_definition(unit).keywords:
			if keyword.id == keyword_id: return true
	for effect in _field_effects(unit,true):
		if effect.op=="grant_keyword" and effect.keyword_id==keyword_id: return true
	for layer in unit.get("grants",[]):
		if layer.keyword_id == keyword_id and int(layer.modifier_id) > consumed:
			return true
	return false

func _consume_keyword(unit: Dictionary, keyword_id: String) -> void:
	var had := _has_keyword(unit,keyword_id)
	if had:
		if not unit.has("consumed_keyword_history"): unit["consumed_keyword_history"] = {}
		unit.consumed_keyword_history[keyword_id] = true
	if not unit.has("consumed_keywords"): unit["consumed_keywords"] = {}
	unit.consumed_keywords[keyword_id] = int(state.next_modifier_id)-1
	if had and not _has_keyword(unit,keyword_id):
		_queue_unit_event(unit,"on_keyword_lost",unit.uid,unit.card,0,false,{"lost_keyword":keyword_id})
		_recompute(unit)

func _count_row(owner: int, row: String) -> int:
	var count := 0
	for unit in state.units:
		if unit.row == row and (owner < 0 or unit.owner == owner):
			count += 1
	return count

func line_units(owner: int, row: String) -> Array:
	var units: Array = state.units.filter(func(u): return u.row == row and (owner < 0 or int(u.owner) == owner))
	units.sort_custom(func(a,b): return int(a.get("line_index",a.uid)) < int(b.get("line_index",b.uid)))
	return units

func line_order(owner: int, row: String) -> Array:
	var ids: Array = line_units(owner,row).map(func(u): return int(u.uid))
	if row == "support": ids.insert(clampi(int(state.players[owner].get("hq_index",0)),0,ids.size()),-1)
	return ids

func _write_line(owner: int, row: String, ids: Array) -> void:
	for index in ids.size():
		if int(ids[index]) == -1: state.players[owner]["hq_index"] = index
		else:
			var unit := _unit(int(ids[index]))
			if not unit.is_empty(): unit["line_index"] = index

func _remove_from_line(unit: Dictionary) -> void:
	var ids := line_order(unit.owner,unit.row)
	ids.erase(int(unit.uid))
	_write_line(unit.owner,unit.row,ids)

func _position_unit(unit: Dictionary, position: int = -1) -> void:
	var ids := line_order(unit.owner,unit.row)
	ids.erase(int(unit.uid))
	if position < 0:
		position = 0 if unit.row == "support" and (ids.size()-1)%2 == 0 else ids.size()
	ids.insert(clampi(position,0,ids.size()),int(unit.uid))
	_write_line(unit.owner,unit.row,ids)

func _ready(unit: Dictionary) -> bool:
	return not _pinned(unit) and (unit.born_turn != state.turn or _has_keyword(unit, "core.blitz"))

func _pinned(unit: Dictionary) -> bool:
	return int(unit.get("pinned_until",-1)) >= int(state.turn)

func play_cost(player: int, card: Dictionary) -> int:
	var cost := int(card.definition.cost)
	for layer in card.get("match_cost_layers",[]) + card.get("hand_cost_layers",[]):
		if int(layer.get("expires_turn",-1)) < 0 or int(layer.expires_turn) >= int(state.turn): cost = int(layer.cost_set) if layer.has("cost_set") else cost+int(layer.cost_delta)
	if card.definition.has("cost_reduction"):
		var reduction: Dictionary = card.definition.cost_reduction
		# Reading a displayed/legal cost must never consume the action budget.
		cost -= _premise_value({"count_units":reduction.per_unit},{"owner":player},false) * int(reduction.amount)
	var surcharge := 0
	for tier in card.definition.get("cost_surcharge",[]):
		if _premise_met(tier.premise,{"owner":player,"uid":-1,"card":card,"chosen":-1},false): surcharge=maxi(surcharge,int(tier.amount))
	if card.definition.has("cost_override") and _premise_met(card.definition.cost_override.premise,{"owner":player,"uid":-1,"card":card,"chosen":-1},false): return int(card.definition.cost_override.value)
	return maxi(0,cost+surcharge)

func _operation_cost(unit: Dictionary) -> int:
	var cost := int(_unit_definition(unit).get("operation_cost", 1))
	for layer in unit.get("operation_costs", []): cost = int(layer.cost_set) if layer.has("cost_set") else cost+int(layer.cost_delta)
	var fixed_cost := -1
	for effect in _field_effects(unit):
		if effect.op == "modify_operation_cost":
			if effect.has("cost_set"): fixed_cost=int(effect.cost_set)
			else: cost += int(effect.cost_delta)
	# A live fixed-cost aura remains exact even when additive costs change.
	return clampi(fixed_cost if fixed_cost>=0 else cost, 0, 12)

func attack_limit(unit: Dictionary) -> int:
	var result := 2 if _has_keyword(unit,"core.fury") else 1
	for layer in unit.get("attack_limits", []): result = int(layer.attacks)
	return result

func attacks_used(unit: Dictionary) -> int:
	# Older LAN/local servers only sent the single-attack exhausted flag.
	return int(unit.get("attacks_used", 1 if unit.get("attacked", false) else 0))

func _combat_damage(source: Dictionary, target: Dictionary, phase: String) -> int:
	var target_class: String = "hq" if target.is_empty() else str(_unit_definition(target).unit_class)
	var multiplier := 1
	var divisor := 1
	var rounding := "floor"
	var ignore_armor := false
	var attack_delta := 0
	var attack_base: int = source.attack
	for layer in source.get("combat_damage_rules", []):
		if layer.has("target_filter") and not _matches_unit_filter(target,layer.target_filter): continue
		if layer.has("target_attack_compare") and (target.is_empty() or not _compare(int(target.attack),layer.target_attack_compare,int(source.attack))): continue
		if (layer.against == "any" or layer.against == target_class or (not target.is_empty() and layer.against in _unit_classes(target))) and layer.applies_to in ["both", phase] and (layer.get("target_row","any") == "any" or (not target.is_empty() and layer.target_row == target.row)):
			multiplier = int(layer.multiplier)
			divisor = int(layer.get("divisor",1))
			rounding = str(layer.get("rounding","floor"))
			ignore_armor = bool(layer.get("ignore_armor",false))
			attack_delta = int(layer.get("attack_delta",0))
			attack_base = int(target.attack) if layer.get("attack_base")=="opponent" and not target.is_empty() else int(source.attack)
	var numerator := maxi(0,attack_base+attack_delta) * multiplier
	var raw_damage := int((numerator + divisor - 1) / divisor) if rounding == "ceil" else int(numerator / divisor)
	if target.is_empty(): return raw_damage
	if _has_keyword(target,"core.immune"): return 0
	raw_damage = _incoming_damage(target,raw_damage,"combat",source)
	var blocked := 0 if ignore_armor else mini(raw_damage, stack_count(target, "heavy_armor"))
	_stat("armor_blocked", int(target.owner), target.card, blocked, {"source_uid": source.uid, "target_uid": target.uid})
	return maxi(0, raw_damage - blocked)

func stack_count(unit: Dictionary, stack: String) -> int:
	var amount := 0
	var maximum := 100 if stack == "heavy_armor" else 99
	for layer in unit.get("stack_layers", []):
		if layer.stack == stack:
			if layer.mode == "range": amount = clampi(amount + int(layer.offset), int(layer.low), int(layer.high))
			else: amount = clampi(int(layer.amount) if layer.mode == "set" else amount + int(layer.amount), 0, maximum)
	if stack == "heavy_armor":
		for effect in _field_effects(unit):
			if effect.op == "modify_stacks" and effect.stack == stack: amount += int(effect.amount)
	return clampi(amount,0,maximum)

func _merge_counter_layer(layers: Array, layer: Dictionary) -> void:
	# Compose adjacent transformations for the same counter/lifetime. This preserves
	# clipping after every operation and temporary-layer expiry without unbounded history.
	for i in range(layers.size()-1,-1,-1):
		var old: Dictionary = layers[i]
		if old.get("stack","") != layer.stack: continue
		if old.expires_turn != layer.expires_turn or old.get("expires_at_start",false) != layer.get("expires_at_start",false) or old.get("persistent",false) != layer.persistent or old.get("source_card_id","") != layer.get("source_card_id",""): break
		var low := int(old.amount) if old.mode == "set" else int(old.get("low",0))
		var high := int(old.amount) if old.mode == "set" else int(old.get("high",99))
		var offset := 0 if old.mode == "set" else int(old.get("offset",old.get("amount",0)))
		if layer.mode == "set": low=int(layer.amount); high=low; offset=0
		else:
			offset += int(layer.amount)
			low=clampi(low+int(layer.amount),0,99); high=clampi(high+int(layer.amount),0,99)
		layer=layer.duplicate(true);layer.mode="range";layer["offset"]=offset;layer["low"]=low;layer["high"]=high
		if low == high: layer["offset"]=0
		layers.remove_at(i)
		break
	layers.append(layer)

func _custom_stack(unit: Dictionary, effect: Dictionary, context: Dictionary) -> void:
	var names := {}
	for layer in unit.stack_layers:
		if layer.stack != "heavy_armor": names[layer.stack]=true
	if not names.has(effect.stack) and names.size() >= 16:
		_fault="RULE_BUDGET_EXCEEDED";return
	var before := stack_count(unit,effect.stack)
	var layer := {"modifier_id":int(state.next_modifier_id),"source_card_id":_enhancement_source(context),"source_uid":context.uid,"expires_turn":int(state.turn) if effect.duration == "end_of_turn" else -1,"persistent":effect.duration=="match","stack":effect.stack,"amount":int(effect.amount),"mode":"set" if effect.op=="set_stacks" else "add"}
	layer.merge(_effect_expiry(effect.duration,int(context.owner)),true)
	state.next_modifier_id += 1
	_merge_counter_layer(unit.stack_layers,layer)
	if effect.duration == "match":
		if not unit.card.has("match_layers"): unit.card["match_layers"]=[]
		var saved: Array=[]
		for item in unit.card.match_layers:
			if item.bucket=="stack_layers" and item.layer.stack==effect.stack: saved.append(item.layer)
		unit.card.match_layers=unit.card.match_layers.filter(func(item):return item.bucket!="stack_layers" or item.layer.stack!=effect.stack)
		_merge_counter_layer(saved,layer.duplicate(true))
		for item in saved:unit.card.match_layers.append({"bucket":"stack_layers","layer":item})
	if unit.stack_layers.size()+unit.modifiers.size()+unit.grants.size()+unit.attack_limits.size()+unit.operation_costs.size()+unit.combat_damage_rules.size()+unit.get("extra_rules",[]).size()>64:
		_fault="RULE_BUDGET_EXCEEDED";return
	_recompute(unit)
	if stack_count(unit,effect.stack)>before: _queue_stack_event(unit,effect.stack)

func _queue_stack_event(unit: Dictionary, stack: String) -> void:
	for entry in _abilities(_context(unit.owner,unit.uid,unit.card),"on_stack_gained"):
		if entry.ability.stack != stack: continue
		entry.context["trigger_unit"]=int(unit.uid)
		# Recheck the condition on execution, so one threshold consumption cannot
		# reward queued gains again after the counter has already been cleared.
		entry["requires_source"]=true
		entry["stack_event"]=true
		_events.append(entry)
		_spend("events")

func _movement_blocks_attack(unit: Dictionary) -> bool:
	return bool(unit.get("moved", false)) and not _separate_move_and_attack(unit)

func _separate_move_and_attack(unit: Dictionary) -> bool:
	var kind: String = _unit_definition(unit).unit_class
	return kind == "tank" or kind in ["fighter", "bomber"] and _has_keyword(unit,"core.blitz")

func smokescreen_active(unit: Dictionary) -> bool:
	return not unit.is_empty() and unit.row != "front" and _has_keyword(unit,"core.smokescreen")

func guard_active(unit: Dictionary) -> bool:
	return _has_keyword(unit,"core.guard") and not smokescreen_active(unit)

func _refresh_attacks(unit: Dictionary) -> void:
	unit["attack_limit"] = attack_limit(unit)
	unit.attacked = bool(unit.get("attack_locked", false)) or _movement_blocks_attack(unit) or attacks_used(unit) >= int(unit.attack_limit)

func can_move(uid: int) -> bool:
	if state.is_empty() or state.winner != -1 or state.has("pending_choice"):
		return false
	var unit := _unit(uid)
	if unit.is_empty() or unit.owner != state.active_player or unit.row != "support" or unit.moved or not _ready(unit):
		return false
	# Read used attacks, not the exhausted flag: extra attacks cannot bypass this.
	if attacks_used(unit) > 0 and not _separate_move_and_attack(unit):
		return false
	return state.players[unit.owner].credits >= _operation_cost(unit) and _count_row(1 - int(unit.owner), "front") == 0 and _count_row(-1, "front") < 5

func _activation_entry(uid: int, index: int) -> Dictionary:
	var unit:=_unit(uid)
	if unit.is_empty(): return {}
	for entry in _abilities(_context(unit.owner,uid,unit.card),"on_activate"):
		if int(entry.ability_index)==index: return entry
	return {}

func activation_error(player: int, uid: int, index: int) -> String:
	if state.is_empty() or state.winner!=-1: return "对局已结束"
	if state.has("mulligan"): return "请先完成开局换牌"
	if state.has("pending_choice"): return "请先完成当前选择"
	if player!=state.active_player: return "等待己方回合"
	var unit:=_unit(uid)
	if unit.is_empty() or unit.owner!=player or unit.hp<=0: return "只能发动自己的在场单位"
	if unit.get("suppressed",false): return "抑制期间无法发动"
	var entry:=_activation_entry(uid,index)
	if entry.is_empty(): return "此主动能力已失效"
	var mark: Dictionary=unit.get("activation_counts",{}).get(str(index),{})
	if int(mark.get("turn",-1))==int(state.turn): return "本回合已发动"
	if entry.ability.has("premise") and not _premise_met(entry.ability.premise,entry.context): return "尚未满足发动条件"
	if entry.ability.has("target") and _ability_targets(entry).is_empty(): return "没有合法目标"
	return ""

func _activate(player: int, uid: int, index: int) -> void:
	var entry:=_activation_entry(uid,index)
	var unit:=_unit(uid)
	unit.get_or_add("activation_counts",{})[str(index)]={"turn":int(state.turn)}
	# Ability use is separate from normal movement/attack and costs no credits.
	_run_roots([entry])

func legal_targets(player: int, action: Dictionary) -> Array:
	var result: Array = []
	if state.is_empty() or state.winner != -1 or not player in [0, 1]:
		return result
	if state.has("pending_choice"):
		var choice: Dictionary = state.pending_choice
		if action.get("type") == "choose_target" and player == choice.owner and action.get("choice_id") == choice.choice_id:
			return choice.targets.duplicate()
		return result
	if player != state.active_player: return result
	if action.get("type", "") == "play":
		var entry := _hand(player, str(action.get("hand_id", "")))
		if entry.is_empty():
			return result
		var definition: Dictionary = entry.card.definition
		if definition.kind == "hq": return []
		if state.players[player].credits < play_cost(player,entry.card) or (definition.kind == "unit" and (_count_row(player, "support") >= 4 or not _unit_entry_allowed(player))):
			return result
		if definition.kind == "counter" and state.players[player].get("counters", []).size() >= 3:
			return result
		if definition.play_target == null:
			return [-1]
		for unit in state.units:
			if _explicit_target_blocked(unit,entry.card): continue
			if (definition.play_target.side == "any" or (unit.owner == player) == (definition.play_target.side == "ally")) and (definition.play_target.row == "any" or definition.play_target.row == unit.row) and _matches_class(unit,definition.play_target):
				result.append(unit.uid)
		if definition.play_target.get("include_hq",false):
			for seat in [0,1]:
				if definition.play_target.side == "any" or ((seat==player)==(definition.play_target.side=="ally")): result.append(-101-seat)
		if result.is_empty(): return [-1]
	elif action.get("type", "") == "attack":
		var unit := _unit(int(action.get("uid", -1)))
		if unit.is_empty() or unit.owner != player or bool(unit.get("attack_locked", false)) or _movement_blocks_attack(unit) or attacks_used(unit) >= attack_limit(unit) or not _ready(unit) or state.players[player].credits < _operation_cost(unit):
			return result
		var ranged: bool = _unit_definition(unit).unit_class in ["artillery", "fighter", "bomber"]
		for enemy in state.units:
			if not _fighter_cover_allows(unit,enemy.row,enemy.uid): continue
			if enemy.owner == player:
				continue
			if smokescreen_active(enemy): continue
			if ranged or (unit.row == "support" and enemy.row == "front") or (unit.row == "front" and enemy.row == "support"):
				if _guard_allows(enemy.owner, enemy.row, enemy.uid, str(_unit_definition(unit).unit_class)):
					result.append(enemy.uid)
		if _fighter_cover_allows(unit,"support",-1) and (ranged or unit.row == "front") and _guard_allows(1 - player, "support", -1, str(_unit_definition(unit).unit_class)):
			result.append(-1)
	result.sort()
	return result

func _guard_allows(owner: int, row: String, target_uid: int, attacker_class: String = "") -> bool:
	if attacker_class in ["artillery","bomber"]: return true
	var target := _unit(target_uid)
	if not target.is_empty() and guard_active(target): return true
	var line := line_order(owner,row)
	var index := line.find(target_uid)
	if index < 0: return false
	for adjacent in [index-1,index+1]:
		if adjacent < 0 or adjacent >= line.size() or int(line[adjacent]) < 0: continue
		if guard_active(_unit(int(line[adjacent]))): return false
	return true

func _action_error(player: int, action: Dictionary) -> String:
	if state.is_empty() or state.winner != -1:
		return "对局未开始或已结束"
	if not player in [0, 1]:
		return "玩家身份无效"
	var type_value: Variant = action.get("type", null)
	if not type_value is String:
		return "行动类型无效"
	var fields := {"activate":["type","uid","ability_index"],"mulligan":["type","hand_ids"],"choose_card": ["type","choice_id","option_index"], "choose_target": ["type", "choice_id", "target_uid"], "play": ["type", "hand_id", "target_uid", "position"], "move": ["type", "uid", "position"], "attack": ["type", "uid", "target_uid"], "end_turn": ["type"], "concede": ["type"]}
	if not fields.has(type_value):
		return "未知行动"
	for key in action:
		if not key in fields[type_value]:
			return "行动包含未知字段"
	if type_value == "concede":
		return ""
	if type_value=="mulligan":
		if not state.has("mulligan") or state.mulligan.confirmed[player]: return "开局换牌已确认"
		if not action.get("hand_ids") is Array or action.hand_ids.size()>5: return "换牌格式无效"
		var seen: Array=[]
		for id in action.hand_ids:
			if not id is String or id in seen or _hand(player,id).is_empty(): return "换牌必须选择自己的初始手牌，且不能重复"
			seen.append(id)
		return ""
	if state.has("mulligan"): return "请等待双方确认开局手牌"
	if type_value == "choose_card":
		var choice: Dictionary = state.get("pending_choice",{})
		if not action.get("choice_id") is String or not Runtime._integer(action.get("option_index")): return "选牌格式无效"
		if choice.get("kind", "unit") == "unit" or choice.get("owner") != player or choice.get("choice_id") != action.choice_id or int(action.option_index) < 0 or int(action.option_index) >= choice.get("options",[]).size(): return "此选牌已过期或候选无效"
		return ""
	if type_value == "choose_target":
		if state.get("pending_choice",{}).get("kind","unit") != "unit": return "请完成当前选牌"
		if not action.get("choice_id") is String or not Runtime._integer(action.get("target_uid")):
			return "目标选择格式无效"
		if not int(action.target_uid) in legal_targets(player, action): return "此选择已过期或目标无效"
		return ""
	if state.has("pending_choice"): return "请先完成效果目标选择"
	if player != state.active_player:
		return "尚未轮到你"
	if type_value=="activate":
		if not Runtime._integer(action.get("uid")) or not Runtime._integer(action.get("ability_index")) or action.uid<1 or action.ability_index<0 or action.ability_index>63: return "主动能力格式无效"
		return activation_error(player,int(action.uid),int(action.ability_index))
	if type_value in ["move", "attack"] and (not action.has("uid") or not Runtime._integer(action.uid)):
		return "单位 ID 无效"
	if action.has("target_uid") and not Runtime._integer(action.target_uid):
		return "目标 ID 无效"
	if type_value == "play":
		if not action.get("hand_id", null) is String:
			return "手牌 ID 无效"
		if not int(action.get("target_uid", -1)) in legal_targets(player, action):
			return "无法打出：检查费用、后援格和目标"
	if action.has("position"):
		if not Runtime._integer(action.position) or action.position < 0: return "阵线位置无效"
		if type_value == "play":
			if _hand(player,action.hand_id).card.definition.kind != "unit" or action.position > _count_row(player,"support")+1: return "部署位置无效"
		elif type_value == "move" and action.position > _count_row(-1,"front"): return "前线位置无效"
	if type_value == "move" and not can_move(int(action.uid)):
		return "无法推进：检查费用、部署限制、单位类型和前线"
	if type_value == "attack" and (not action.has("target_uid") or not int(action.target_uid) in legal_targets(player, action)):
		return "无法攻击该目标"
	return ""

func apply_action(player: int, action: Dictionary) -> String:
	var error := _action_error(player, action)
	if not error.is_empty():
		return error
	if action.type=="mulligan": return _confirm_mulligan(player,action.hand_ids)
	var next_seq: int = int(state.state_seq) + 1
	var resolution: Dictionary
	if action.type in ["choose_target","choose_card"]:
		resolution = state._resolution.duplicate(true)
		resolution.choices.append(int(action.option_index if action.type == "choose_card" else action.target_uid))
	else:
		var origin := state.duplicate(true)
		origin.erase("_resolution")
		origin.erase("pending_choice")
		resolution = {"origin": origin, "player": player, "action": action.duplicate(true), "choices": [], "id": str(next_seq)}
	# Replay the frozen initiating action with the recorded decisions. This keeps
	# nested death/counter/turn continuations deterministic and budgets cumulative.
	# Only the new telemetry suffix is exported; the origin never leaves authority.
	state = resolution.origin.duplicate(true)
	_reset_budget()
	_choice_answers = resolution.choices
	_choice_cursor = 0
	_resolution_id = resolution.id
	player = int(resolution.player)
	action = resolution.action
	match action.type:
		"activate": _activate(player,int(action.uid),int(action.ability_index))
		"setup_turn": _start_turn()
		"concede":
			_stat("concede", player)
			state.winner = 1 - player
			_log("玩家 %d 投降" % (player + 1))
		"play": _play(player, action.hand_id, int(action.get("target_uid", -1)),int(action.get("position",-1)))
		"move":
			var unit := _unit(int(action.uid))
			_consume_keyword(unit,"core.smokescreen")
			state.players[player].credits -= _operation_cost(unit)
			_stat("operation_spent", player, unit.card, _operation_cost(unit))
			_stat("move", player, unit.card, 1, {"uid":unit.uid})
			_remove_from_line(unit)
			unit.row = "front"
			_position_unit(unit,int(action.get("position",-1)))
			unit.moved = true
			if _unit_definition(unit).unit_class == "infantry":
				unit.attack_locked = true
			_refresh_attacks(unit)
			_log("%s 推进至前线" % _unit_definition(unit).name)
			_checkpoint()
			_drain_deaths()
			_complete_action(unit,"move")
			if state.winner==-1 and _fault.is_empty() and not _unit(unit.uid).is_empty():
				_emit_unit_event(player,"unit_moved",unit.uid,unit.card)
				_drain_deaths()
		"attack": _attack(int(action.uid), int(action.target_uid))
		"end_turn": _end_turn()
	# Settle prerequisites even when the action had no immediate effect roots.
	if _fault.is_empty() and int(state.winner) == -1:
		_checkpoint()
		_drain_deaths()
	if _fault == "AWAITING_CHOICE":
		state["_resolution"] = resolution
		state.state_seq = next_seq
		return ""
	if not _fault.is_empty():
		state = resolution.origin
		state.winner = 3
		state["error"] = _fault
		state.state_seq = next_seq
		state.log.append("对局中止：" + _fault)
		return _fault
	state.state_seq = next_seq
	return ""

func _new_unit(owner: int, card: Dictionary, token_id: String = "", from_deck: bool = false, position: int = -1) -> Dictionary:
	var unit := {"uid": int(state.next_uid), "owner": owner, "row": "support", "card": card.duplicate(true), "token_id": token_id, "attack": 0, "hp": 0, "max_hp": 0, "damage_taken": 0, "modifiers": [], "grants": [], "attack_limits": [], "operation_costs": [], "combat_damage_rules": [], "extra_rules": [], "stack_layers": [], "stacks": {"heavy_armor": 0}, "attacks_used": 0, "attack_locked": false, "bound_targets": {}, "event_counts": {}, "damage_progress": {}, "is_veteran":bool(card.get("veteran_form",false)), "has_attacked_in_play": false, "consumed_keyword_history": {}, "equipment": {}, "born_turn": int(state.turn), "moved": false, "attacked": false}
	state.next_uid += 1
	for saved in card.get("match_layers",[]) + card.get("pending_layers",[]):
		var layer: Dictionary = saved.layer.duplicate(true)
		layer["modifier_id"] = int(state.next_modifier_id)
		state.next_modifier_id += 1
		unit[saved.bucket].append(layer)
	unit["ability_layers"] = card.get("match_abilities",[]).duplicate(true) + card.get("pending_abilities",[]).duplicate(true)
	unit.card.erase("pending_layers")
	unit.card.erase("pending_abilities")
	_recompute(unit)
	state.units.append(unit)
	_position_unit(unit,position)
	if _has_keyword(unit,"core.alpine"):
		var bonus := 0
		for other in state.units:
			if other.uid != unit.uid and other.owner == owner and _has_keyword(other,"core.alpine"): bonus += 1
		unit["alpine_bonus"] = bonus
		_recompute(unit)
	_stat("summon" if from_deck or not token_id.is_empty() else "deploy", owner, card, 1, {"uid": unit.uid, "token_id": token_id, "from_deck": from_deck})
	_log("%s 进入后援线" % _unit_definition(unit).name)
	return unit

func _recompute(unit: Dictionary) -> void:
	unit["stacks"] = {"heavy_armor": stack_count(unit, "heavy_armor")}
	for layer in unit.get("stack_layers",[]):
		if layer.stack != "heavy_armor": unit.stacks[layer.stack] = stack_count(unit,layer.stack)
	var definition := _unit_definition(unit)
	var attack: int = int(definition.attack)
	var health: int = int(definition.health)
	var capacity_only := 0
	var damage_baseline := 0
	var innate_bonus := int(unit.get("alpine_bonus",0)) + int(unit.get("mobilize_bonus",0))
	attack += innate_bonus
	health += innate_bonus
	for modifier in unit.modifiers:
		if modifier.has("attack_set"): attack = int(modifier.attack_set)
		if modifier.has("health_set"):
			health = int(modifier.health_set)
			capacity_only = 0
			damage_baseline = int(modifier.damage_baseline)
		attack += int(modifier.attack_delta)
		health += int(modifier.health_delta)
		if modifier.get("health_mode")=="max_only": capacity_only += int(modifier.health_delta)
	for effect in _field_effects(unit):
		if effect.op == "modify_stats":
			attack += int(effect.attack_delta)
			health += int(effect.health_delta)
			if effect.get("health_mode")=="max_only": capacity_only += int(effect.health_delta)
	unit.attack = clampi(attack, 0, 30)
	unit.max_hp = clampi(health, 0, 30)
	unit["capacity_only"] = capacity_only
	unit["damage_baseline"] = damage_baseline
	if damage_baseline != 0:
		unit.damage_taken = maxi(int(unit.damage_taken),damage_baseline-capacity_only)
	unit.hp = mini(int(unit.max_hp),int(unit.max_hp) - capacity_only - int(unit.damage_taken) + damage_baseline)
	unit["operation_cost"] = _operation_cost(unit)
	_refresh_attacks(unit)

func _context(owner: int, uid: int, card: Dictionary, chosen: int = -1) -> Dictionary:
	var unit := _unit(uid)
	return {"owner": owner, "uid": uid, "card": card.duplicate(true), "chosen": chosen, "chosen_snapshot":_unit(chosen).duplicate(true), "previous_cards":state.players.map(func(p):return str(p.get("last_played_kind",""))), "previous_card_details":state.players.map(func(p):return p.get("last_played_card",{}).duplicate(true)), "bound_targets":unit.get("bound_targets",{}).duplicate(true), "ability_layers":unit.get("ability_layers",[]).duplicate(true), "suppressed":bool(unit.get("suppressed",false)), "salvage":_has_keyword(unit,"core.salvage"),"source_row":unit.get("row","support"),"source_position":line_order(owner,unit.get("row","support")).find(uid)}

func _variant_card(card: Dictionary, changes: Dictionary, reason: String) -> Dictionary:
	var result := card.duplicate(true)
	for key in ["match_layers","pending_layers","match_abilities","pending_abilities","match_ability_sources","hand_cost_layers","match_cost_layers"]: result.erase(key)
	result.source.merge(changes,true)
	result.definition.merge(changes,true)
	result.definition_hash = Runtime.sha(result.source)
	result.compiled_program_hash = Runtime.sha({"compiler_version":"card-compiler-1","definition_hash":result.definition_hash,"keyword_bindings":result.keyword_bindings,"expanded_definition":result.definition})
	result["generated_origin"] = card.get("generated_origin",{"definition_hash":card.definition_hash,"telemetry_ref":card.get("telemetry_ref",{})}).duplicate(true)
	result["generated_token_id"] = reason
	return result

func _source_key(context: Dictionary) -> String:
	return str(context.owner)+":"+str(context.uid)+":"+str(context.card.get("definition_hash",""))

func _destroyer(unit: Dictionary, context: Dictionary) -> void:
	# Capture the killer before simultaneous deaths remove it from the board.
	if not unit.has("destroyer"):
		unit["destroyer"] = {"owner":int(context.owner),"salvage":bool(context.get("salvage",false)),"uid":int(context.uid),"source_key":_source_key(context),"unit_classes":_unit_classes(_unit(int(context.uid))) if not _unit(int(context.uid)).is_empty() else []}

func _unit_damage(unit: Dictionary, amount: int, context: Dictionary) -> void:
	if context.get("damage_kind","effect") != "combat": amount = _incoming_damage(unit,amount,"effect",_unit(int(context.get("uid",-1))),dict_merge(context.card,{"damage_owner":context.owner}))
	if _has_keyword(unit,"core.immune"): amount = 0
	_damage_stat(context.owner,context.card,amount,int(unit.hp),unit.owner,unit.uid,unit.card)
	if amount > 0:
		_consume_keyword(unit,"core.mobilize")
		if unit.hp > 0 and amount >= unit.hp: _destroyer(unit,context)
		var actual := mini(amount,maxi(0,int(unit.hp)))
		unit.damage_taken += amount
		_queue_unit_event(unit,"on_damaged",int(context.uid),context.card,actual)
	_recompute(unit)

func _suppress(unit: Dictionary) -> void:
	unit["suppressed"] = true
	unit.card.erase("match_layers")
	unit.card.erase("match_abilities")
	unit.card.erase("match_ability_sources")
	unit["ability_layers"] = []
	for key in ["modifiers","grants","attack_limits","operation_costs","combat_damage_rules","extra_rules","stack_layers"]: unit[key] = []
	unit["equipment"] = {}
	unit["equipment_sources"] = []
	unit["alpine_bonus"] = 0
	unit["mobilize_bonus"] = 0
	unit.damage_taken = 0
	_recompute(unit)

func _leave_battlefield(unit: Dictionary, return_hand: bool, cost_effect: Dictionary = {}, cost_context: Dictionary = {}) -> void:
	if return_hand:
		_self_departure_event(unit,"own_unit_returned")
		if not _fault.is_empty() or _unit(unit.uid).is_empty(): return
	var departure := _context(unit.owner,unit.uid,unit.card)
	_remove_from_line(unit)
	state.units.erase(unit)
	_stat("return_to_hand" if return_hand else "remove",unit.owner,unit.card,1,{"uid":unit.uid})
	if return_hand:
		var returned: Dictionary=_departure_card(unit.card)
		if unit.card.has("veteran_base"):
			returned=unit.card.veteran_base.duplicate(true)
			# Upgrading already cleared the old enhancements. Only permanent
			# enhancements gained after promotion accompany the base form home.
			for key in ["match_layers","match_abilities","match_ability_sources","match_cost_layers"]:
				if unit.card.has(key): returned[key]=unit.card[key].duplicate(true)
		if cost_effect.has("cost_delta"):
			_add_hand_cost(returned,cost_effect,cost_context)
			if not _fault.is_empty(): return
		_receive_card(unit.owner,returned,"return",true)
	_after_leave(unit,departure)
	if return_hand: _emit_unit_event(unit.owner,"unit_returned",unit.uid,unit.card)

func _generated_card(parent: Dictionary, token_id: String, creator_uid: int = -1) -> Dictionary:
	var source := {}
	var expanded := {}
	for pair in [[parent.source, source], [parent.definition, expanded]]:
		var library: Dictionary = pair[0]
		var result: Dictionary = pair[1]
		for token in library.tokens:
			if token.token_id != token_id: continue
			result.merge(token.duplicate(true))
			result.erase("token_id")
			var kind: String = result.get("kind", "unit")
			result["kind"] = kind
			result["cost"] = int(result.get("cost", 1))
			result["operation_cost"] = int(result.get("operation_cost", 1 if kind == "unit" else 0))
			result["abilities"] = result.get("abilities", [])
			result["play_target"] = result.get("play_target")
			result["flavor_text"] = result.get("flavor_text", "")
			result["tokens"] = library.tokens.duplicate(true)
			result["schema_version"] = library.schema_version
			result["ruleset_version"] = library.ruleset_version
			result["appearance"] = {"emblem": result.unit_class if kind == "unit" else kind}
			if library.has("faction_id"): result["faction_id"] = library.faction_id
			for key in ["sin","rarity"]:
				if library.get("veteran",{}).get("token_id")==token_id and not result.has(key) and library.has(key): result[key]=library[key]
	if expanded.is_empty():
		_fault = "INVALID_TOKEN_REFERENCE"
		return {}
	var origin: Dictionary = parent.get("generated_origin", {"definition_hash":parent.get("definition_hash", ""), "telemetry_ref":parent.get("telemetry_ref", {})})
	var definition_hash := Runtime.sha(source)
	var bindings: Array = parent.get("keyword_bindings", [])
	var program := {"compiler_version":"card-compiler-1","definition_hash":definition_hash,"keyword_bindings":bindings,"expanded_definition":expanded}
	return {"ok":true,"definition":expanded,"source":source,"definition_hash":definition_hash,"compiled_program_hash":Runtime.sha(program),"keyword_bindings":bindings.duplicate(true),"compiler_version":"card-compiler-1","generated_origin":origin.duplicate(true),"generated_token_id":token_id,"art_id":parent.get("token_art_ids",{}).get(token_id,""),"token_art_ids":parent.get("token_art_ids",{}).duplicate(true),"creator_uid":creator_uid if creator_uid >= 0 else int(parent.get("creator_uid",-1)),"origin_card":parent.get("origin_card",parent).duplicate(true)}

func _initialize_innate_rules(unit: Dictionary, restoring: bool = false) -> void:
	var context := _context(unit.owner, unit.uid, unit.card)
	for ability in unit.card.definition.abilities:
		if ability.trigger != "on_play": continue
		for rule in ability.effects:
			if restoring and rule.get("duration")=="match": continue
			if not ability.has("premise") and rule.get("target") == "self" and (rule.get("duration") == "battle" or rule.get("duration") == "match" and rule.op in ["grant_unit_class","set_combat_priority","modify_incoming_damage","grant_order_target_reward"]) and rule.op in ["set_attack_limit", "modify_operation_cost", "set_combat_damage_multiplier", "modify_stacks", "set_stacks", "set_combat_priority", "grant_unit_class", "modify_incoming_damage", "grant_order_target_reward"]:
				_spend("ops")
				if not _fault.is_empty(): return
				_effect(rule, context)

func _initialize_summoned_unit(unit: Dictionary) -> void:
	var context := _context(unit.owner, unit.uid, unit.card)
	_initialize_innate_rules(unit)
	_summons.append_array(_binding_entries(context))
	_summons.append_array(_abilities(context, "on_summon"))
	_emit_entry_event(unit)

func _abilities(context: Dictionary, trigger: String) -> Array:
	var entries := []
	var all_abilities: Array = ([] if context.get("suppressed",false) else context.card.definition.abilities) + context.get("ability_layers",[])
	for index in all_abilities.size():
		var ability: Dictionary = all_abilities[index]
		if int(ability.get("expires_turn",-1)) >= 0 and int(ability.expires_turn) < int(state.turn): continue
		if ability.trigger == trigger and ability.get("zone","battlefield")==context.get("zone","battlefield"):
			entries.append({"context":context.duplicate(true),"ability":ability.duplicate(true),"ability_index":index})
	return entries

func _binds_on_deployment(ability: Dictionary) -> bool:
	return ability.has("target") and ability.trigger in ["on_death","own_turn_start","own_turn_end"] and ability.target.get("timing","deploy")=="deploy"

func _binding_entries(context: Dictionary) -> Array:
	var entries := []
	var all_abilities: Array = ([] if context.get("suppressed",false) else context.card.definition.abilities) + context.get("ability_layers",[])
	for index in all_abilities.size():
		var ability: Dictionary = all_abilities[index]
		if _binds_on_deployment(ability):
			entries.append({"context":context.duplicate(true),"ability":ability.duplicate(true),"ability_index":index,"bind_only":true})
	return entries

func _ability_targets(entry: Dictionary) -> Array:
	var candidates := []
	var selector: Dictionary = entry.ability.target
	for unit in state.units:
		if _explicit_target_blocked(unit,entry.context.card): continue
		if (selector.side=="any" or (unit.owner==entry.context.owner)==(selector.side=="ally")) and (selector.row=="any" or selector.row==unit.row) and _matches_class(unit,selector): candidates.append(int(unit.uid))
	# A requested evolution must exist on the target's own live schedule.
	var chosen_effects: Array=Runtime.effect_leaves(entry.ability.get("effects",[])).filter(func(e):return e.get("target")=="chosen")
	if not chosen_effects.is_empty() and chosen_effects.all(func(e):return e.op=="trigger_evolution"):
		candidates=candidates.filter(func(uid):return not _evolution_schedule(uid).is_empty())
	candidates.sort()
	if selector.get("include_hq",false):
		for seat in [0,1]:
			if selector.side == "any" or ((seat==entry.context.owner)==(selector.side=="ally")): candidates.append(-101-seat)
	return candidates

func _choose_ability_target(entry: Dictionary) -> int:
	var selector: Dictionary=entry.ability.target
	var candidates:=_ability_targets(entry)
	if candidates.is_empty(): return -1
	if _choice_cursor>=64:
		_fault="RULE_BUDGET_EXCEEDED"
		return -1
	if _choice_cursor>=_choice_answers.size():
		state["pending_choice"]={"choice_id":_resolution_id+"-"+str(_choice_cursor),"owner":entry.context.owner,"source_uid":entry.context.uid,"source_name":entry.context.card.definition.name,"trigger":entry.ability.trigger,"selection_timing":"deploy" if entry.get("bind_only",false) else "trigger","side":selector.side,"row":selector.row,"ability_index":entry.get("ability_index",0),"targets":candidates,"unit_classes":selector.get("unit_classes",[])}
		_fault="AWAITING_CHOICE"
		return -1
	var answer := int(_choice_answers[_choice_cursor])
	if not answer in candidates:
		_fault="INVALID_CHOICE_REPLAY"
		return -1
	_choice_cursor+=1
	return answer

func _run_roots(roots: Array) -> void:
	for entry in roots:
		if state.winner != -1 or not _fault.is_empty():
			return
		_run_ability(entry)
		_drain_deaths()

func _run_ability(entry: Dictionary) -> void:
	if entry.context.get("zone")=="hand" and _hand(entry.context.owner,entry.context.get("hand_instance_id","")).is_empty(): return
	if entry.has("scheduled_lifetime"):
		if not _schedule_alive({"source_uid":entry.context.uid,"chosen":entry.scheduled_chosen,"lifetime":entry.scheduled_lifetime,"played_turn":entry.get("scheduled_turn",-1)}): return
	# Revalidate previously chosen targets for delayed orders and later groups.
	# Automatic/self/random/area targets are deliberately unaffected.
	if _explicit_target_blocked(_unit(int(entry.context.get("chosen",-1))),entry.context.card):
		entry.context.chosen=-1
	if entry.get("requires_source",false):
		var source := _unit(entry.context.uid)
			
		if source.is_empty() or source.get("suppressed",false) or source.hp <= 0 or source.card.definition_hash != entry.context.card.definition_hash: return
	if entry.get("bind_only",false):
		var unit := _unit(entry.context.uid)
		if unit.is_empty() or unit.get("suppressed",false): return
		var chosen := _choose_ability_target(entry)
		if not _fault.is_empty(): return
		if not unit.has("bound_targets"): unit["bound_targets"]={}
		unit.bound_targets[str(entry.ability_index)]=chosen
		_stat("target_bound",unit.owner,unit.card,1,{"source_uid":unit.uid,"target_uid":chosen,"ability_index":entry.ability_index})
		return
	if not entry.get("premise_checked",false) and entry.ability.has("premise") and not _premise_met(entry.ability.premise, entry.context): return
	if entry.get("stack_event",false) and entry.ability.has("limit"):
		var source := _unit(entry.context.uid)
		var key := _event_key(entry)
		if int(source.event_counts.get(key,0))>=int(entry.ability.limit): return
		source.event_counts[key]=int(source.event_counts.get(key,0))+1
	var once: String=entry.context.get("once_per_card","")
	if not once.is_empty():
		var recipient := _unit(int(entry.context.get("trigger_unit",-1)))
		if recipient.is_empty(): return
		if not Runtime.effect_leaves(entry.ability.effects).any(func(e): return e.get("target")=="trigger_unit" and _matches_unit_filter(recipient,e.get("unit_filter",{}))): return
		var key := str(entry.context.owner)+":"+_enhancement_source(entry.context)+":"+once
		var marks: Dictionary=recipient.card.get_or_add("once_marks",{})
		if marks.has(key): return
		marks[key]=true
	_stat("trigger",entry.context.owner,entry.context.card,1,{"trigger":entry.ability.trigger,"source_uid":entry.context.uid})
	if entry.ability.has("target"):
		if _binds_on_deployment(entry.ability):
			# Follow the selected battlefield instance across row changes. If it
			# leaves, _targets yields nothing; unrelated effects still resolve.
			entry.context.chosen=int(entry.context.get("bound_targets",{}).get(str(entry.get("ability_index",-1)),-1))
			# A delayed binding must still be targetable; never choose a replacement.
			if _explicit_target_blocked(_unit(entry.context.chosen),entry.context.card): entry.context.chosen=-1
		else:
			entry.context.chosen=_choose_ability_target(entry)
			entry.context["chosen_snapshot"]=_unit(int(entry.context.chosen)).duplicate(true)
			if not _fault.is_empty(): return
			if entry.ability.trigger == "on_play" and entry.context.card.definition.kind == "order" and entry.context.chosen != -1:
				_order_target_reward(entry.context.owner,entry.context.chosen,entry.context.card)
	# Snapshot once. Each pass is a separate effect group: armor applies to
	# each packet; deaths and damage triggers resolve before the next pass.
	var repetitions := _premise_value(entry.ability.get("repeat",1),entry.context)
	if repetitions < 0 or repetitions > 16:
		_fault = "RULE_BUDGET_EXCEEDED"
		return
	for iteration in repetitions:
		entry.context["drawn_cards"]=[]
		entry.context["last_damage_killed"]=false
		entry.context["last_damage_kill_count"]=0
		for effect in entry.ability.effects:
			if state.winner!=-1 or not _fault.is_empty(): return
			_spend("ops")
			if not _fault.is_empty(): return
			_effect(effect,entry.context)
			_checkpoint()
		if entry.ability.has("repeat"): _drain_deaths()

func _drain_deaths() -> void:
	# Finish the current group first, then deaths before queued summon groups.
	# A work queue keeps arbitrarily chained token effects off the call stack.
	while (not _deaths.is_empty() or not _summons.is_empty() or not _events.is_empty()) and state.winner == -1 and _fault.is_empty():
		_run_ability(_deaths.pop_front() if not _deaths.is_empty() else (_summons.pop_front() if not _summons.is_empty() else _events.pop_front()))

func _ordered_units() -> Array:
	var units: Array = state.units.duplicate()
	units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.owner != b.owner:
			return a.owner == state.active_player
		return a.uid < b.uid)
	return units

func _condition_events() -> void:
	if state.winner != -1 or not _fault.is_empty(): return
	for unit in _ordered_units():
		if unit.hp <= 0 or unit.get("suppressed",false): continue
		for entry in _abilities(_context(unit.owner,unit.uid,unit.card),"when_condition"):
			var key := str(unit.card.definition_hash)+":"+str(entry.ability_index)
			var seen: Dictionary = unit.get_or_add("condition_seen",{})
			if seen.has(key) or not _premise_met(entry.ability.premise,entry.context): continue
			seen[key]=true
			entry["premise_checked"]=true
			entry["requires_source"]=true
			_events.append(entry)

func _checkpoint() -> void:
	for unit in state.units: _recompute(unit)
	var dead := []
	for unit in _ordered_units():
		if unit.hp <= 0 or unit.get("destroyed", false):
			dead.append(unit)
	var death_contexts := {}
	for unit in dead:
		var captured := _context(unit.owner,unit.uid,unit.card)
		captured["source_neighbors"] = _adjacent_targets("adjacent_to_self",captured)
		captured["killer_classes"] = unit.get("destroyer",{}).get("unit_classes",[]).duplicate()
		death_contexts[unit.uid] = captured
		var killer_key: String = unit.get("destroyer",{}).get("source_key","")
		if not killer_key.is_empty(): _action_kills[killer_key] = int(_action_kills.get(killer_key,0))+1
	# Capture all listeners before removing a simultaneous death batch.
	for fallen in dead:
		var deaths: Dictionary=state.get_or_add("unit_deaths_by_turn",{})
		if int(deaths.get("turn",-1))!=int(state.turn): deaths.clear();deaths.merge({"turn":int(state.turn),"0":0,"1":0})
		deaths[str(fallen.owner)]=int(deaths.get(str(fallen.owner),0))+1
		var killer := _unit(int(fallen.get("destroyer",{}).get("uid",-1)))
		if not killer.is_empty() and killer.owner!=fallen.owner and killer.hp>0 and not killer in dead:
			_queue_unit_event(killer,"on_kill",fallen.uid,fallen.card,0,false,{"trigger_unit_snapshot":fallen.duplicate(true)})
		_emit_hand_death(fallen)
		for listener in _ordered_units():
			_queue_unit_event(listener,"own_unit_died" if listener.owner == fallen.owner else "enemy_unit_died",fallen.uid,fallen.card,0,true)
		_queue_field_death(fallen)
		_headquarters_event(fallen.owner,"unit_died",fallen.uid,fallen.card)
	for unit in dead:
		var death_context: Dictionary = death_contexts[unit.uid]
		_remove_from_line(unit)
		state.units.erase(unit)
		_after_leave(unit,death_context)
		_stat("death", unit.owner, unit.card, 1, {"uid": unit.uid, "token_id": unit.token_id})
		_log("%s 阵亡" % _unit_definition(unit).name)
		if unit.token_id.is_empty():
			state.discard.append({"owner": unit.owner, "card": _departure_card(unit.card), "source_uid": unit.uid})
		if unit.token_id.is_empty() or unit.card.has("generated_origin"):
			_deaths.append_array(_abilities(death_context, "on_death"))
		var killer: Dictionary = unit.get("destroyer",{})
		if killer.get("salvage",false) and killer.owner == state.active_player and killer.owner != unit.owner:
			var copy := _variant_card(unit.card,{"attack":1,"health":1,"cost":mini(3,int(unit.card.definition.cost))},"salvage")
			_receive_card(killer.owner,copy,"salvage",true)
	if not dead.is_empty():
		_spend("cleanup")
		if _fault.is_empty(): _checkpoint()
	var zero_dead: bool = state.players[0].hp <= 0
	var one_dead: bool = state.players[1].hp <= 0
	if zero_dead or one_dead:
		state.winner = 2 if zero_dead and one_dead else (1 if zero_dead else 0)
		_log("对局结束：" + ("平局" if state.winner == 2 else "玩家 %d 获胜" % (int(state.winner) + 1)))

	_condition_events()

func _play(player: int, hand_id: String, chosen: int, position: int = -1) -> void:
	var entry := _hand(player, hand_id)
	var card: Dictionary = entry.card
	state.players[player].hand.erase(entry)
	if card.definition.kind == "counter":
		# Remains a hidden hand card for capacity, intel and discard. Arming is
		# private: no kredits spent, public log, play event or presentation.
		entry["armed_turn"]=int(state.turn)
		state.players[player].counters.append(entry)
		return
	var previous_cards: Array=state.players.map(func(p):return str(p.get("last_played_kind","")))
	var previous_details: Array=state.players.map(func(p):return p.get("last_played_card",{}).duplicate(true))
	_record_played_card(player,card)
	var paid_cost := play_cost(player,card)
	state.players[player].credits -= paid_cost
	card.erase("hand_cost_layers")
	_stat("play", player, card, 1, {"card_kind": card.definition.kind})
	_stat("deployment_spent", player, card, paid_cost)
	_log("玩家 %d 打出 %s" % [player + 1, card.definition.name])
	var prior_units := _ordered_units().map(func(u): return int(u.uid))
	var uid := -1
	if card.definition.kind == "unit":
		uid = _new_unit(player, card,"",false,position).uid
		_record_deployment(_unit(uid))
		if not _fault.is_empty(): return
		_run_roots(_binding_entries(_context(player,uid,card,chosen)))
		if state.winner!=-1 or not _fault.is_empty(): return
	elif card.definition.kind == "field":
		var old: Dictionary = state.get("field",{})
		if not old.is_empty():
			state.discard.append({"owner":old.owner,"card":old.card})
			_stat("field_replaced",old.owner,old.card)
		state["field"]={"owner":player,"card":card.duplicate(true),"played_turn":int(state.turn)}
		_checkpoint()
		_drain_deaths()
		if state.winner!=-1 or not _fault.is_empty(): return
	else:
		state.discard.append({"owner": player, "card": card})
		_consume_order_intercept(player)
		_trigger_counters(player, "enemy_order_played")
		if _counter_canceled or state.winner != -1 or not _fault.is_empty(): return
	if card.definition.kind == "order" and chosen != -1: _order_target_reward(player,chosen,card)
	var play_roots := _abilities(_context(player, uid, card, chosen), "on_play")
	var selected_roots := []
	# Lock all common-target branches before any result mutates their target.
	for root in play_roots:
		root.context["previous_cards"]=previous_cards.duplicate()
		root.context["previous_card_details"]=previous_details.duplicate(true)
		if root.ability.has("premise") and not root.ability.has("target") and not str(root.ability.premise).contains("source_destroyed_count"):
			if not _premise_met(root.ability.premise,root.context): continue
			root["premise_checked"] = true
		selected_roots.append(root)
	_run_roots(selected_roots)
	if card.definition.kind == "unit": _trigger_counters(player, "enemy_unit_deployed", uid)
	if state.winner != -1 or not _fault.is_empty(): return
	if card.definition.kind in ["unit","order","field"]:
		_emit_card_event(player,card,uid,prior_units)
		if card.definition.kind == "unit" and not _unit(uid).is_empty(): _emit_entry_event(_unit(uid))
		_drain_deaths()
	if not _fault.is_empty(): return
	if card.definition.kind == "order":
		var scheduled := {"owner":player,"card":card.duplicate(true),"played_turn":int(state.turn),"chosen":chosen,"groups":[]}
		for index in card.definition.abilities.size():
			if str(card.definition.abilities[index].trigger).begins_with("next_"): scheduled.groups.append(index)
		if not scheduled.groups.is_empty():
			if state.scheduled.size() >= 32: _fault="RULE_BUDGET_EXCEEDED"
			else: state.scheduled.append(scheduled)

func _trigger_counters(actor: int, trigger: String, trigger_uid: int = -1, attack_target: int = -1) -> void:
	var owner := 1 - actor
	var pending: Array = state.players[owner].get("counters", []).duplicate()
	for entry in pending:
		if state.winner != -1 or not _fault.is_empty() or _counter_canceled: return
		if trigger in ["enemy_hq_attacked","enemy_unit_deployed"] and _unit(trigger_uid).is_empty(): return
		if trigger=="enemy_unit_attacked" and (_unit(trigger_uid).is_empty() or _unit(attack_target).is_empty()): return
		if entry.card.definition.counter_trigger != trigger: continue
		if int(state.turn)!=int(entry.get("armed_turn",-2))+1 or int(state.active_player)!=actor: continue
		var cost:=play_cost(owner,entry.card)
		if int(state.players[owner].credits)<cost: continue
		var context := _context(owner, -1, entry.card)
		context["trigger_unit"] = trigger_uid
		context["attack_target"] = attack_target
		var roots := []
		for ability_entry in _abilities(context, "on_reveal"):
			if not ability_entry.ability.has("premise") or _premise_met(ability_entry.ability.premise,context):
				ability_entry["premise_checked"] = true
				roots.append(ability_entry)
		if roots.is_empty(): continue
		state.players[owner].credits-=cost
		_stat("play",owner,entry.card,1,{"card_kind":"counter"})
		_stat("deployment_spent",owner,entry.card,cost)
		state.players[owner].counters.erase(entry)
		entry.card.erase("hand_cost_layers")
		state.discard.append({"owner": owner, "card": entry.card})
		_log("反制触发：%s" % entry.card.definition.name)
		_stat("counter_reveal", owner, entry.card)
		_record_played_card(owner,entry.card)
		_run_roots(roots)
		if state.winner==-1 and _fault.is_empty():
			_emit_card_event(owner,entry.card,-1,_ordered_units().map(func(u):return int(u.uid)))
			_drain_deaths()

func _attack(uid: int, target_uid: int) -> void:
	var attacker := _unit(uid)
	_consume_keyword(attacker,"core.smokescreen")
	_drain_deaths()
	if not _fault.is_empty() or state.winner!=-1 or _unit(uid).is_empty(): return
	var owner: int = attacker.owner
	state.players[owner].credits -= _operation_cost(attacker)
	_stat("operation_spent", owner, attacker.card, _operation_cost(attacker))
	_stat("attack", owner, attacker.card, 1, {"source_uid":uid,"target_uid":target_uid})
	attacker.attacks_used = int(attacker.attacks_used) + 1
	_refresh_attacks(attacker)
	if target_uid == -1:
		_trigger_counters(owner, "enemy_hq_attacked", uid)
		if _counter_canceled or state.winner != -1 or not _fault.is_empty() or _unit(uid).is_empty(): return
		attacker = _unit(uid)
		_queue_unit_event(attacker,"on_attack",-1,{},0,false,{"attack_target":-1})
		_drain_deaths()
		if state.winner!=-1 or not _fault.is_empty() or _unit(uid).is_empty(): return
		attacker["has_attacked_in_play"] = true
		_consume_keyword(attacker,"core.shock")
		var damage := _incoming_damage(state.players[1-owner],_combat_damage(attacker, {}, "attack"),"combat",attacker)
		_damage_stat(owner, attacker.card, damage, int(state.players[1 - owner].hp), 1 - owner, -1)
		state.players[1 - owner].hp -= damage
		_log("%s 对敌方总部造成 %d 点伤害" % [_unit_definition(attacker).name, damage])
	else:
		_trigger_counters(owner,"enemy_unit_attacked",uid,target_uid)
		if _counter_canceled or state.winner!=-1 or not _fault.is_empty() or _unit(uid).is_empty() or _unit(target_uid).is_empty(): return
		var defender := _unit(target_uid)
		attacker["attack_context"]={"attack_target":target_uid,"attack_target_snapshot":defender.duplicate(true)}
		attacker.attack_context.attack_target_snapshot["snapshot_operation_cost"]=_operation_cost(defender)
		_queue_unit_event(attacker,"on_attack",target_uid,defender.card,0,false,attacker.attack_context)
		_drain_deaths()
		if state.winner!=-1 or not _fault.is_empty() or _unit(uid).is_empty(): return
		if _unit(target_uid).is_empty():
			attacker.erase("attack_context")
			return
		_resolve_combat(attacker,_unit(target_uid))
		attacker.attack_context["attack_target_snapshot"] = defender.duplicate(true)
		attacker.attack_context.attack_target_snapshot["snapshot_operation_cost"]=_operation_cost(defender)
	_checkpoint()
	_drain_deaths()
	_complete_action(attacker,"attack")
	if state.winner == -1 and _fault.is_empty():
		_emit_unit_event(owner,"unit_attacked",uid,attacker.card)
		_drain_deaths()
	if target_uid == -1 and state.winner == -1 and _fault.is_empty():
		_emit_unit_event(owner,"unit_attacked_hq",uid,attacker.card)
		_drain_deaths()

func _combat_hit(source: Dictionary, target: Dictionary, phase: String) -> void:
	var amount := _combat_damage(source,target,phase)
	var context := _context(source.owner,source.uid,source.card)
	context["damage_kind"] = "combat"
	_unit_damage(target,amount,context)

func _resolve_combat(attacker: Dictionary, defender: Dictionary) -> void:
	if attacker.is_empty() or defender.is_empty(): return
	_queue_unit_event(defender,"on_attacked",attacker.uid,attacker.card)
	_drain_deaths()
	if state.winner != -1 or not _fault.is_empty() or _unit(attacker.uid).is_empty() or _unit(defender.uid).is_empty(): return
	var attacker_class: String = _unit_definition(attacker).unit_class
	var defender_class: String = _unit_definition(defender).unit_class
	attacker["has_attacked_in_play"] = true
	var shock := _has_keyword(attacker,"core.shock")
	var ambush := _has_keyword(defender,"core.ambush") and int(defender.get("ambush_used_turn",-1)) != int(state.turn)
	var retaliation := not shock and defender_class != "bomber" and attacker_class != "artillery" and (attacker_class != "bomber" or defender_class == "fighter")
	_consume_keyword(attacker,"core.smokescreen")
	_consume_keyword(attacker,"core.shock")
	_drain_deaths()
	if not _fault.is_empty() or state.winner!=-1 or _unit(attacker.uid).is_empty() or _unit(defender.uid).is_empty(): return
	if ambush: defender["ambush_used_turn"] = int(state.turn)
	var attack_first := _strikes_first(attacker,"attack")
	var defend_first := retaliation and (ambush or _strikes_first(defender,"retaliation"))
	if defend_first and not attack_first:
		_combat_hit(defender,attacker,"retaliation")
		if attacker.hp > 0: _combat_hit(attacker,defender,"attack")
	elif attack_first and not defend_first:
		_combat_hit(attacker,defender,"attack")
		if retaliation and defender.hp > 0: _combat_hit(defender,attacker,"retaliation")
	else:
		# Normal combat remains simultaneous: a lethally damaged defender retaliates.
		_combat_hit(attacker,defender,"attack")
		if retaliation: _combat_hit(defender,attacker,"retaliation")
	if defender.hp>0 and not defender.get("destroyed",false):
		_queue_unit_event(defender,"after_attacked",attacker.uid,attacker.card,0,false,{"trigger_unit_snapshot":attacker.duplicate(true)})
	_log("%s 攻击 %s" % [_unit_definition(attacker).name,_unit_definition(defender).name])

func _draw(owner: int) -> void:
	var player: Dictionary = state.players[owner]
	if player.deck.is_empty():
		player.fatigue += 1
		_stat("fatigue", owner, {}, mini(int(player.fatigue), maxi(0, int(player.hp))))
		player.hp -= player.fatigue
		_log("玩家 %d 受到 %d 点疲劳伤害" % [owner + 1, player.fatigue])
		return
	var card: Dictionary = player.deck.pop_back()
	_receive_card(owner, card, "opening_draw" if state.state_seq == 0 and player.max_credits == 0 else "draw")

func _draw_effect(owner: int, effect: Dictionary, context: Dictionary) -> void:
	var deck: Array=state.players[owner].deck
	var index:=deck.size()-1
	if effect.has("filter"):
		while index>=0 and not _transfer_matches(deck[index],effect.filter,context,false): index-=1
		if index<0: return
	elif index<0:
		_draw(owner)
		return
	var card: Dictionary=deck[index]
	deck.remove_at(index)
	context.get_or_add("drawn_cards",[]).append({"cost":int(card.definition.cost),"owner":owner,"instance_id":"h"+str(state.next_hand_id) if _held_cards(owner).size()<10 else ""})
	_receive_card(owner,card,"draw")

func _held_cards(owner: int) -> Array:
	var player: Dictionary=state.players[owner]
	var held: Array=player.hand+player.get("counters",[])
	held.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return str(a.instance_id).naturalnocasecmp_to(str(b.instance_id))<0)
	return held

func _return_counters(owner: int) -> void:
	var player: Dictionary=state.players[owner]
	for entry in player.get("counters",[]):
		entry.erase("armed_turn")
		player.hand.append(entry)
	player.counters=[]
	player.hand=_held_cards(owner)

func _receive_card(owner: int, card: Dictionary, event: String, revealed: bool = false) -> void:
	var player: Dictionary = state.players[owner]
	if _held_cards(owner).size() >= 10:
		player.burned.append(card)
		_stat("burn", owner, card)
		_log("玩家 %d 手牌已满，烧毁一张牌" % (owner + 1))
	else:
		_stat(event, owner, card)
		var entry := {"instance_id": "h" + str(state.next_hand_id), "card": card}
		if revealed: entry["revealed"] = true
		player.hand.append(entry)
		state.next_hand_id += 1
		_log("玩家 %d 抽取一张牌" % (owner + 1))

func _from_deck(effect: Dictionary, context: Dictionary) -> void:
	var owner: int = context.owner
	var deck: Array = state.players[owner].deck
	var summoning: bool = effect.op == "summon_from_deck"
	for i in int(effect.amount):
		if summoning and (_count_row(owner, "support") >= 4 or not _unit_entry_allowed(owner)): return
		var found := -1
		# The top is the end of the array, exactly as in _draw. Never consult
		# the mutable catalog: this is the actual frozen card in this match.
		for index in range(deck.size() - 1, -1, -1):
			_spend("visits")
			if not _fault.is_empty(): return
			if deck[index].definition.name == effect.card_name and (not summoning or deck[index].definition.kind == "unit"):
				found = index
				break
		if found < 0: return
		var card: Dictionary = deck[found]
		deck.remove_at(found)
		if not summoning:
			_receive_card(owner, card, "search")
			continue
		var unit := _new_unit(owner, card, "", true)
		_initialize_summoned_unit(unit)
		if not _fault.is_empty(): return

func _matches_unit_filter(unit: Dictionary, filter: Dictionary) -> bool:
	if unit.is_empty(): return false
	var name: String = unit.card.definition.name
	if filter.has("card_name") and name != filter.card_name: return false
	if filter.has("name_contains") and not name.contains(filter.name_contains): return false
	if filter.has("unit_classes") and not filter.unit_classes.any(func(c): return _unit_classes(unit).has(c)): return false
	if filter.has("faction_id") and unit.card.definition.get("faction_id") != filter.faction_id: return false
	if not _matches_sin(unit.card.definition,filter): return false
	if filter.has("cost") and not _compare(int(unit.card.definition.cost),filter.cost.cmp,int(filter.cost.value)): return false
	if filter.has("generated_by") and unit.card.get("generated_token_id","")!=filter.generated_by: return false
	if filter.has("is_liberated") and bool(unit.get("liberated",false))!=filter.is_liberated: return false
	if filter.has("without_keyword") and _has_keyword(unit,filter.without_keyword): return false
	if filter.has("is_veteran") and bool(unit.get("is_veteran",false)) != filter.is_veteran: return false
	if filter.has("keyword_id") and not _has_keyword(unit,filter.keyword_id): return false
	if filter.get("row","any") != "any" and filter.row != unit.row: return false
	if filter.has("attack_parity") and int(unit.attack)%2 != (0 if filter.attack_parity=="even" else 1): return false
	for key in ["attack","health"]:
		if filter.has(key) and not _compare(int(unit.get("hp" if key=="health" else key,0)),filter[key].cmp,int(filter[key].value)): return false
	return true

func _targets(target: String, context: Dictionary, filter: Dictionary = {}) -> Array:
	var targets := _target_candidates(target,context)
	if not filter.is_empty(): targets = targets.filter(func(uid): return _matches_unit_filter(_unit(uid),filter))
	if target.begins_with("random_") and not targets.is_empty():
		var selected: int = targets[_random_index(targets.size())]
		targets = [selected]
		_log("随机目标：单位 #%d" % selected)
	_spend("visits", targets.size())
	return targets

func _target_candidates(target: String, context: Dictionary) -> Array:
	var targets := []
	match target:
		"self_and_trigger":
			for uid in [int(context.uid),int(context.get("trigger_unit",-1))]:
				if not _unit(uid).is_empty() and not uid in targets: targets.append(uid)
			return targets
		"creator":
			var creator := _premise_unit("creator",context)
			return [] if creator.is_empty() else [int(creator.uid)]
		"trigger_and_adjacent":
			var uid := int(context.get("trigger_unit",-1))
			return [] if _unit(uid).is_empty() else [uid]+_adjacent_targets("adjacent_to_trigger",context)
		"adjacent_to_trigger": return _adjacent_targets(target,context)
		"chosen_and_adjacent":
			if _unit(int(context.chosen)).is_empty(): return []
			return [int(context.chosen)] + _adjacent_targets("adjacent_to_chosen",context)
		"adjacent_to_self", "adjacent_to_chosen": return _adjacent_targets(target,context)
		"selected_units": return context.get("selected_units",[]).filter(func(uid):return not _unit(uid).is_empty())
		"own_hq": targets.append(-int(context.owner) - 1)
		"enemy_hq": targets.append(-int(1 - context.owner) - 1)
		"self":
			if not _unit(context.uid).is_empty(): targets.append(context.uid)
		"attack_target":
			if not _unit(int(context.get("attack_target",-1))).is_empty(): targets.append(int(context.attack_target))
		"trigger_unit":
			var trigger_uid := int(context.get("trigger_unit", -1))
			if not _unit(trigger_uid).is_empty(): targets.append(trigger_uid)
		"chosen":
			if int(context.chosen) in [-101,-102]: targets.append(int(context.chosen)+100)
			elif not _unit(context.chosen).is_empty(): targets.append(context.chosen)
		_:
			var friendly := target in ["all_other_friendly_units","all_friendly_units", "random_friendly_unit", "random_friendly_target"]
			for unit in state.units:
				if target=="all_other_friendly_units" and unit.uid==context.uid: continue
				if target == "all_units" or (unit.owner == context.owner) == friendly:
					targets.append(unit.uid)
			targets.sort()
			if target in ["random_enemy_target","random_friendly_target"]: targets.append(-1-(int(context.owner) if friendly else 1-int(context.owner)))

	return targets

func _effect_value(value: Variant, context: Dictionary) -> int:
	if not value is Dictionary: return int(value)
	if value.has("stack_count") or value.has("unit_stat"): return _unit_value(value,context)
	if value.has("count_units"): return _premise_value(value,context)
	if value.has("equipment_faction"): return _unit(context.uid).get("equipment_sources",[]).filter(func(e):return e.faction_id==value.equipment_faction).size()*int(value.scale)
	if value.has("equipment"): return int(_unit(context.uid).get("equipment",{}).get(value.equipment,0))*int(value.scale)
	var stat: String = value.get("stat", "")
	if stat == "selected_destroyed_count": return int(context.get("selected_destroyed_count",0))
	if stat == "event_damage": return int(context.get("event_damage",0))
	if stat in ["friendly_turn_number","enemy_turn_number"]: return int(state.players[int(context.owner) if stat=="friendly_turn_number" else 1-int(context.owner)].get("turns_started",0))
	if stat == "source_destroyed_count": return int(_action_kills.get(_source_key(context),0))
	if stat == "source_base_health": return int(context.card.definition.health)
	if not stat in ["enemy_unit_count", "friendly_unit_count", "other_friendly_unit_count"]:
		_fault = "UNSUPPORTED_EFFECT"
		return 0
	var owner: int = 1 - int(context.owner) if stat == "enemy_unit_count" else int(context.owner)
	var total := 0
	for unit in state.units:
		if unit.owner == owner and unit.hp > 0 and not unit.get("destroyed", false):
			if stat != "other_friendly_unit_count" or int(unit.uid) != int(context.uid): total += 1
	return total

func _effect(effect: Dictionary, context: Dictionary) -> void:
	var owner: int = context.owner
	_stat("effect", owner, context.card, 1, {"op": effect.op, "effect": effect.duplicate(true), "source_uid": context.uid})
	# Snapshot numeric expressions, except the explicit per-hit attack-gap rule.
	effect = effect.duplicate(true)
	for key in ["amount", "attack_delta", "health_delta"]:
		if effect.op == "modify_incoming_damage" and key == "amount" and effect.get(key) is Dictionary and effect[key].has("attack_gap"): continue
		if effect.get(key) is Dictionary and effect[key].get("unit_stat",effect[key].get("stack_count",{})).get("target")!="effect_target": effect[key] = _effect_value(effect[key], context)
	if not _fault.is_empty(): return
	if effect.op == "damage":
		context["last_damage_killed"]=false
		context["last_damage_kill_count"]=0
	if effect.op == "noop": return
	if effect.op == "temporarily_remove":
		for uid in _targets(effect.target,context,effect.get("unit_filter",{})): _suspend_unit(_unit(uid),effect,context)
		return
	if effect.op == "trigger_death":
		for uid in _targets(effect.target,context,effect.get("unit_filter",{})):
			var unit := _unit(uid)
			if not unit.is_empty(): _deaths.append_array(_abilities(_context(unit.owner,unit.uid,unit.card),"on_death"))
		return
	if effect.op == "trigger_evolution":
		for uid in _targets(effect.target,context,effect.get("unit_filter",{})): _advance_evolution(uid)
		return
	if effect.op == "select_units":
		_select_units(effect,context)
		return
	if effect.op == "summon_origin":
		var original: Dictionary=context.card.get("origin_card",context.card)
		for i in int(effect.amount):
			if original.definition.kind=="unit" and _count_row(owner,"support")<4 and _unit_entry_allowed(owner): _initialize_summoned_unit(_new_unit(owner,original,"",true))
		return
	if effect.op == "lose_kredits":
		var seat: int=owner if effect.player=="owner" else 1-owner
		state.players[seat].credits=maxi(0,int(state.players[seat].credits)-int(effect.amount))
		return
	if effect.op == "prepare_counter":
		_prune_intercepts()
		if state.order_intercepts.size()>=32: _fault="RULE_BUDGET_EXCEEDED";return
		state.order_intercepts.append({"owner":owner,"source_uid":int(context.uid),"duration":effect.duration,"played_turn":int(state.turn),"card":context.card.duplicate(true)})
		return
	if effect.op == "become_veteran":
		for uid in _targets(effect.target,context,effect.get("unit_filter",{})): _become_veteran(_unit(uid))
		return
	if effect.op == "take_control":
		for uid in _targets(effect.target,context,effect.get("unit_filter",{})):
			var unit := _unit(uid)
			if unit.is_empty() or unit.owner == owner or _count_row(owner,"support") >= 4: continue
			var previous_owner: int=unit.owner
			_change_controller(unit,owner)
			if effect.duration != "battle":
				unit.get_or_add("control_layers",[]).append({"owner":previous_owner,"expires_turn":int(state.turn)+(2 if effect.duration=="next_own_turn_start" else 0),"at_start":effect.duration=="next_own_turn_start"})
			else: unit.erase("control_layers")
		return
	if effect.op == "grant_ability":
		for uid in _targets(effect.target,context):
			var unit := _unit(uid)
			if unit.is_empty(): continue
			if unit.ability_layers.size() >= 16: _fault="RULE_BUDGET_EXCEEDED";return
			var layer: Dictionary=effect.ability.duplicate(true)
			layer["expires_turn"]=int(state.turn) if effect.duration=="end_of_turn" else -1
			unit.ability_layers.append(layer)
			if effect.duration=="match": _save_match_abilities(unit.card,[effect.ability],context)
		return
	if effect.op in ["transform","become_trigger_unit"]:
		_transform_units(effect,context)
		return
	if effect.op == "schedule":
		_prune_schedules()
		if state.scheduled.size() >= 32:
			_fault="RULE_BUDGET_EXCEEDED"
			return
		var has_chosen: bool=Runtime.effect_leaves(effect.effects).any(Runtime._effect_chooses)
		var lifetime: String=effect.get("lifetime","source" if context.uid>=0 else "target" if has_chosen else "match")
		var saved := {"owner":owner,"card":context.card.duplicate(true),"chosen":int(context.chosen),"source_uid":int(context.uid),"context":context.duplicate(true),"lifetime":lifetime,"played_turn":int(state.turn),"groups":[-1],"ability":{"trigger":effect.trigger,"after_turns":effect.get("after_turns",1),"effects":effect.effects.duplicate(true)},"repeat":effect.get("repeat","once"),"times":effect.get("times",-1)}
		if effect.has("once_per_card"): saved["once_per_card"]=effect.once_per_card
		if _schedule_alive(saved): state.scheduled.append(saved)
		return
	if effect.op == "if_killed":
		if not context.get("last_damage_killed",false): return
		# Capture before child damage can overwrite the preceding packet's result.
		var count: int=int(context.get("last_damage_kill_count",0)) if effect.get("per_unit",false) else 1
		for n in count:
			for child in effect.effects:
				_spend("ops")
				if state.winner!=-1 or not _fault.is_empty(): return
				_effect(child,context)
				_checkpoint()
		return
	if effect.op == "if_drawn":
		var drawn: Array=context.get("drawn_cards",[])
		var parity: int=0 if effect.parity=="even" else 1
		var hits: int=drawn.filter(func(c):return int(c.owner)==owner and int(c.cost)%2==parity).size()
		var count: int=drawn.filter(func(c):return int(c.owner)==owner).size()
		if count==0 or (hits==0 if effect.match=="any" else hits!=count): return
		for child in effect.effects:
			_spend("ops")
			if state.winner!=-1 or not _fault.is_empty(): return
			_effect(child,context)
			_checkpoint()
		return
	if effect.op == "modify_stats" and effect.attack_delta == 0 and effect.health_delta == 0: return
	if effect.op in ["damage", "heal"] and effect.amount is int and effect.amount == 0: return
	if effect.op == "choose_effect":
		var options: Array = []
		var available: Array=[]
		for option in effect.options:
			if option.has("premise") and not _premise_met(option.premise,context): continue
			available.append(option)
			options.append({"label":option.label,"rules_text":Runtime.choice_text(option,context.card.definition)})
		if available.is_empty(): return
		var selected := _choose_card(owner,options,context,"effect")
		if not _fault.is_empty(): return
		var branch: Dictionary=available[selected]
		var branch_context: Dictionary=context.duplicate(true)
		if branch.has("target"):
			branch_context.chosen=_choose_ability_target({"context":branch_context,"ability":{"trigger":"on_play","target":branch.target}})
			branch_context["chosen_snapshot"]=_unit(int(branch_context.chosen)).duplicate(true)
			if not _fault.is_empty(): return
			if context.card.definition.kind=="order" and branch_context.chosen!=-1: _order_target_reward(owner,branch_context.chosen,context.card)
		for child in branch.effects:
			_spend("ops")
			if not _fault.is_empty(): return
			_effect(child,branch_context)
			_checkpoint()
			if state.winner != -1 or not _fault.is_empty(): return
		return
	if effect.op in ["research","develop"]:
		_card_research(effect,context)
		return
	if effect.op == "modify_hand_cost":
		_modify_hand_cost(effect,context)
		return
	if effect.op == "modify_cards":
		_modify_cards(effect,context)
		return
	if effect.op == "cancel_action":
		_counter_canceled = true
		_log("本次行动被反制")
		return
	if effect.op == "draw":
		for i in int(effect.amount):
			_draw_effect(owner if effect.player == "owner" else 1 - owner,effect,context)
			_checkpoint()
			if state.winner != -1 or not _fault.is_empty(): return
		return
	if effect.op == "gain_kredits":
		var credits_before: int = state.players[owner].credits
		var limit:=maxi(credits_before,int(state.players[owner].max_credits)) if not effect.get("allow_overflow",false) else 1000
		state.players[owner].credits = mini(limit,credits_before+int(effect.amount))
		_stat("kredits_gained", owner, context.card, int(state.players[owner].credits) - credits_before)
		_log("玩家 %d 恢复 %d 点资源" % [owner + 1, effect.amount])
		return
	if effect.op == "intel":
		var held := _held_cards(1-owner)
		var candidates: Array = held.filter(func(entry: Dictionary) -> bool: return not entry.get("revealed",false))
		for i in mini(int(effect.amount),candidates.size()):
			# Selection contains only public hand positions.
			# Never pass an unrevealed definition, instance ID or armed-counter flag.
			var options: Array = candidates.map(func(entry): return {"hidden":true,"hand_position":held.find(entry)})
			var index := _choose_card(owner,options,context,"intel") if effect.get("selection","random") == "chosen" else _random_index(candidates.size())
			if not _fault.is_empty(): return
			candidates[index]["revealed"] = true
			candidates.remove_at(index)
		_log("玩家 %d 获取情报" % (owner+1))
		return
	if effect.op in ["discard","gain_hq_defense","modify_kredit_slots"]:
		var affected: int = owner if effect.player == "owner" else 1-owner
		var player: Dictionary = state.players[affected]
		if effect.op == "discard":
			context.erase("discarded_name")
			var held: Array = _held_cards(affected).filter(func(entry): return _card_filter(entry.card,effect.get("filter",{})))
			for i in mini(int(effect.amount),held.size()):
				var index := _choose_card(affected,held.map(func(entry):return entry.card),context,"discard") if effect.get("selection","random") == "chosen" else _random_index(held.size())
				if not _fault.is_empty(): return
				var entry: Dictionary = held[index]
				held.remove_at(index)
				player.hand.erase(entry)
				player.counters.erase(entry)
				entry.card.erase("hand_cost_layers")
				state.discard.append({"owner":affected,"card":entry.card})
				context["discarded_name"] = entry.card.definition.name
				_stat("discard",affected,entry.card)
		elif effect.op == "gain_hq_defense":
			player.max_hp += int(effect.amount)
			player.hp += int(effect.amount)
		else:
			player.max_credits = clampi(int(player.max_credits)+int(effect.amount),0,12)
			player.credits = mini(int(player.credits),int(player.max_credits))
		return
	if effect.op == "summon":
		for i in int(effect.amount):
			if _count_row(owner, "support") < 4 and _unit_entry_allowed(owner):
				var card := _generated_card(context.card, effect.token_id, int(context.uid))
				if not _fault.is_empty(): return
				var unit := _new_unit(owner, card, effect.token_id)
				_initialize_summoned_unit(unit)
				if not _fault.is_empty(): return
		return
	if effect.op == "create_card":
		for i in int(effect.amount):
			var card := _generated_card(context.card, effect.token_id, int(context.uid))
			if not _fault.is_empty(): return
			_receive_card(owner if effect.player == "owner" else 1 - owner, card, "create")
		return
	if effect.op == "remove_hand":
		var affected: int = owner if effect.player == "owner" else 1-owner
		var player: Dictionary = state.players[affected]
		for entry in player.hand.duplicate():
			_spend("visits")
			if entry.card.definition.name == effect.card_name:
				player.hand.erase(entry)
				_stat("remove_hand",affected,entry.card)
		return
	if effect.op == "reshuffle_zones":
		_reshuffle_zones(effect,context)
		return
	if effect.op == "liberate":
		_liberate(_unit(int(context.uid)),effect.token_id)
		return
	if effect.op == "transfer_card":
		_transfer_card(effect,context)
		return
	if effect.op in ["search_deck", "summon_from_deck"]:
		_from_deck(effect, context)
		return
	var targets := _targets(effect.target, context, effect.get("unit_filter",{}))
	var packet_spec: Dictionary=effect.duplicate(true)
	for uid in targets:
		effect=packet_spec.duplicate(true)
		var per_target: Dictionary=context.duplicate(true)
		per_target["effect_target"]=uid
		for key in ["amount","attack_delta","health_delta"]:
			if effect.get(key) is Dictionary and not effect[key].has("attack_gap"): effect[key]=_effect_value(effect[key],per_target)
		if effect.op in ["set_combat_priority","grant_unit_class","modify_incoming_damage","grant_order_target_reward"]:
			_add_extra_rule(uid,effect,context)
			continue
		if not _fault.is_empty(): return
		if uid < 0:
			var player: Dictionary = state.players[-uid - 1]
			if effect.op == "damage":
				var raw: int=mini(int(effect.amount),int(effect.get("max_amount",1000)))
				var amount := _incoming_damage(player,raw,"effect",_unit(int(context.get("uid",-1))),dict_merge(context.card,{"damage_owner":context.owner}))
				_damage_stat(owner, context.card, amount, int(player.hp), -uid - 1, uid)
				player.hp -= amount
			if effect.op == "heal":
				_stat("heal", owner, context.card, mini(int(effect.amount), maxi(0, int(player.max_hp) - int(player.hp))), {"target_owner": -uid - 1,"target_uid":uid})
				player.hp = mini(int(player.max_hp), int(player.hp) + int(effect.amount))
		else:
			var unit := _unit(uid)
			if unit.is_empty(): continue
			if effect.op in ["modify_stacks","set_stacks"] and effect.stack != "heavy_armor":
				_custom_stack(unit,effect,context)
				continue
			var armor_before := stack_count(unit,"heavy_armor") if effect.op in ["modify_stacks","set_stacks"] else 0
			match effect.op:
				"damage":
					var was_alive: bool = unit.hp > 0 and not unit.get("destroyed",false)
					var slot := {"owner":int(unit.owner),"row":str(unit.row),"index":line_order(unit.owner,unit.row).find(uid)}
					var packet: int=int(effect.amount)
					for bonus in context.card.definition.get("damage_bonuses",[]) + effect.get("bonuses",[]):
						if _matches_unit_filter(unit,bonus.filter): packet += int(bonus.amount)
					packet=mini(packet,int(effect.get("max_amount",1000)))
					for cap in effect.get("caps",[]):
						if _matches_unit_filter(unit,cap.filter): packet=mini(packet,int(cap.amount))
					_unit_damage(unit,packet,context)
					if was_alive and unit.hp <= 0:
						context["last_damage_killed"]=true
						context["last_damage_kill_count"]=int(context.get("last_damage_kill_count",0))+1
					if effect.has("on_kill_summon") and was_alive and unit.hp <= 0:
						# Only this damage packet's lethal result counts. Capture the victim's
						# ownership/position before cleanup; indirect deaths do not qualify.
						_checkpoint()
						if state.winner == -1 and _fault.is_empty(): _summon_at_victim(effect.on_kill_summon,slot,context)
				"heal":
					_stat("heal", owner, context.card, mini(int(effect.amount), maxi(0,int(unit.max_hp)-int(unit.hp))), {"target_owner": unit.owner,"target_uid":uid})
					unit.damage_taken = maxi(int(unit.get("damage_baseline",0))-int(unit.get("capacity_only",0)), int(unit.damage_taken) - int(effect.amount))
				"destroy":
					if effect.target=="selected_units" and unit.hp>0 and not unit.get("destroyed",false): context["selected_destroyed_count"]=int(context.get("selected_destroyed_count",0))+1
					_stat("destroy", owner, context.card, 1, {"target_owner": unit.owner,"target_uid":uid})
					unit["destroyed"] = true
					_destroyer(unit,context)
				"equip", "unequip":
					if not unit.has("equipment"): unit["equipment"]={}
					if not unit.equipment.has(effect.tag) and unit.equipment.size() >= 16:
						_fault="RULE_BUDGET_EXCEEDED"
						return
					var before: int=int(unit.equipment.get(effect.tag,0))
					unit.equipment[effect.tag]=clampi(before+int(effect.amount)*(1 if effect.op=="equip" else -1),0,10)
					if not unit.has("equipment_sources"): unit["equipment_sources"]=[]
					if effect.op=="equip":
						for n in int(unit.equipment[effect.tag])-before: unit.equipment_sources.append({"tag":effect.tag,"faction_id":str(context.card.definition.get("faction_id",""))})
					else:
						for n in before-int(unit.equipment[effect.tag]):
							for i in unit.equipment_sources.size():
								if unit.equipment_sources[i].tag==effect.tag:
									unit.equipment_sources.remove_at(i)
									break
				"suppress": _suppress(unit)
				"repair": unit.damage_taken = int(unit.get("damage_baseline",0))-int(unit.get("capacity_only",0))
				"pin": unit["pinned_until"] = maxi(int(unit.get("pinned_until",-1)),int(state.turn)+(2 if unit.owner == state.active_player else 1)+2*(int(effect.turns)-1))
				"reset_operations":
					unit.moved = false
					unit.attack_locked = false
					unit.attacks_used = 0
				"retreat":
					if unit.row == "front" and _count_row(unit.owner,"support") < 4:
						_remove_from_line(unit)
						unit.row = "support"
						_position_unit(unit)
					else:
						_self_departure_event(unit,"own_unit_retreated")
						if not _fault.is_empty(): return
						_leave_battlefield(unit,true)
					_emit_unit_event(unit.owner,"unit_retreated",unit.uid,unit.card)
				"return_to_hand": _leave_battlefield(unit,true,effect,context)
				"remove": _leave_battlefield(unit,false)
				"fight":
					if unit.owner != context.owner: _resolve_combat(_unit(context.uid),unit)
				"modify_stats", "set_attack", "swap_stats", "grant_keyword", "set_attack_limit", "modify_operation_cost", "set_combat_damage_multiplier", "modify_stacks", "set_stacks":
					if unit.modifiers.size() + unit.grants.size() + unit.attack_limits.size() + unit.operation_costs.size() + unit.combat_damage_rules.size() + unit.get("extra_rules",[]).size() + unit.get("stack_layers", []).size() >= 64:
						_fault = "RULE_BUDGET_EXCEEDED"
						return
					var layer := {"modifier_id": int(state.next_modifier_id), "source_card_id":_enhancement_source(context),"source_uid": context.uid, "expires_turn": int(state.turn) if effect.duration == "end_of_turn" else -1}
					layer.merge(_effect_expiry(effect.duration,int(context.owner)),true)
					state.next_modifier_id += 1
					if effect.op == "swap_stats":
						# Read both displayed values before changing either. Account for
						# live auras once; later aura changes and damage work normally.
						var aura_attack := 0
						var aura_health := 0
						var aura_capacity := 0
						for aura in _field_effects(unit):
							if aura.op == "modify_stats":
								aura_attack += int(aura.attack_delta)
								aura_health += int(aura.health_delta)
								if aura.get("health_mode")=="max_only": aura_capacity += int(aura.health_delta)
						layer.merge({"attack_set":int(unit.hp)-aura_attack,"health_set":int(unit.attack)-aura_health,"damage_baseline":int(unit.damage_taken)+aura_capacity,"attack_delta":0,"health_delta":0})
						unit.modifiers.append(layer)
					elif effect.op == "set_attack":
						var target_context: Dictionary=context.duplicate(true)
						target_context["effect_target"]=unit.uid
						layer["attack_set"]=_effect_value(effect.value,target_context)
						layer["attack_delta"]=0
						layer["health_delta"]=0
						unit.modifiers.append(layer)
					elif effect.op == "modify_stats":
						layer["attack_delta"] = effect.attack_delta
						layer["health_delta"] = effect.health_delta
						if effect.has("health_mode"): layer["health_mode"]=effect.health_mode
						unit.modifiers.append(layer)
					elif effect.op == "grant_keyword":
						layer["keyword_id"] = effect.keyword_id
						unit.grants.append(layer)
					elif effect.op == "set_attack_limit":
						layer["attacks"] = int(effect.attacks)
						unit.attack_limits.append(layer)
					elif effect.op == "modify_operation_cost":
						var key := "cost_set" if effect.has("cost_set") else "cost_delta"
						layer[key] = int(effect[key])
						unit.operation_costs.append(layer)
					elif effect.op in ["modify_stacks", "set_stacks"]:
						layer["stack"] = effect.stack
						layer["amount"] = int(effect.amount)
						layer["mode"] = "set" if effect.op == "set_stacks" else "add"
						if not unit.has("stack_layers"): unit["stack_layers"] = []
						unit.stack_layers.append(layer)
					else:
						for key in ["against", "applies_to", "multiplier"]: layer[key] = effect[key]
						for key in ["attack_base","divisor", "rounding", "ignore_armor", "target_row", "attack_delta", "target_filter", "target_attack_compare"]:
							if effect.has(key): layer[key] = effect[key]
						unit.combat_damage_rules.append(layer)
					if effect.duration == "match":
						var bucket: String = {"modify_stats":"modifiers","set_attack":"modifiers","grant_keyword":"grants","set_attack_limit":"attack_limits","modify_operation_cost":"operation_costs","set_combat_damage_multiplier":"combat_damage_rules","modify_stacks":"stack_layers","set_stacks":"stack_layers"}[effect.op]
						if not unit.card.has("match_layers"): unit.card["match_layers"] = []
						unit.card.match_layers.append({"bucket":bucket,"layer":layer.duplicate(true)})
			_recompute(unit)
			if effect.op in ["modify_stacks","set_stacks"] and stack_count(unit,"heavy_armor") > armor_before: _queue_stack_event(unit,"heavy_armor")
		_log("%s → %s" % [effect.op, "总部 %d" % -uid if uid < 0 else "单位 #%d" % uid])

func _headquarters_sources() -> Array:
	var sources := []
	for owner in [int(state.active_player),1-int(state.active_player)]:
		var hq: Dictionary = state.players[owner].get("headquarters",{})
		if not hq.is_empty(): sources.append({"owner":owner,"uid":-1,"card":hq})
	return sources

func _headquarters_event(actor: int, event: String, uid: int, card: Dictionary) -> void:
	for source in _headquarters_sources():
		var context := _context(source.owner,-1,source.card)
		context["trigger_unit"] = uid
		context["event_card"] = card.duplicate(true)
		for entry in _abilities(context,("own_" if source.owner==actor else "enemy_")+event):
			var counts: Dictionary=state.players[source.owner].hq_event_counts
			var key:=_event_key(entry)
			if entry.ability.has("limit") and int(counts.get(key,0))>=int(entry.ability.limit): continue
			if entry.ability.has("premise") and not _premise_met(entry.ability.premise,context): continue
			if entry.ability.has("occurrence"):
				var seen: Dictionary=state.players[source.owner].get_or_add("hq_event_seen",{})
				seen[key]=int(seen.get(key,0))+1
				if int(seen[key])!=int(entry.ability.occurrence): continue
			counts[key]=int(counts.get(key,0))+1
			entry["premise_checked"] = true
			_events.append(entry)
			_spend("events")

func turn_draw_count(owner: int) -> int:
	var hq: Dictionary = state.players[owner].get("headquarters",{})
	if hq.is_empty(): return 1
	var count := int(hq.definition.draw_rule.base)
	var context := _context(owner,-1,hq)
	for adjustment in hq.definition.draw_rule.get("adjustments",[]):
		if _premise_met(adjustment.premise,context): count += int(adjustment.delta)
	return clampi(count,0,10)

func _turn_roots(trigger: String) -> Array:
	var roots := []
	for source in _headquarters_sources():
		roots.append_array(_abilities(_context(source.owner,-1,source.card),trigger if source.owner==state.active_player else trigger.replace("own_","opponent_")))
	var field: Dictionary = state.get("field",{})
	if not field.is_empty():
		var field_trigger := trigger if int(field.owner)==int(state.active_player) else trigger.replace("own_","opponent_")
		roots.append_array(_abilities(_context(field.owner,-1,field.card),field_trigger))
	for unit in _ordered_units():
		if unit.token_id.is_empty() or unit.card.has("generated_origin"):
			roots.append_array(_abilities(_context(unit.owner, unit.uid, unit.card), trigger if unit.owner == state.active_player else trigger.replace("own_","opponent_")))
	if trigger == "own_turn_start": roots.append_array(_scheduled_roots("turn_start",int(state.active_player)))
	return roots

func _effect_expiry(duration: String, owner: int) -> Dictionary:
	if duration=="next_own_turn_start": return {"expires_turn":int(state.turn)+(2 if owner==state.active_player else 1),"expires_at_start":true}
	if duration=="next_opponent_turn_end": return {"expires_turn":int(state.turn)+(1 if owner==state.active_player else 2)}
	return {"expires_turn":int(state.turn) if duration=="end_of_turn" else -1}

func _expire_start_layers() -> void:
	for unit in state.units:
		for key in ["modifiers","grants","attack_limits","operation_costs","combat_damage_rules","extra_rules","stack_layers"]:
			unit[key]=unit.get(key,[]).filter(func(layer):return not (layer.get("expires_at_start",false) and int(layer.expires_turn)<=int(state.turn)))
	for player in state.players:
		player["extra_rules"]=player.get("extra_rules",[]).filter(func(layer):return not (layer.get("expires_at_start",false) and int(layer.expires_turn)<=int(state.turn)))

func _start_turn() -> void:
	_release_suspended("turn_start")
	_expire_start_layers()
	_checkpoint()
	_drain_deaths()
	if state.winner!=-1 or not _fault.is_empty(): return
	_expire_control(true)
	_return_counters(int(state.active_player))
	var player: Dictionary = state.players[state.active_player]
	player["deployments_previous_turn"]=player.get("deployments_this_turn",[])
	player["deployments_this_turn"]=[]
	player["turns_started"]=int(player.get("turns_started",0))+1
	player.max_credits = mini(12, int(player.max_credits) + 1)
	player.credits = player.max_credits
	for unit in state.units:
		if unit.owner == state.active_player:
			unit.moved = false
			unit.attacks_used = 0
			unit.attack_locked = false
			if _has_keyword(unit,"core.mobilize"):
				unit["mobilize_bonus"] = int(unit.get("mobilize_bonus",0))+1
				_recompute(unit)
			_refresh_attacks(unit)
	_stat("turn_start", int(state.active_player), {}, int(player.credits))
	_log("第 %d 回合 · 玩家 %d · 资源 %d" % [state.turn, int(state.active_player) + 1, player.credits])
	var draw_count := turn_draw_count(int(state.active_player))
	for i in draw_count:
		_draw(state.active_player)
		_checkpoint()
		if state.winner!=-1 or not _fault.is_empty(): return
	_checkpoint()
	_drain_deaths()
	if state.winner == -1:
		_run_roots(_turn_roots("own_turn_start"))

func _end_turn() -> void:
	_stat("unused_kredits", int(state.active_player), {}, int(state.players[state.active_player].credits))
	_run_roots(_turn_roots("own_turn_end"))
	_release_suspended("end_of_turn")
	_release_suspended("turn_end")
	_checkpoint()
	_drain_deaths()
	while state.winner == -1 and _fault.is_empty():
		var expiring := false
		for unit in state.units:
			for layer in unit.modifiers + unit.grants + unit.attack_limits + unit.operation_costs + unit.combat_damage_rules + unit.get("extra_rules",[]) + unit.get("stack_layers", []):
				if layer.expires_turn == state.turn:
					expiring = true
		if not expiring:
			break
		_spend("cleanup")
		if not _fault.is_empty(): return
		for unit in state.units:
			unit.modifiers = unit.modifiers.filter(func(layer: Dictionary) -> bool: return layer.expires_turn != state.turn)
			var lost: Array=[]
			for layer in unit.grants:
				if layer.expires_turn==state.turn and _has_keyword(unit,layer.keyword_id) and not layer.keyword_id in lost: lost.append(layer.keyword_id)
			unit.grants = unit.grants.filter(func(layer: Dictionary) -> bool: return layer.expires_turn != state.turn)
			for keyword_id in lost:
				if not _has_keyword(unit,keyword_id): _queue_unit_event(unit,"on_keyword_lost",unit.uid,unit.card,0,false,{"lost_keyword":keyword_id})
			unit.attack_limits = unit.attack_limits.filter(func(layer: Dictionary) -> bool: return layer.expires_turn != state.turn)
			unit.operation_costs = unit.operation_costs.filter(func(layer: Dictionary) -> bool: return layer.expires_turn != state.turn)
			unit["extra_rules"] = unit.get("extra_rules",[]).filter(func(layer: Dictionary) -> bool: return layer.expires_turn != state.turn)
			unit.combat_damage_rules = unit.combat_damage_rules.filter(func(layer: Dictionary) -> bool: return layer.expires_turn != state.turn)
			unit["stack_layers"] = unit.get("stack_layers", []).filter(func(layer: Dictionary) -> bool: return layer.expires_turn != state.turn)
			_recompute(unit)
		_checkpoint()
		_drain_deaths()
	if state.winner != -1 or not _fault.is_empty(): return
	for player in state.players:
		player["extra_rules"] = player.get("extra_rules",[]).filter(func(layer: Dictionary) -> bool: return layer.expires_turn != state.turn)
	_expire_control(false)
	for unit in state.units:
		# Keep expired slots to preserve ability-index bindings and event counters.
		unit.erase("attack_context")
	state.active_player = 1 - int(state.active_player)
	state.turn += 1
	_start_turn()

func ai_action(player: int) -> Dictionary:
	if state.has("mulligan") and state.winner==-1:
		if state.mulligan.confirmed[player]: return {}
		return {"type":"mulligan","hand_ids":state.players[player].hand.filter(func(h):return int(h.card.definition.cost)>3).map(func(h):return str(h.instance_id))}
	if not state.is_empty() and state.winner == -1 and state.has("pending_choice"):
		var choice: Dictionary = state.pending_choice
		if choice.owner == player:
			if choice.get("kind","unit") != "unit": return {"type":"choose_card","choice_id":choice.choice_id,"option_index":0}
			return {"type": "choose_target", "choice_id": choice.choice_id, "target_uid": choice.targets[0]}
		return {}
	if state.is_empty() or state.winner != -1 or player != state.active_player:
		return {}
	# Legal actions only; ties use stable identity order, never hidden opponent cards.
	for entry in state.players[player].hand:
		var action := {"type": "play", "hand_id": entry.instance_id}
		var targets := legal_targets(player, action)
		if not targets.is_empty():
			action.target_uid = targets[0]
			return action
	for unit in state.units:
		if unit.owner != player: continue
		var action := {"type": "attack", "uid": unit.uid}
		var targets := legal_targets(player, action)
		if not targets.is_empty():
			action.target_uid = -1 if -1 in targets else targets[0]
			return action
		for entry in _abilities(_context(player,unit.uid,unit.card),"on_activate"):
			if activation_error(player,unit.uid,entry.ability_index).is_empty(): return {"type":"activate","uid":unit.uid,"ability_index":entry.ability_index}
		if can_move(unit.uid):
			return {"type": "move", "uid": unit.uid}
	return {"type": "end_turn"}

func view_for(player: int) -> Dictionary:
	if state.is_empty() or not player in [0, 1]: return {}
	var view := state.duplicate(true)
	for key in ["_resolution", "rng_state", "seed", "next_uid", "next_hand_id", "next_modifier_id", "private_log", "telemetry", "telemetry_truncated", "starting_decks", "scheduled", "order_intercepts"]:
		view.erase(key)
	if view.has("pending_choice") and view.pending_choice.owner != player:
		view.pending_choice.erase("options")
		if view.pending_choice.get("kind","unit") != "unit": view.pending_choice["targets"] = []
	for i in 2:
		view.players[i].erase("hq_event_counts")
		view.players[i]["deck_count"] = view.players[i].deck.size()
		view.players[i]["hand_count"] = view.players[i].hand.size() if i==player else _held_cards(i).size()
		view.players[i]["counter_count"] = view.players[i].get("counters", []).size() if i==player else 0
		view.players[i].deck = []
		if i != player:
			view.players[i]["revealed_hand"] = []
			var held:=_held_cards(i)
			for position in held.size():
				var entry: Dictionary = held[position]
				if entry.get("revealed",false): view.players[i].revealed_hand.append({"position":position,"card":entry.card})
			view.players[i]["counters"] = []
			view.players[i].hand = []
			view.players[i].burned = []
	view["unit_activations"]={}
	for unit in state.units:
		if unit.owner!=player: continue
		var entries: Array=[]
		for entry in _abilities(_context(player,unit.uid,unit.card),"on_activate"):
			entries.append({"ability_index":entry.ability_index,"error":activation_error(player,unit.uid,entry.ability_index)})
		if not entries.is_empty(): view.unit_activations[str(unit.uid)]=entries
	view["presentation_events"] = _public_presentation_events()
	view.log = view.log.slice(maxi(0, view.log.size() - 60))
	return view

func _public_presentation_events() -> Array:
	# Only public, resolved effects. Draws, hand creation, deck searches and hidden
	# counter placements never export a name, hash, definition or private target.
	var result: Array = []
	var allowed := ["attack","move","deploy","generated_deploy","summon","damage","heal","death","destroy","counter_reveal","trigger","turn_start","play","generated_play","veteran"]
	for i in range(maxi(0,state.telemetry.size()-256),state.telemetry.size()):
		var event: Dictionary = state.telemetry[i]
		if not str(event.kind) in allowed: continue
		if event.kind in ["play","generated_play"] and event.get("card_kind")=="counter": continue
		var shown := {"id":i,"kind":event.kind,"owner":event.owner,"amount":event.amount}
		for key in ["name","uid","source_uid","target_uid","target_owner","card_kind","trigger","media"]:
			if event.has(key): shown[key]=event[key]
		if event.has("display_card"): shown["display_card"]=event.display_card.duplicate(true)
		result.append(shown)
	# Bound snapshot size. Older history retains names, never a hidden hand face.
	var displayed:=0
	for index in range(result.size()-1,-1,-1):
		if not result[index].has("display_card"): continue
		displayed+=1
		if displayed>4: result[index].erase("display_card")
	return result.slice(maxi(0,result.size()-128))

func _field_effects(unit: Dictionary, keywords_only: bool = false) -> Array:
	var effects := []
	var is_hq := not unit.has("uid")
	var seat: int = int(unit.get("owner",0)) if not is_hq else 0 if is_same(unit,state.players[0]) else 1
	var sources := _headquarters_sources()
	var field: Dictionary=state.get("field",{})
	if not field.is_empty(): sources.append({"owner":field.owner,"uid":-1,"card":field.card})
	for source in state.units:
		if not source.get("suppressed",false) and not source.get("destroyed",false): sources.append({"owner":source.owner,"uid":source.uid,"card":source.card})
	for source in sources:
		for ability in source.card.definition.abilities:
			if ability.trigger!="while_active" or keywords_only and not ability.effects.any(func(e):return e.op=="grant_keyword"): continue
			var context := {"owner":source.owner,"uid":source.uid,"card":source.card,"chosen":-1}
			if ability.has("premise") and not _premise_met(ability.premise,context,false): continue
			for effect in ability.effects:
				if not effect.has("target"): continue
				var matches := false
				if is_hq:
					matches = effect.target in ["own_hq","enemy_hq"] and (seat==int(source.owner))==(effect.target=="own_hq")
				else:
					matches = effect.target=="all_units" or effect.target=="self" and source.uid==unit.uid or effect.target=="adjacent_to_self" and unit.uid in _adjacent_targets("adjacent_to_self",context) or effect.target=="all_other_friendly_units" and seat==int(source.owner) and source.uid!=unit.uid or effect.target in ["all_friendly_units","all_enemy_units"] and (seat==int(source.owner))==(effect.target=="all_friendly_units")
				if not matches: continue
				if effect.has("unit_filter") and (is_hq or not _matches_unit_filter(unit,effect.unit_filter)): continue
				var resolved: Dictionary=effect.duplicate(true)
				resolved["aura_owner"]=source.owner
				for key in ["attack_delta","health_delta","amount"]:
					if resolved.get(key) is Dictionary: resolved[key]=_effect_value(resolved[key],context)
				effects.append(resolved)
	return effects

func _premise_value(value: Variant, context: Dictionary, spend: bool = true) -> int:
	if not value is Dictionary: return int(value)
	if value.has("stack_count") or value.has("unit_stat"): return _unit_value(value,context)
	if value.has("count_units"):
		var selector: Dictionary = value.count_units
		var total := 0
		var names := {}
		for unit in state.units:
			if spend: _spend("visits")
			if unit.hp <= 0 or unit.get("destroyed",false): continue
			if selector.side != "any" and ((unit.owner == context.owner) != (selector.side == "ally")): continue
			if selector.get("row","any") != "any" and selector.row != unit.row: continue
			if not _matches_class(unit,selector): continue
			if selector.has("adjacent_to") and not unit.uid in _adjacent_targets("adjacent_to_"+selector.adjacent_to,context): continue
			var card_name: String = _unit_definition(unit).name
			if selector.has("card_name") and card_name != selector.card_name: continue
			if selector.has("name_contains") and not card_name.contains(selector.name_contains): continue
			if selector.get("distinct_by") == "name" and names.has(card_name): continue
			names[card_name] = true
			total += 1
		return total
	var stat: String = value.stat
	var owner: int = 1 - int(context.owner) if stat.begins_with("enemy_") else int(context.owner)
	var player: Dictionary = state.players[owner]
	if stat.ends_with("_deaths_this_turn"):
		var deaths: Dictionary=state.get("unit_deaths_by_turn",{})
		return int(deaths.get(str(owner),0)) if int(deaths.get("turn",-1))==int(state.turn) else 0
	if stat.ends_with("_hand_count"): return player.hand.size()
	if stat.ends_with("_deck_count"): return player.deck.size()
	if stat.ends_with("_hq_health"): return int(player.hp)
	if stat.ends_with("_kredits"): return int(player.credits)
	if stat in ["source_attack", "source_health"]:
		var source := _unit(context.uid)
		return int(source.get("attack" if stat == "source_attack" else "hp", 0))
	if stat.ends_with("_front_count") or stat.ends_with("_support_count"):
		var total := 0
		var row := "front" if stat.ends_with("_front_count") else "support"
		for unit in state.units:
			if unit.owner == owner and unit.row == row and unit.hp > 0 and not unit.get("destroyed", false): total += 1
		return total
	return _effect_value(value, context)

func _premise_unit(target: String, context: Dictionary) -> Dictionary:
	var key: String = {"self":"uid","chosen":"chosen","trigger_unit":"trigger_unit","attack_target":"attack_target","effect_target":"effect_target"}.get(target,"")
	var unit := _unit(int(context.card.get("creator_uid",-1)) if target=="creator" else int(context.get(key,-1)))
	if unit.is_empty() or unit.hp <= 0 or unit.get("destroyed",false): return {}
	return unit

func _unit_value(value: Dictionary, context: Dictionary) -> int:
	var query: Dictionary = value.get("stack_count",value.get("unit_stat",{}))
	var unit := _premise_unit(query.target,context)
	if unit.is_empty() and query.target=="attack_target": unit=context.get("attack_target_snapshot",{})
	if unit.is_empty(): return 0
	if value.has("stack_count"): return stack_count(unit,query.stack)
	if query.stat=="operation_cost": return _operation_cost(unit)
	if query.stat=="cost": return int(unit.card.definition.cost)
	if query.stat=="max_health": return int(unit.max_hp)
	return int(_unit_definition(unit).get(query.stat.trim_prefix("base_"),0)) if str(query.stat).begins_with("base_") else int(unit.get("hp" if query.stat=="health" else "attack",0))

func _premise_units_available(p: Dictionary, context: Dictionary) -> bool:
	if p.test=="compare":
		for value in [p.left,p.right]:
			if value is Dictionary and (value.has("stack_count") or value.has("unit_stat")):
				if _premise_unit(value.get("stack_count",value.get("unit_stat",{})).target,context).is_empty(): return false
	if p.test in ["unit_keyword","unit_state","unit_matches","unit_side"]: return not _query_unit(p.target,context).is_empty()
	for child in p.get("items",[]):
		if not _premise_units_available(child,context): return false
	return _premise_units_available(p.item,context) if p.has("item") else true

func _printed_keyword(unit: Dictionary, keyword_id: String) -> bool:
	var definition: Dictionary = unit.card.get("source",unit.card.definition)
	if not unit.token_id.is_empty() and not unit.card.has("generated_origin"):
		for token in definition.tokens:
			if token.token_id == unit.token_id:
				definition = token
				break
	for keyword in definition.keywords:
		if keyword.id == keyword_id: return true
	return false

func _record_deployment(unit: Dictionary) -> void:
	var owner: int=unit.owner
	# A deployment during the other player's turn is not an own-turn deployment.
	if owner!=state.active_player: return
	var player: Dictionary=state.players[owner]
	if not player.has("deployments_this_turn"): player["deployments_this_turn"]=[]
	var d: Dictionary=unit.card.definition
	var record: Dictionary={"name":d.name,"sin":d.get("sin"),"faction_id":d.get("faction_id"),"unit_classes":_unit_classes(unit).duplicate()}
	if record in player.deployments_this_turn: return
	if player.deployments_this_turn.size()>=1024:
		_fault="RULE_BUDGET_EXCEEDED"
		return
	player.deployments_this_turn.append(record)

func _deployed_last_turn(p: Dictionary, context: Dictionary, spend: bool) -> bool:
	var owner: int=int(context.owner) if p.player=="owner" else 1-int(context.owner)
	var player: Dictionary=state.players[owner]
	# On the other side's turn, their last own turn is still the current snapshot.
	var key: String="deployments_previous_turn" if owner==state.active_player else "deployments_this_turn"
	for record in player.get(key,[]):
		if spend: _spend("visits")
		if not _fault.is_empty(): return false
		var f: Dictionary=p.filter
		if not _matches_sin(record,f): continue
		if f.has("faction_id") and record.faction_id!=f.faction_id: continue
		if f.has("card_name") and record.name!=f.card_name: continue
		if f.has("name_contains") and not str(record.name).contains(f.name_contains): continue
		if f.has("unit_classes") and not f.unit_classes.any(func(c):return c in record.unit_classes): continue
		return true
	return false

func _premise_met(p: Dictionary, context: Dictionary, spend: bool = true) -> bool:
	if p.test=="event_card": return _card_filter_matches(context.get("event_card",{}).get("definition",{}),p.filter)
	if p.test in ["hand_contains","played_this_turn"]:
		var side: int=int(context.owner) if p.player=="owner" else 1-int(context.owner)
		var cards: Array=state.players[side].hand.map(func(e):return e.card.definition) if p.test=="hand_contains" else state.players[side].get("played_cards_this_turn",[]) if int(state.players[side].get("played_cards_turn",-1))==int(state.turn) else []
		var count:=0
		for d in cards:
			if spend: _spend("visits")
			if not _fault.is_empty(): return false
			if _card_filter_matches(d,p.filter): count+=1
		return count>=int(p.get("min",1))
	if p.test=="deployed_last_turn": return _deployed_last_turn(p,context,spend)
	# Missing units invalidate the whole tree, including negated queries.
	if not _premise_units_available(p,context): return false
	if p.test=="unit_side": return (_query_unit(p.target,context).owner==context.owner)==(p.side=="ally")
	if p.test=="unit_matches": return _matches_unit_filter(_query_unit(p.target,context),p.filter)
	if p.test=="deck_top":
		var deck: Array=state.players[int(context.owner) if p.player=="owner" else 1-int(context.owner)].deck
		return not deck.is_empty() and int(deck.back().definition.cost)%2==(0 if p.parity=="even" else 1)
	if p.test == "destroyed_by": return p.unit_classes.any(func(c): return c in context.get("killer_classes",[]))
	if p.test == "previous_card":
		if spend: _spend("ops")
		var side: int=int(context.owner) if p.player=="owner" else 1-int(context.owner)
		var details: Dictionary=context.get("previous_card_details",[{},{}])[side]
		if p.get("this_turn",false) and int(details.get("turn",-1))!=int(state.turn): return false
		if p.has("card_name") and details.get("name")!=p.card_name: return false
		if p.has("filter") and not _card_filter_matches(details,p.filter): return false
		return _fault.is_empty() and str(context.get("previous_cards",["",""])[side])==p.kind
	if p.test == "turn_owner":
		if spend: _spend("ops")
		return _fault.is_empty() and int(state.active_player)==(int(context.owner) if p.side == "owner" else 1-int(context.owner))
	if p.test in ["unit_keyword","unit_state"]:
		if spend: _spend("ops")
		if not _fault.is_empty(): return false
		var unit := _query_unit(p.target,context)
		if p.test == "unit_state":
			if p.state=="is_liberated": return bool(unit.get("liberated",false))
			if p.state in ["in_front","in_support"]: return unit.row==("front" if p.state=="in_front" else "support")
			return bool(unit.get("is_veteran" if p.state=="is_veteran" else "has_attacked_in_play",false))
		if p.state == "printed": return _printed_keyword(unit,p.keyword_id)
		if p.state == "current": return _has_keyword(unit,p.keyword_id) or (not p.keyword_id.begins_with("core.") and not unit.get("suppressed",false) and _printed_keyword(unit,p.keyword_id))
		return bool(unit.get("consumed_keyword_history",{}).get(p.keyword_id,false))
	if spend: _spend("ops")
	if not _fault.is_empty(): return false
	if p.test == "not": return not _premise_met(p.item, context, spend)
	if p.test == "all":
		for item in p.items:
			if not _premise_met(item, context, spend): return false
		return true
	if p.test == "any":
		for item in p.items:
			if _premise_met(item, context, spend): return true
		return false
	var left := _premise_value(p.left, context, spend)
	var right := _premise_value(p.right, context, spend)+int(p.get("right_offset",0))
	return _compare(left,p.cmp,right)

func _compare(left: int, cmp: String, right: int) -> bool:
	match cmp:
		"gt": return left > right
		"gte": return left >= right
		"eq": return left == right
		"ne": return left != right
		"lte": return left <= right
		"lt": return left < right
	return false

func _queue_unit_event(unit: Dictionary, trigger: String, event_uid: int, event_card: Dictionary, damage: int = 0, death_snapshot: bool = false, extra: Dictionary = {}) -> void:
	var context := _context(unit.owner,unit.uid,unit.card)
	context["trigger_unit"]=event_uid
	context["event_card"]=event_card.duplicate(true)
	context["trigger_unit_snapshot"]=_unit(event_uid).duplicate(true)
	context["event_damage"]=damage
	context.merge(extra,true)
	for entry in _abilities(context,trigger):
		if trigger=="on_keyword_lost" and entry.ability.keyword_id!=context.get("lost_keyword"): continue
		if entry.ability.has("event_scope") and ((unit.uid==event_uid)!=(entry.ability.event_scope=="self")): continue
		var key:=_event_key(entry)
		var repetitions:=1
		if entry.ability.has("damage_step"):
			var progress:=int(unit.damage_progress.get(key,0))+damage
			repetitions=int(progress/int(entry.ability.damage_step))
			unit.damage_progress[key]=progress % int(entry.ability.damage_step)
		for i in repetitions:
			if entry.ability.has("limit") and int(unit.event_counts.get(key,0)) >= int(entry.ability.limit): break
			if entry.ability.has("premise") and not _premise_met(entry.ability.premise,context): continue
			if entry.ability.has("occurrence"):
				var seen: Dictionary=unit.get_or_add("event_seen",{})
				seen[key]=int(seen.get(key,0))+1
				if int(seen[key])!=int(entry.ability.occurrence): continue
			unit.event_counts[key]=int(unit.event_counts.get(key,0))+1
			var queued: Dictionary=entry.duplicate(true)
			queued.context=context.duplicate(true)
			queued["premise_checked"]=true
			queued["requires_source"]=not death_snapshot
			_events.append(queued)
			_spend("events")

func _event_key(entry: Dictionary) -> String:
	return str(entry.ability_index)+("@"+str(state.turn) if entry.ability.get("limit_scope")=="turn" else "")

func _emit_entry_event(unit: Dictionary) -> void:
	_emit_unit_event(unit.owner,"unit_entered",unit.uid,unit.card)

func _emit_unit_event(actor: int, event: String, uid: int, card: Dictionary) -> void:
	_headquarters_event(actor,event,uid,card)
	for unit in _ordered_units():
		if (unit.uid==uid and event in ["unit_entered","unit_became_veteran"]) or unit.hp<=0: continue
		_queue_unit_event(unit,("own_" if unit.owner==actor else "enemy_")+event,uid,card)
	_events.append_array(_scheduled_roots(event,actor,card,uid))

func _change_controller(unit: Dictionary, owner: int) -> void:
	_remove_from_line(unit)
	unit.owner=owner
	unit.row="support"
	unit.born_turn=int(state.turn)
	_position_unit(unit)
	_recompute(unit)
	_emit_entry_event(unit)
	_stat("control",owner,unit.card,1,{"uid":unit.uid})

func _expire_control(at_start: bool) -> void:
	for unit in state.units.duplicate():
		var layers: Array=unit.get("control_layers",[])
		# Nested temporary controls unwind from the most recent change.
		while not layers.is_empty():
			var layer: Dictionary=layers.back()
			if int(layer.expires_turn)>int(state.turn) or int(layer.expires_turn)==int(state.turn) and layer.at_start!=at_start: break
			layers.pop_back()
			if _count_row(layer.owner,"support")>=4:
				_remove_from_line(unit)
				unit.owner=layer.owner
				_leave_battlefield(unit,true)
				break
			_change_controller(unit,layer.owner)
	_checkpoint()
	_drain_deaths()

func _emit_card_event(actor: int, card: Dictionary, uid: int, listeners: Array, played: bool = true) -> void:
	var events: Array=["card_played"] if played else []
	if card.definition.kind in ["unit","order"]: events.push_front("unit_deployed" if card.definition.kind=="unit" else "order_played")
	for event in events:
		_headquarters_event(actor,event,uid,card)
		for listener in listeners:
			var unit:=_unit(int(listener))
			if unit.is_empty() or unit.hp<=0: continue
			_queue_unit_event(unit,("own_" if int(unit.owner)==actor else "enemy_")+event,uid,card)
		if event!="card_played": _events.append_array(_scheduled_roots(event,actor,card,uid))

func _record_played_card(owner: int, card: Dictionary) -> void:
	var player: Dictionary=state.players[owner]
	var d: Dictionary={"name":card.definition.name,"kind":card.definition.kind,"sin":card.definition.get("sin"),"turn":int(state.turn)}
	player["last_played_kind"]=str(d.kind)
	player["last_played_card"]=d
	if int(player.get("played_cards_turn",-1))!=int(state.turn):
		player["played_cards_this_turn"]=[]
		player["played_cards_turn"]=int(state.turn)
	if player.played_cards_this_turn.size()>=1024: _fault="RULE_BUDGET_EXCEEDED";return
	player.played_cards_this_turn.append(d)

func _matches_sin(d: Dictionary, f: Dictionary) -> bool:
	var sin=d.get("sin")
	return (not f.has("sin") or sin==f.sin) and (not f.has("sins") or sin in f.sins) and (not f.has("exclude_sins") or not sin in f.exclude_sins)

func _card_filter_matches(d: Dictionary, f: Dictionary) -> bool:
	if d.is_empty() or not _matches_sin(d,f): return false
	if f.has("card_name") and d.get("name")!=f.card_name: return false
	if f.has("name_contains") and not str(d.get("name","")).contains(f.name_contains): return false
	if f.has("kind") and d.get("kind")!=f.kind: return false
	return true

func _scheduled_roots(event: String, actor: int, event_card: Dictionary = {}, event_uid: int = -1) -> Array:
	var roots:=[]
	_prune_schedules()
	for schedule in state.get("scheduled",[]).duplicate():
		var eligible:=[]
		for index in schedule.groups:
			var a: Dictionary=schedule.ability if index == -1 else schedule.card.definition.abilities[index]
			var matches: bool=(event in ["unit_deployed","unit_entered","unit_attacked_hq"] and a.trigger=="next_own_"+event and actor==int(schedule.owner)) or (event=="order_played" and a.trigger=="next_own_order_played" and actor==int(schedule.owner)) or (event=="turn_start" and int(state.turn)>int(schedule.played_turn) and ((a.trigger=="next_own_turn_start" and actor==int(schedule.owner)) or (a.trigger=="next_opponent_turn_start" and actor!=int(schedule.owner))))
			if matches:
				if not schedule.has("remaining"): schedule["remaining"]={}
				var left: int=int(schedule.remaining.get(str(index),int(a.get("after_turns",1))))-1
				schedule.remaining[str(index)]=left
				if left<=0: eligible.append(index)
		# Snapshot all sibling branch conditions before any result changes the board.
		for index in eligible:
			var a: Dictionary=schedule.ability if index == -1 else schedule.card.definition.abilities[index]
			var context: Dictionary=schedule.context.duplicate(true) if schedule.has("context") else _context(schedule.owner,-1,schedule.card,int(schedule.chosen))
			# Explicit schedule captures its original source and selected instance.
			# Legacy next-order groups instead receive the newly matching event.
			if event != "turn_start" or not schedule.has("context"):
				context["event_card"]=event_card.duplicate(true)
				context["trigger_unit"]=event_uid
			context["once_per_card"]=schedule.get("once_per_card","")
			if not a.has("premise") or _premise_met(a.premise,context): roots.append({"context":context,"ability":a.duplicate(true),"ability_index":index,"premise_checked":true,"scheduled_lifetime":schedule.get("lifetime","match"),"scheduled_chosen":int(schedule.chosen),"scheduled_turn":int(schedule.played_turn)})
			if schedule.get("repeat") in ["each_turn","each_event"] and int(schedule.get("times",-1))!=1:
				if int(schedule.get("times",-1))>1: schedule.times-=1
				schedule.remaining[str(index)]=1
			else: schedule.groups.erase(index)
		if schedule.groups.is_empty(): state.scheduled.erase(schedule)
	return roots


func _schedule_alive(schedule: Dictionary) -> bool:
	var lifetime: String=schedule.get("lifetime","match")
	if lifetime=="match": return true
	if lifetime=="turn": return int(schedule.get("played_turn",-1))==int(state.turn)
	var uid: int=int(schedule.get("source_uid",-1) if lifetime=="source" else schedule.get("chosen",-1))
	if lifetime=="target" and uid in [-101,-102]: return state.players[-101-uid].hp>0
	var unit := _unit(uid)
	return not unit.is_empty() and unit.hp>0 and not unit.get("destroyed",false) and (lifetime!="source" or not unit.get("suppressed",false))

func _prune_schedules() -> void:
	state.scheduled=state.scheduled.filter(_schedule_alive)

func _prune_intercepts() -> void:
	state.order_intercepts=state.get("order_intercepts",[]).filter(func(e):return (e.duration!="end_of_turn" or int(e.played_turn)==int(state.turn)) and (e.duration!="battle" or _schedule_alive({"lifetime":"source","source_uid":e.source_uid})))

func _consume_order_intercept(actor: int) -> void:
	_prune_intercepts()
	for entry in state.order_intercepts:
		if int(entry.owner)==actor: continue
		state.order_intercepts.erase(entry)
		_counter_canceled=true
		_stat("counter_triggered",entry.owner,entry.card)
		_log("敌方指令被预备效果取消")
		return

func _transform_units(effect: Dictionary, context: Dictionary) -> void:
	var targets := _targets(effect.target,context)
	for uid in targets:
		var unit := _unit(int(uid))
		if unit.is_empty() or unit.hp<=0 or unit.get("destroyed",false): continue
		var card: Dictionary=context.get("event_card",{}).duplicate(true) if effect.op=="become_trigger_unit" else _generated_card(context.card,effect.token_id,int(context.uid))
		if card.is_empty(): continue
		if effect.op=="become_trigger_unit":
			for key in ["once_marks","match_layers","match_abilities","match_ability_sources","match_cost_layers","pending_layers","pending_abilities","hand_cost_layers"]: card.erase(key)
		if not _fault.is_empty(): return
		if effect.inherit=="permanent":
			for key in ["match_layers","match_abilities","match_ability_sources","match_cost_layers"]:
				if unit.card.has(key): card[key]=unit.card[key].duplicate(true)
		var owner: int=unit.owner
		var row: String=unit.row
		var original_line: Array=line_order(owner,row).duplicate()
		var support_line: Array=line_order(owner,"support").duplicate()
		var position: int=original_line.find(int(unit.uid))
		var departure := _context(unit.owner,unit.uid,unit.card)
		_remove_from_line(unit);state.units.erase(unit)
		_after_leave(unit,departure)
		state.discard.append({"owner":owner,"card":unit.card.duplicate(true),"source_uid":unit.uid})
		_stat("transform",owner,unit.card,1,{"uid":unit.uid})
		var replacement := _new_unit(owner,card,effect.get("token_id",""),true)
		replacement.row=row
		original_line[position]=int(replacement.uid)
		if row!="support": _write_line(owner,"support",support_line)
		_write_line(owner,row,original_line)
		_recompute(replacement)
		_initialize_summoned_unit(replacement)
		_prune_schedules()
		if not _fault.is_empty(): return

func _transfer_matches(card: Dictionary, f: Dictionary, context: Dictionary, summoning: bool) -> bool:
	var d: Dictionary=card.definition
	if summoning and d.kind!="unit": return false
	if not _matches_sin(d,f): return false
	for pair in [["card_name","name"],["kind","kind"],["faction_id","faction_id"]]:
		if f.has(pair[0]) and f[pair[0]]!=d.get(pair[1]): return false
	if f.has("unit_class") and not f.unit_class in _card_classes(card): return false
	if int(d.cost)<int(f.get("min_cost",0)) or int(d.cost)>int(f.get("max_cost",12)): return false
	if f.has("name_contains") and not str(d.name).contains(f.name_contains): return false
	var event: Dictionary=context.get("event_card",{}).get("definition",{})
	if f.get("event_faction",false) and (not event.has("faction_id") or d.get("faction_id")!=event.faction_id): return false
	if f.has("event_cost_distance") and (event.is_empty() or absi(int(d.cost)-int(event.cost))>int(f.event_cost_distance)): return false
	return true

func _transfer_pool(region: String, effect: Dictionary, context: Dictionary) -> Array:
	var owner: int=context.owner
	var pool:=[]
	match region:
		"attack_target":
			var snapshot: Dictionary=context.get("attack_target_snapshot",{})
			if not snapshot.is_empty(): pool=[snapshot.card]
		"event_card":
			if not context.get("event_card",{}).is_empty(): pool=[context.event_card]
		"self":
			# A live source can have gained permanent layers earlier in this group.
			# After death the captured context is the last state of the departed card.
			var source := _unit(int(context.uid))
			if effect.mode == "move":
				for entry in state.discard:
					if int(entry.owner)==owner and int(entry.get("source_uid",-1))==int(context.uid): pool.append(entry.card); break
			else: pool=[_departure_card(context.card if source.is_empty() else source.card)]
		"deck": pool=state.players[owner].deck.duplicate()
		"hand": pool=state.players[owner].hand.map(func(e):return e.card)
		"drawn":
			var ids: Array=context.get("drawn_cards",[]).filter(func(c):return int(c.owner)==owner).map(func(c):return c.get("instance_id",""))
			pool=state.players[owner].hand.filter(func(e):return e.instance_id in ids).map(func(e):return e.card)
		"discard":
			for entry in state.discard:
				if int(entry.owner)==owner: pool.append(entry.card)
		"starting_deck":
			var hashes: Dictionary={}
			for card in state.starting_decks[owner]:
				if not hashes.has(card.definition_hash): pool.append(card); hashes[card.definition_hash]=true
	return pool

func _transfer_card(effect: Dictionary, context: Dictionary) -> void:
	if effect.get("player")=="opponent":
		context=context.duplicate(true)
		context.owner=1-int(context.owner)
	var owner: int=context.owner
	var summoning: bool=effect.destination in ["support","source_position"]
	# Choose the first region with matching cards; never mix candidate regions.
	var sources: Array=[effect.source]
	sources.append_array(effect.get("fallback_sources",[]))
	var pool: Array=[]
	for source in sources:
		pool=_transfer_pool(str(source),effect,context)
		_spend("visits",pool.size())
		if not _fault.is_empty(): return
		pool=pool.filter(func(c):return _transfer_matches(c,effect.get("filter",{}),context,summoning))
		if not pool.is_empty(): break
	if effect.selection=="highest_cost" and not pool.is_empty():
		var cost:=0
		for card in pool: cost=maxi(cost,int(card.definition.cost))
		pool=pool.filter(func(c):return int(c.definition.cost)==cost)
	for i in _effect_value(effect.amount,context):
		if pool.is_empty() or not _fault.is_empty(): return
		if effect.destination=="deck" and state.players[owner].deck.size()>=100 and not (effect.source=="deck" and effect.mode=="move"): return
		var row: String=context.get("source_row","support") if effect.destination=="source_position" else "support"
		if summoning and not _unit_entry_allowed(owner): return
		if summoning and (_count_row(-1 if row=="front" else owner,row)>=(5 if row=="front" else 4) or (row=="front" and _count_row(1-owner,"front")>0)): return
		var index:=_choose_card(owner,pool,context,"search") if effect.selection=="chosen" else pool.size()-1 if effect.selection=="top" else _random_index(pool.size())
		if not _fault.is_empty(): return
		var card: Dictionary=pool[index].duplicate(true)
		card.erase("hand_cost_layers")
		var destination: String=effect.destination
		if destination=="hand" and effect.get("overflow")=="deck_top" and _held_cards(owner).size()>=10: destination="deck"
		if destination=="deck" and state.players[owner].deck.size()>=100: return
		if effect.mode == "copy":
			# Permanent enhancements belong to the copied card. Temporary in-play
			# state is not copied; pending nonpermanent enhancements also expire.
			for key in ["once_marks","pending_layers","pending_abilities"]: card.erase(key)
			if effect.has("inherit_from"): _filter_inherited_layers(card,effect.inherit_from)
			if effect.get("copy_state")=="current_stats":
				var snapshot: Dictionary=context.get("attack_target_snapshot",{})
				var display: Dictionary=Runtime.display_definition(card)
				card["pending_layers"]=[{"bucket":"modifiers","layer":{"attack_delta":int(snapshot.attack)-int(display.attack),"health_delta":int(snapshot.max_hp)-int(display.health),"expires_turn":-1}},{"bucket":"operation_costs","layer":{"cost_delta":int(snapshot.get("snapshot_operation_cost",_operation_cost(snapshot)))-int(display.operation_cost),"expires_turn":-1}}]
		if effect.mode=="move":
			if effect.source=="self":
				for key in ["once_marks","pending_layers","pending_abilities"]: card.erase(key)
			var original: Dictionary=pool[index]
			pool.remove_at(index)
			if effect.source=="deck": state.players[owner].deck.erase(original)
			elif effect.source in ["hand","drawn"]:
				for entry in state.players[owner].hand:
					if entry.card==original and (effect.source!="drawn" or context.get("drawn_cards",[]).any(func(c):return c.get("instance_id","")==entry.instance_id)):
						state.players[owner].hand.erase(entry); break
			elif effect.source=="self":
				for entry in state.discard:
					if int(entry.owner)==owner and int(entry.get("source_uid",-1))==int(context.uid): state.discard.erase(entry); break
			elif effect.source=="discard":
				for entry in state.discard:
					if int(entry.owner)==owner and entry.card==original: state.discard.erase(entry); break
		if destination=="hand": _receive_card(owner,card,"copy" if effect.mode=="copy" else "retrieve")
		elif destination=="deck":
			if state.players[owner].deck.size()>=100: return
			var before: int=state.players[owner].deck.size()
			var placement: String="top" if effect.destination=="hand" else str(effect.get("deck_position","random"))
			state.players[owner].deck.insert(before if placement=="top" else 0 if placement=="bottom" else _random_index(before+1),card)
			_stat("deck_insert",owner,card,1,{"source":effect.source,"mode":effect.mode,"deck_before":before,"deck_after":state.players[owner].deck.size()})
			_log("玩家 %d 将 1 张牌加入牌库，剩余 %d 张" % [owner+1,state.players[owner].deck.size()])
		else:
			if effect.has("copy_buff"):
				if card.get("match_layers",[]).size()+card.get("pending_layers",[]).size()>=64:
					_fault="RULE_BUDGET_EXCEEDED"
					return
				var buff: Dictionary=effect.copy_buff
				var key := "match_layers" if buff.duration=="match" else "pending_layers"
				if not card.has(key): card[key]=[]
				card[key].append({"bucket":"modifiers","layer":{"attack_delta":int(buff.attack_delta),"health_delta":int(buff.health_delta),"expires_turn":-1,"source_card_id":_enhancement_source(context),"source_uid":context.uid}})
			var unit:=_new_unit(owner,card,"",effect.get("entry","summon")!="deploy")
			if effect.destination=="source_position":
				_remove_from_line(unit)
				unit.row=row
				_position_unit(unit,int(context.get("source_position",-1))+i)
			if effect.get("entry","summon")=="deploy": _initialize_deployed_unit(unit)
			else: _initialize_summoned_unit(unit)


func _matches_class(unit: Dictionary, selector: Dictionary) -> bool:
	return _matches_unit_filter(unit,selector)

func _adjacent_targets(target: String, context: Dictionary) -> Array:
	var uid := int(context.get("trigger_unit",-1)) if target=="adjacent_to_trigger" else int(context.get("chosen",-1)) if target == "adjacent_to_chosen" else int(context.uid)
	var center := _unit(uid)
	var result := []
	if center.is_empty():
		if context.has("source_neighbors") and target == "adjacent_to_self": return context.source_neighbors.filter(func(id): return not _unit(int(id)).is_empty())
		# A death trigger uses the two surviving neighbours at its former slot.
		if target != "adjacent_to_self" or int(context.get("source_position",-1)) < 0: return result
		var line := line_order(int(context.owner),str(context.get("source_row","support")))
		for index in [int(context.source_position)-1,int(context.source_position)]:
			if index >= 0 and index < line.size() and int(line[index]) > 0: result.append(line[index])
	else:
		var line := line_order(int(center.owner),str(center.row))
		var at := line.find(uid)
		for index in [at-1,at+1]:
			if index >= 0 and index < line.size() and int(line[index]) > 0: result.append(line[index])
	return result

func _card_filter(card: Dictionary, filter: Dictionary) -> bool:
	var d: Dictionary = card.definition
	if filter.has("card_name") and d.name != filter.card_name: return false
	if filter.has("name_contains") and not str(d.name).contains(filter.name_contains): return false
	if filter.has("kind") and d.kind != filter.kind: return false
	if filter.has("faction_id") and d.get("faction_id") != filter.faction_id: return false
	if filter.has("unit_class") and not filter.unit_class in _card_classes(card): return false
	return true

func _choose_card(owner: int, options: Array, context: Dictionary, kind: String) -> int:
	if options.is_empty(): return -1
	if _choice_cursor >= 64:
		_fault = "RULE_BUDGET_EXCEEDED"
		return -1
	if _choice_cursor >= _choice_answers.size():
		state["pending_choice"] = {"choice_id":_resolution_id+"-"+str(_choice_cursor),"kind":kind,"owner":owner,"source_uid":context.uid,"source_name":context.card.definition.name,"trigger":"on_play","targets":[],"options":options.duplicate(true),"source_faction_id":context.card.definition.get("faction_id",""),"source_sin":context.card.definition.get("sin",null),"keyword_info":context.card.get("display_keywords",[])}
		_fault = "AWAITING_CHOICE"
		return -1
	var answer := int(_choice_answers[_choice_cursor])
	if answer < 0 or answer >= options.size():
		_fault = "INVALID_CHOICE_REPLAY"
		return -1
	_choice_cursor += 1
	return answer

func _card_research(effect: Dictionary, context: Dictionary) -> void:
	var pool: Array = []
	if effect.op == "research" or effect.source == "tokens":
		for token_id in effect.token_ids:
			pool.append(_generated_card(context.card,token_id,int(context.uid)))
			if not _fault.is_empty(): return
	else:
		var seen := {}
		for card in (state.players[int(context.owner)].deck if effect.get("source")=="deck" else state.starting_decks[int(context.owner)]):
			_spend("visits")
			if not seen.has(card.definition.name) and _card_filter(card,effect.get("filter",{})):
				pool.append(card if effect.source=="deck" else card.duplicate(true))
				seen[card.definition.name] = true
	if pool.is_empty(): return
	var options: Array = []
	if effect.op == "research": options = pool
	else:
		for i in mini(3,pool.size()):
			var at := _random_index(pool.size())
			options.append(pool[at])
			pool.remove_at(at)
	var selected := _choose_card(int(context.owner),options,context,effect.op)
	if not _fault.is_empty(): return
	if effect.get("source")=="deck": state.players[int(context.owner)].deck.erase(options[selected])
	_receive_card(int(context.owner),options[selected],effect.op)
	_stat(effect.op,int(context.owner),context.card)

func _modify_hand_cost(effect: Dictionary, context: Dictionary) -> void:
	var owner: int=context.owner
	if effect.selection=="self":
		var entry := _hand(owner,context.get("hand_instance_id",""))
		if not entry.is_empty(): _add_hand_cost(entry.card,effect,context)
		return
	var entries: Array=_held_cards(owner).filter(func(e): return _card_filter(e.card,effect.get("filter",{})))
	if effect.selection=="drawn":
		var drawn: Array=context.get("drawn_cards",[]).filter(func(c): return int(c.owner)==owner).map(func(c):return c.get("instance_id",""))
		entries=entries.filter(func(e):return e.instance_id in drawn)
	if entries.is_empty(): return
	if not effect.selection in ["all","drawn"]:
		var index: int=_choose_card(owner,entries.map(func(e):return e.card),context,"hand_cost") if effect.selection=="chosen" else _random_index(entries.size())
		if not _fault.is_empty(): return
		entries=[entries[index]]
	for entry in entries:
		_spend("visits")
		_add_hand_cost(entry.card,effect,context)
		if not _fault.is_empty(): return

func _add_hand_cost(card: Dictionary, effect: Dictionary, context: Dictionary) -> void:
	var key: String="match_cost_layers" if effect.duration=="match" else "hand_cost_layers"
	if card.get("match_cost_layers",[]).size()+card.get("hand_cost_layers",[]).size()>=64:
		_fault="RULE_BUDGET_EXCEEDED"
		return
	if not card.has(key): card[key]=[]
	card[key].append({"cost_delta":int(effect.cost_delta),"source_card_id":_enhancement_source(context),"expires_turn":int(state.turn) if effect.duration=="end_of_turn" else -1})

func _modify_cards(effect: Dictionary, context: Dictionary) -> void:
	var filter: Dictionary = effect.filter.duplicate(true)
	if filter.get("same_as_discarded",false):
		if not context.has("discarded_name"): return
		filter["card_name"] = context.discarded_name
	filter["kind"] = "unit"
	var owners: Array = [0,1] if effect.player == "both" else [int(context.owner) if effect.player == "owner" else 1-int(context.owner)]
	for owner in owners:
		if "battlefield" in effect.zones:
			for unit in state.units.duplicate():
				_spend("visits")
				var on_board_filter: Dictionary = filter.duplicate(true)
				on_board_filter.erase("unit_class")
				if unit.owner != owner or not _card_filter(unit.card,on_board_filter) or filter.has("unit_class") and not filter.unit_class in _unit_classes(unit): continue
				var target_context: Dictionary = context.duplicate(true)
				target_context.chosen = unit.uid
				if effect.get("attack_delta",0) != 0 or effect.get("health_delta",0) != 0:
					_effect({"op":"modify_stats","target":"chosen","attack_delta":effect.get("attack_delta",0),"health_delta":effect.get("health_delta",0),"duration":effect.duration},target_context)
				if effect.get("operation_cost_delta",0) != 0:
					_effect({"op":"modify_operation_cost","target":"chosen","cost_delta":effect.operation_cost_delta,"duration":effect.duration},target_context)
				if not unit.has("ability_layers"): unit["ability_layers"] = []
				if unit.ability_layers.size() + effect.get("grant_abilities",[]).size() > 16:
					_fault = "RULE_BUDGET_EXCEEDED"
					return
				unit.ability_layers.append_array(effect.get("grant_abilities",[]).duplicate(true))
				if effect.duration == "match":
					if not unit.card.has("match_abilities"): unit.card["match_abilities"] = []
					_save_match_abilities(unit.card,effect.get("grant_abilities",[]),context)
		for zone in ["hand","deck"]:
			if not zone in effect.zones: continue
			var cards: Array = _held_cards(owner).map(func(entry):return entry.card) if zone == "hand" else state.players[owner].deck
			for card in cards:
				_spend("visits")
				if not _card_filter(card,filter): continue
				var key := "match_layers" if effect.duration == "match" else "pending_layers"
				var ability_key := "match_abilities" if effect.duration == "match" else "pending_abilities"
				if card.get("match_layers",[]).size() + card.get("pending_layers",[]).size() + 2 > 64 or card.get("match_abilities",[]).size() + card.get("pending_abilities",[]).size() + effect.get("grant_abilities",[]).size() > 16:
					_fault = "RULE_BUDGET_EXCEEDED"
					return
				if not card.has(key): card[key] = []
				var layer := {"source_card_id":_enhancement_source(context),"source_uid":context.uid,"expires_turn":-1}
				if effect.get("attack_delta",0) != 0 or effect.get("health_delta",0) != 0:
					card[key].append({"bucket":"modifiers","layer":dict_merge(layer,{"attack_delta":effect.get("attack_delta",0),"health_delta":effect.get("health_delta",0)})})
				if effect.get("operation_cost_delta",0) != 0: card[key].append({"bucket":"operation_costs","layer":dict_merge(layer,{"cost_delta":effect.operation_cost_delta})})
				if not card.has(ability_key): card[ability_key] = []
				if effect.duration == "match": _save_match_abilities(card,effect.get("grant_abilities",[]),context)
				else: card[ability_key].append_array(effect.get("grant_abilities",[]).duplicate(true))

func dict_merge(left: Dictionary, right: Dictionary) -> Dictionary:
	var result := left.duplicate(true)
	result.merge(right,true)
	return result


func _complete_action(unit: Dictionary, action: String) -> void:
	if state.winner != -1 or not _fault.is_empty() or _unit(unit.uid).is_empty() or unit.hp <= 0: return
	var extra: Dictionary=unit.get("attack_context",{}) if action=="attack" else {}
	_queue_unit_event(unit,"after_"+action,unit.uid,unit.card,0,false,extra)
	_queue_unit_event(unit,"after_action",unit.uid,unit.card,0,false,extra)
	unit.erase("attack_context")
	_drain_deaths()

func _queue_field_death(fallen: Dictionary) -> void:
	var field: Dictionary = state.get("field",{})
	if field.is_empty(): return
	var context := _context(field.owner,-1,field.card)
	context["event_card"] = fallen.card.duplicate(true)
	for entry in _abilities(context,"own_unit_died" if field.owner == fallen.owner else "enemy_unit_died"):
		if entry.ability.has("premise") and not _premise_met(entry.ability.premise,context): continue
		if not field.has("event_counts"): field["event_counts"]={}
		var key := _event_key(entry)
		if entry.ability.has("limit") and int(field.event_counts.get(key,0)) >= int(entry.ability.limit): continue
		if entry.ability.has("occurrence"):
			var seen: Dictionary=field.get_or_add("event_seen",{})
			seen[key]=int(seen.get(key,0))+1
			if int(seen[key])!=int(entry.ability.occurrence): continue
		field.event_counts[key]=int(field.event_counts.get(key,0))+1
		entry["premise_checked"]=true
		_events.append(entry)
		_spend("events")

func _add_extra_rule(uid: int, effect: Dictionary, context: Dictionary) -> void:
	var unit: Dictionary = state.players[-uid-1] if uid < 0 else _unit(uid)
	if unit.is_empty(): return
	if not unit.has("extra_rules"): unit["extra_rules"]=[]
	var layer_count: int = unit.extra_rules.size()
	if uid >= 0:
		for bucket in ["modifiers","grants","attack_limits","operation_costs","combat_damage_rules","stack_layers"]: layer_count += unit.get(bucket,[]).size()
	if layer_count >= 64:
		_fault="RULE_BUDGET_EXCEEDED"
		return
	var layer: Dictionary = effect.duplicate(true)
	layer.erase("target");layer.erase("duration")
	layer["source_card_id"]=_enhancement_source(context)
	layer["beneficiary"]=context.owner
	layer["modifier_id"]=int(state.next_modifier_id)
	state.next_modifier_id+=1
	layer.merge(_effect_expiry(effect.duration,int(context.owner)),true)
	if effect.op == "grant_order_target_reward":
		layer["beneficiary"]=context.owner
		layer["created_resolution"]=_resolution_id
	unit.extra_rules.append(layer)
	if uid >= 0 and effect.duration == "match":
		if not unit.card.has("match_layers"):unit.card["match_layers"]=[]
		unit.card.match_layers.append({"bucket":"extra_rules","layer":layer.duplicate(true)})

func _strikes_first(unit: Dictionary, phase: String) -> bool:
	return unit.get("extra_rules",[]).any(func(e):return e.op == "set_combat_priority" and e.applies_to in [phase,"both"])

func _unit_classes(unit: Dictionary) -> Array:
	var classes: Array = [_unit_definition(unit).unit_class]
	for e in unit.get("extra_rules",[]):
		if e.op == "grant_unit_class" and not e.unit_class in classes: classes.append(e.unit_class)
	return classes

func _card_classes(card: Dictionary) -> Array:
	var classes := Runtime.definition_classes(card.definition)
	for saved in card.get("match_layers",[]) + card.get("pending_layers",[]):
		if saved.bucket == "extra_rules" and saved.layer.op == "grant_unit_class" and not saved.layer.unit_class in classes: classes.append(saved.layer.unit_class)
	return classes

func _incoming_damage(target: Dictionary, amount: int, kind: String, source: Dictionary = {}, source_card: Dictionary = {}) -> int:
	# Zero damage is not a damage event; vulnerability does not create one.
	if amount <= 0: return 0
	var bonus := 0
	var multiplier := 1
	var classes: Array=_unit_classes(source) if not source.is_empty() else _card_classes(source_card) if source_card.get("definition",{}).get("kind")=="unit" else []
	for e in target.get("extra_rules",[])+_field_effects(target):
		if e.op != "modify_incoming_damage" or not e.damage_kind in [kind,"both"]: continue
		var origin: Dictionary=source.card if not source.is_empty() else source_card
		if e.has("source_kind") and origin.get("definition",{}).get("kind")!=e.source_kind: continue
		if e.get("source_side","any")!="any":
			var actor: int=int(source.owner) if not source.is_empty() else int(source_card.get("damage_owner",-1))
			if actor<0 or (actor==int(e.get("aura_owner",e.get("beneficiary",-1))))!=(e.source_side=="ally"): continue
		if e.has("source_unit_classes") and not e.source_unit_classes.any(func(c):return c in classes): continue
		if e.get("immune",false): return 0
		multiplier=mini(1000,multiplier*int(e.get("multiplier",1)))
		if e.amount is Dictionary:
			# Compare current combatants for each hit. Orders/HQ without a unit source have no attack gap.
			if source.is_empty() or not target.has("attack"): continue
			var gap: int=maxi(0,int(target.attack)-int(source.attack))
			bonus-=int(gap/int(e.amount.attack_gap.step))*int(e.amount.attack_gap.reduction)
		else: bonus+=int(e.amount)
	return clampi(maxi(0,amount+bonus)*multiplier,0,1000)

func _order_target_reward(actor: int, chosen: int, card: Dictionary) -> void:
	var unit: Dictionary = state.players[-chosen-101] if chosen <= -101 else _unit(chosen)
	if unit.is_empty(): return
	for e in unit.get("extra_rules",[]):
		if e.op != "grant_order_target_reward" or int(e.beneficiary) != actor or e.get("created_resolution") == _resolution_id or e.get("last_resolution") == _resolution_id: continue
		e["last_resolution"]=_resolution_id
		var gain := mini(int(e.amount),maxi(0,int(state.players[actor].max_credits)-int(state.players[actor].credits)))
		state.players[actor].credits+=gain
		_stat("kredits_gained",actor,card,gain,{"target_uid":chosen})


func _summon_at_victim(token_id: String, slot: Dictionary, context: Dictionary) -> void:
	_spend("ops")
	if not _fault.is_empty(): return
	var owner: int = slot.owner
	var row: String = slot.row
	if not _unit_entry_allowed(owner): return
	if _count_row(-1 if row == "front" else owner,row) >= (5 if row == "front" else 4): return
	if row == "front" and _count_row(1-owner,"front") > 0: return
	var card := _generated_card(context.card,token_id,int(context.uid))
	if not _fault.is_empty(): return
	var unit := _new_unit(owner,card,token_id,false,int(slot.index) if row == "support" else -1)
	if row == "front":
		_remove_from_line(unit)
		unit.row = row
		_position_unit(unit,int(slot.index))
	_initialize_summoned_unit(unit)

func _enhancement_source(context: Dictionary) -> String:
	# Identity comes from the frozen server record, never from a mutable display name.
	return str(context.get("card",{}).get("telemetry_ref",{}).get("card_id",""))

func _save_match_abilities(card: Dictionary, abilities: Array, context: Dictionary) -> void:
	if not card.has("match_abilities"): card["match_abilities"]=[]
	if not card.has("match_ability_sources"): card["match_ability_sources"]=[]
	while card.match_ability_sources.size() < card.match_abilities.size(): card.match_ability_sources.append("")
	for ability in abilities:
		card.match_abilities.append(ability.duplicate(true))
		card.match_ability_sources.append(_enhancement_source(context))

func _filter_inherited_layers(card: Dictionary, sources: Array) -> void:
	var allowed: Array=sources.map(func(entry):return str(entry.card_id))
	if card.has("match_cost_layers"): card.match_cost_layers=card.match_cost_layers.filter(func(e):return str(e.get("source_card_id","")) in allowed)
	if card.has("match_layers"):
		card.match_layers=card.match_layers.filter(func(saved):return str(saved.layer.get("source_card_id","")) in allowed)
	var abilities: Array=[];var origins: Array=[];var saved_origins: Array=card.get("match_ability_sources",[])
	for index in card.get("match_abilities",[]).size():
		var origin: String=str(saved_origins[index]) if index < saved_origins.size() else ""
		if origin in allowed:
			abilities.append(card.match_abilities[index].duplicate(true));origins.append(origin)
	card["match_abilities"]=abilities;card["match_ability_sources"]=origins

func _become_veteran(unit: Dictionary) -> void:
	if unit.is_empty() or unit.hp<=0 or unit.get("destroyed",false) or unit.get("is_veteran",false): return
	var upgrade: Dictionary=unit.card.definition.get("veteran",{})
	if upgrade.is_empty(): return
	var original: Dictionary=unit.card.duplicate(true)
	var card := _generated_card(original,upgrade.token_id,unit.uid)
	if not _fault.is_empty() or card.is_empty(): return
	card["veteran_form"]=true
	var base_form: Dictionary=original.duplicate(true)
	for key in ["match_layers","match_abilities","match_ability_sources","match_cost_layers","pending_layers","pending_abilities","hand_cost_layers"]: base_form.erase(key)
	card["veteran_base"]=base_form
	# Changing form is not a deployment, summon, death or a new action budget.
	unit.card=card
	unit.token_id=str(upgrade.token_id)
	unit["is_veteran"]=true
	unit.damage_taken=0
	for bucket in ["modifiers","grants","attack_limits","operation_costs","combat_damage_rules","extra_rules","stack_layers","ability_layers"]: unit[bucket]=[]
	unit["equipment"]={};unit["equipment_sources"]=[]
	unit["bound_targets"]={};unit["event_counts"]={};unit["damage_progress"]={}
	unit["consumed_keyword_history"]={};unit["alpine_bonus"]=0;unit["mobilize_bonus"]=0
	unit.erase("suppressed");unit.erase("pinned_until");unit.erase("ambush_used_turn")
	_recompute(unit)
	# Innate stat rules initialize once, without firing ordinary on_play/on_summon.
	var context := _context(unit.owner,unit.uid,card)
	for ability in card.definition.abilities:
		if ability.trigger!="on_play" or ability.has("premise"): continue
		for effect in ability.effects:
			if effect.get("target")=="self" and effect.get("duration") in ["battle","match"] and effect.op in ["set_attack_limit","modify_operation_cost","set_combat_damage_multiplier","modify_stacks","set_stacks","set_combat_priority","grant_unit_class","modify_incoming_damage","grant_order_target_reward"]:
				_spend("ops")
				if not _fault.is_empty(): return
				_effect(effect,context)
	_stat("veteran",unit.owner,card,1,{"uid":unit.uid,"previous_name":original.definition.name})
	_log("%s 升为老兵" % original.definition.name)
	_summons.append_array(_binding_entries(_context(unit.owner,unit.uid,card)))
	_queue_unit_event(unit,"on_veteran",unit.uid,card)
	_emit_unit_event(unit.owner,"unit_became_veteran",unit.uid,card)

# Query snapshots retain identity for a target removed earlier in the same action.
# They never make the departed instance eligible for an effect or a new selection.
func _query_unit(target: String, context: Dictionary) -> Dictionary:
	var live := _premise_unit(target,context)
	return live if not live.is_empty() else context.get(target+"_snapshot",{})

func _after_leave(unit: Dictionary, context: Dictionary) -> void:
	_deaths.append_array(_abilities(context,"on_leave"))
	_release_suspended("source_leaves",int(unit.uid))

func _suspend_unit(unit: Dictionary, effect: Dictionary, context: Dictionary) -> void:
	if unit.is_empty(): return
	if effect.return_when=="source_leaves" and _unit(int(context.uid)).is_empty(): return
	if state.suspended.size()>=32: _fault="RULE_BUDGET_EXCEEDED";return
	var captured := _context(unit.owner,unit.uid,unit.card)
	var record := {"unit":unit.duplicate(true),"position":line_order(unit.owner,unit.row).find(unit.uid),"source_uid":int(context.uid),"turn":int(state.turn),"return_when":effect.return_when,"destination":effect.destination}
	if effect.has("return_cost"):record["return_cost"]=int(effect.return_cost)
	record["reset"]=effect.get("reset","none")
	if effect.return_when in ["next_own_turn_start","next_opponent_turn_start","next_own_turn_end","next_opponent_turn_end"]:
		var desired: int=int(context.owner) if effect.return_when in ["next_own_turn_start","next_own_turn_end"] else 1-int(context.owner)
		record["return_turn"]=int(state.turn)+(2 if desired==int(state.active_player) else 1)+2*(int(effect.get("after_turns",1))-1)
	state.suspended.append(record)
	_remove_from_line(unit)
	state.units.erase(unit)
	_after_leave(unit,captured)
	_stat("temporarily_remove",int(context.owner),context.card,1,{"target_uid":unit.uid})

func _release_suspended(when: String, uid: int = -1) -> void:
	for record in state.get("suspended",[]).duplicate():
		if (when=="turn_start" and (not record.has("return_turn") or int(record.return_turn)>int(state.turn) or not str(record.return_when).ends_with("_start"))) or (when=="turn_end" and (not record.has("return_turn") or int(record.return_turn)>int(state.turn) or not str(record.return_when).ends_with("_end"))) or (not when in ["turn_start","turn_end"] and record.return_when!=when) or (when=="source_leaves" and int(record.source_uid)!=uid) or (when=="end_of_turn" and int(record.turn)!=int(state.turn)): continue
		state.suspended.erase(record)
		var unit: Dictionary=record.unit
		if record.get("reset","none")!="none": _reset_suspended_unit(unit,record.reset=="temporary_and_damage")
		var owner: int=unit.owner
		var row: String=unit.row
		if record.destination=="original_position":
			if row=="front" and (_count_row(1-owner,"front")>0 or _count_row(-1,"front")>=5):row="support"
			if row=="support" and _count_row(owner,"support")>=4:row="hand"
		else:row="hand"
		if row=="hand":
			var card: Dictionary=unit.card.duplicate(true)
			if record.has("return_cost"):
				card["hand_cost_layers"]=[{"cost_set":int(record.return_cost),"expires_turn":-1}]
			_receive_card(owner,card,"return",true)
		else:
			unit.row=row
			state.units.append(unit)
			_position_unit(unit,int(record.position))
			_recompute(unit)
			_emit_entry_event(unit)
		_stat("temporary_return",owner,unit.card,1,{"uid":unit.uid})

func _evolution_schedule(uid: int) -> Dictionary:
	var unit:=_unit(uid)
	if unit.is_empty() or unit.hp<=0 or unit.get("suppressed",false): return {}
	for schedule in state.get("scheduled",[]):
		if int(schedule.get("source_uid",-1))!=uid or not schedule.has("ability"):continue
		if not Runtime.effect_leaves(schedule.ability.effects).any(func(e):return e.op=="transform" and e.target=="self"):continue
		if not _schedule_alive(schedule): continue
		return schedule
	return {}

func _advance_evolution(uid: int) -> void:
	_prune_schedules()
	var schedule:=_evolution_schedule(uid)
	if schedule.is_empty(): return
	state.scheduled.erase(schedule)
	_run_ability({"context":schedule.context.duplicate(true),"ability":schedule.ability.duplicate(true),"ability_index":-1})


func _unit_entry_allowed(owner: int) -> bool:
	var field: Dictionary=state.get("field",{})
	if field.is_empty(): return true
	var count: int=state.units.filter(func(u):return u.owner==owner).size()
	for a in field.card.definition.abilities:
		if a.trigger!="while_active": continue
		if a.has("premise") and not _premise_met(a.premise,{"owner":field.owner,"uid":-1,"card":field.card,"chosen":-1},false): continue
		for rule in a.effects:
			if rule.op=="unit_limit" and (rule.player=="both" or (owner==field.owner)==(rule.player=="owner")) and count>=int(rule.amount): return false
	return true

func _departure_card(card: Dictionary) -> Dictionary:
	if not card.has("liberated_base"): return card
	var original: Dictionary=card.liberated_base.duplicate(true)
	for key in ["match_layers","match_abilities","match_ability_sources","match_cost_layers"]:
		if card.has(key): original[key]=card[key].duplicate(true)
	return original

func _self_departure_event(unit: Dictionary, trigger: String) -> void:
	if unit.get("self_departure_running",false): return
	unit["self_departure_running"]=true
	var context := _context(unit.owner,unit.uid,unit.card)
	context["trigger_unit"]=unit.uid
	context["trigger_unit_snapshot"]=unit.duplicate(true)
	context["event_card"]=unit.card.duplicate(true)
	for entry in _abilities(context,trigger):
		if entry.ability.get("event_scope")!="self": continue
		var key := _event_key(entry)
		if entry.ability.has("limit") and int(unit.event_counts.get(key,0))>=int(entry.ability.limit): continue
		if entry.ability.has("premise") and not _premise_met(entry.ability.premise,context): continue
		if entry.ability.has("occurrence"):
			var seen: Dictionary=unit.get_or_add("event_seen",{})
			seen[key]=int(seen.get(key,0))+1
			if int(seen[key])!=int(entry.ability.occurrence): continue
		unit.event_counts[key]=int(unit.event_counts.get(key,0))+1
		entry["premise_checked"]=true
		_run_ability(entry)
		if not _fault.is_empty(): break
	unit.erase("self_departure_running")

func _liberate(unit: Dictionary, token_id: String) -> void:
	if unit.is_empty() or unit.get("liberated",false) or unit.hp<=0: return
	var original: Dictionary=unit.card.duplicate(true)
	var card := _generated_card(original,token_id,unit.uid)
	if card.is_empty() or not _fault.is_empty(): return
	card["liberated_base"]=original.duplicate(true)
	for key in ["match_layers","match_abilities","match_ability_sources","match_cost_layers"]: card.liberated_base.erase(key)
	card["liberated_form"]=true
	for key in ["match_layers","match_abilities","match_ability_sources","match_cost_layers"]:
		if original.has(key): card[key]=original[key].duplicate(true)
	unit.card=card
	unit["liberated"]=true
	# Keep uid, row, damage, enhancements, action counters and pin state.
	unit["bound_targets"]={}
	_recompute(unit)
	_stat("liberate",unit.owner,card,1,{"uid":unit.uid})
	_log("%s 解放" % original.definition.name)
	_summons.append_array(_binding_entries(_context(unit.owner,unit.uid,card)))

func _reshuffle_zones(effect: Dictionary, context: Dictionary) -> void:
	var seats: Array=[0,1] if effect.player=="both" else [context.owner if effect.player=="owner" else 1-int(context.owner)]
	var batches := {}
	for seat in seats:
		var cards := []
		if "hand" in effect.zones:
			for entry in _held_cards(seat):
				var card: Dictionary=entry.card.duplicate(true)
				card.erase("hand_cost_layers")
				cards.append(card)
		if "discard" in effect.zones:
			for entry in state.discard:
				if entry.owner==seat: cards.append(entry.card)
		if "battlefield" in effect.zones:
			for unit in state.units:
				if unit.owner==seat: cards.append(_departure_card(unit.card))
		if state.players[seat].deck.size()+cards.size()>100:
			_fault="RULE_BUDGET_EXCEEDED"
			return
		batches[seat]=cards
	# Snapshot both sides before any leave triggers resolve.
	for seat in seats:
		if "hand" in effect.zones:
			state.players[seat].hand.clear()
			state.players[seat].counters.clear()
		if "discard" in effect.zones: state.discard=state.discard.filter(func(e):return e.owner!=seat)
		if "battlefield" in effect.zones:
			for unit in state.units.duplicate():
				if unit.owner==seat: _leave_battlefield(unit,false)
		state.players[seat].deck.append_array(batches[seat])
		var deck: Array=state.players[seat].deck
		for i in range(deck.size()-1,0,-1):
			var j := _random_index(i+1)
			if not _fault.is_empty(): return
			var old: Dictionary=deck[i]
			deck[i]=deck[j];deck[j]=old
		_stat("reshuffle",seat,context.card,batches[seat].size())

func _initialize_deployed_unit(unit: Dictionary) -> void:
	_record_deployment(unit)
	if not _fault.is_empty(): return
	var context := _context(unit.owner,unit.uid,unit.card)
	var listeners: Array=_ordered_units().filter(func(u):return u.uid!=unit.uid).map(func(u):return int(u.uid))
	if unit.card.definition.play_target!=null:
		context.chosen=_choose_ability_target({"context":context,"ability":{"target":unit.card.definition.play_target,"trigger":"on_play"}})
		if not _fault.is_empty(): return
	_run_roots(_binding_entries(context))
	if not _fault.is_empty(): return
	_run_roots(_abilities(context,"on_play"))
	if not _fault.is_empty(): return
	_trigger_counters(unit.owner,"enemy_unit_deployed",unit.uid)
	if not _fault.is_empty(): return
	_emit_card_event(unit.owner,unit.card,unit.uid,listeners,false)
	if not _unit(unit.uid).is_empty(): _emit_entry_event(unit)

func _reset_suspended_unit(unit: Dictionary, heal_damage: bool) -> void:
	for key in ["modifiers","grants","attack_limits","operation_costs","combat_damage_rules","extra_rules","stack_layers"]: unit[key]=[]
	_initialize_innate_rules(unit,true)
	for saved in unit.card.get("match_layers",[]): unit[saved.bucket].append(saved.layer.duplicate(true))
	unit["ability_layers"]=unit.card.get("match_abilities",[]).duplicate(true)
	for key in ["suppressed","pin_until","mobilize_bonus","alpine_bonus","pinned_until"]: unit.erase(key)
	unit["equipment"]={}
	unit["equipment_sources"]=[]
	if heal_damage: unit.damage_taken=0
	_recompute(unit)


func _explicit_target_blocked(unit: Dictionary, source_card: Dictionary) -> bool:
	return _has_keyword(unit,"core.untargetable") or source_card.get("definition",{}).get("kind")=="order" and _has_keyword(unit,"core.order_untargetable")

func _emit_hand_death(fallen: Dictionary) -> void:
	for owner in [0,1]:
		for held in state.players[owner].hand:
			var context := _context(owner,-1,held.card)
			context.merge({"zone":"hand","hand_instance_id":held.instance_id,"trigger_unit":fallen.uid,"trigger_unit_snapshot":fallen.duplicate(true),"event_card":fallen.card.duplicate(true)},true)
			for entry in _abilities(context,"own_unit_died" if fallen.owner==owner else "enemy_unit_died"):
				_events.append(entry);_spend("events")

func _fighter_cover_allows(attacker: Dictionary, row: String, target_uid: int) -> bool:
	if _unit_definition(attacker).unit_class!="bomber" or _has_keyword(attacker,"core.ignore_fighter_cover"): return true
	var target := _unit(target_uid)
	if not target.is_empty() and _unit_definition(target).unit_class=="fighter": return true
	for defender in state.units:
		if defender.owner!=attacker.owner and defender.row==row and defender.hp>0 and not defender.get("destroyed",false) and _unit_definition(defender).unit_class=="fighter": return false
	return true


func _select_units(effect: Dictionary, context: Dictionary) -> void:
	var candidates: Array=[]
	for unit in _ordered_units():
		if (effect.side=="any" or (unit.owner==context.owner)==(effect.side=="ally")) and _matches_unit_filter(unit,effect.get("unit_filter",{})) and not _explicit_target_blocked(unit,context.card): candidates.append(int(unit.uid))
	var selected: Array=[]
	var minimum:=mini(int(effect.min),candidates.size())
	while not candidates.is_empty() and selected.size()<int(effect.max):
		if _choice_cursor>=64: _fault="RULE_BUDGET_EXCEEDED";return
		var targets:=candidates.duplicate()
		if selected.size()>=minimum: targets.append(-1000)
		if _choice_cursor>=_choice_answers.size():
			state["pending_choice"]={"choice_id":_resolution_id+"-"+str(_choice_cursor),"owner":context.owner,"source_uid":context.uid,"source_name":context.card.definition.name,"trigger":"on_play","side":effect.side,"targets":targets,"selected_units":selected.duplicate(),"max":effect.max,"min":minimum,"multi":true}
			_fault="AWAITING_CHOICE";return
		var answer:=int(_choice_answers[_choice_cursor])
		if not answer in targets: _fault="INVALID_CHOICE_REPLAY";return
		_choice_cursor+=1
		if answer==-1000: break
		selected.append(answer);candidates.erase(answer)
	context["selected_units"]=selected
	context["selected_destroyed_count"]=0
	if context.card.definition.kind=="order":
		for uid in selected: _order_target_reward(context.owner,uid,context.card)
