extends "res://tests/test_mechanics0110.gd"
## Run: godot --headless --path . --script tests/test_mechanics0120.gd
## Covers issues handled in 0.12.0: #108 #116 #126 #128 #131 #132 #133.

func _initialize() -> void:
	_forbid_play()
	_first_order_discount()
	_kredit_slot_gained()
	_counter_returned()
	_remove_abilities()
	_distinct_targets()
	_printed_keywords_rule()
	print("MECHANICS 0120: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _hand_card(g: RefCounted, owner: int, spec: Dictionary) -> String:
	var id: String = "h" + str(g.state.next_hand_id)
	g.state.next_hand_id += 1
	g.state.players[owner].hand.append({"instance_id": id, "card": _compile_with(spec)})
	return id

func _order(name: String, cost := 3) -> Dictionary:
	var spec := _base(name, "order")
	spec.cost = cost
	spec.abilities = [{"trigger": "on_play", "effects": [{"op": "gain_hq_defense", "player": "owner", "amount": 1}]}]
	return spec

func _turn(g: RefCounted) -> void:
	var player: int = g.state.active_player
	_check(g.apply_action(player, {"type": "end_turn"}).is_empty(), "end turn")
	var next: int = g.state.active_player
	g.state.players[next].credits = 12
	g.state.players[next].max_credits = 12

func _forbid_play() -> void:
	var spec := _base("乱魔", "order")
	spec.abilities = [{"trigger": "on_play", "effects": [{"op": "forbid_play", "player": "opponent", "card_kinds": ["order", "field"]}]}]
	var card := _compile_with(spec)
	_check(Runtime.rules_text(card).contains("敌方下个回合不能打出指令或场地"), "forbid_play has rules text (#126)")
	var aura := _base("封锁光环")
	aura.abilities = [{"trigger": "while_active", "effects": [{"op": "forbid_play", "player": "opponent", "card_kinds": ["order"]}]}]
	_compile_with(aura, false)
	var g := _game()
	var seat := _rich(g)
	var enemy := 1 - seat
	_run_effect(g, spec.abilities[0].effects[0], g._context(seat, -1, card))
	_turn(g)
	var order := _hand_card(g, enemy, _order("被封的指令"))
	var unit := _hand_card(g, enemy, _base("照常部署"))
	_check(g.legal_targets(enemy, {"type": "play", "hand_id": order}).is_empty(), "orders are banned on the opponent's next turn")
	_check(not g.legal_targets(enemy, {"type": "play", "hand_id": unit}).is_empty(), "other kinds stay playable")
	_check(not g.apply_action(enemy, {"type": "play", "hand_id": order, "target_uid": -1}).is_empty(), "a banned play is refused")
	_turn(g)
	_turn(g)
	_check(not g.legal_targets(enemy, {"type": "play", "hand_id": order}).is_empty(), "the ban ends after that turn")

func _first_order_discount() -> void:
	var spec := _base("黄金")
	spec.abilities = [{"trigger": "while_active", "effects": [{"op": "modify_play_cost", "cost_delta": -1, "filter": {"kind": "order"}, "first_each_turn": true}]}]
	var gold := _compile_with(spec)
	_check(Runtime.rules_text(gold).contains("己方每回合打出的第一张指令费用-1"), "play-cost aura has rules text (#131)")
	var wrong := _base("部署减费")
	wrong.abilities = [{"trigger": "on_play", "effects": [{"op": "modify_play_cost", "cost_delta": -1}]}]
	_compile_with(wrong, false)
	var g := _game()
	var seat := _rich(g)
	g._new_unit(seat, gold)
	var first := _hand_card(g, seat, _order("第一张", 3))
	var second := _hand_card(g, seat, _order("第二张", 3))
	var unit := _hand_card(g, seat, _base("单位不减"))
	var first_card: Dictionary = g._hand(seat, first).card
	_check(g.play_cost(seat, first_card) == 2, "the first order this turn is one cheaper")
	_check(g.play_cost(seat, g._hand(seat, unit).card) == 1, "other kinds keep their cost")
	_check(g.cost_breakdown(seat, first_card).parts.any(func(p): return p.get("source") == "黄金"), "breakdown names the aura")
	var credits := int(g.state.players[seat].credits)
	_check(g.apply_action(seat, {"type": "play", "hand_id": first, "target_uid": -1}).is_empty(), "play the first order")
	_check(int(g.state.players[seat].credits) == credits - 2, "it was paid at the reduced cost")
	_check(g.play_cost(seat, g._hand(seat, second).card) == 3, "the second order pays full cost")
	_turn(g)
	_turn(g)
	_check(g.play_cost(seat, g._hand(seat, second).card) == 2, "the discount returns next turn")
	var enemy_g := _game()
	var enemy_seat := 1 - _rich(enemy_g)
	enemy_g._new_unit(enemy_seat, gold)
	var own := _hand_card(enemy_g, 1 - enemy_seat, _order("对方的指令", 3))
	_check(enemy_g.play_cost(1 - enemy_seat, enemy_g._hand(1 - enemy_seat, own).card) == 3, "the aura only helps its owner")

func _kredit_slot_gained() -> void:
	var spec := _base("钻石")
	spec.abilities = [{"trigger": "own_kredit_slot_gained", "effects": [{"op": "draw", "player": "owner", "amount": 1}]}]
	var diamond := _compile_with(spec)
	_check(Runtime.rules_text(diamond).contains("己方因效果获得资源槽后"), "slot trigger has rules text (#132)")
	var watcher := _base("敌方观察")
	watcher.abilities = [{"trigger": "enemy_kredit_slot_gained", "effects": [{"op": "gain_hq_defense", "player": "owner", "amount": 1}]}]
	var g := _game()
	var seat: int = g.state.active_player
	var enemy := 1 - seat
	g.state.players[seat].max_credits = 3
	g._new_unit(seat, diamond)
	g._new_unit(enemy, _compile_with(watcher))
	var context: Dictionary = g._context(seat, -1, _compile(_base("来源")))
	_check(g._effect_value({"stat": "friendly_kredit_slots"}, context) == 3, "friendly_kredit_slots reads the slot count")
	_check(g._effect_value({"stat": "enemy_kredit_slots"}, context) == int(g.state.players[enemy].max_credits), "enemy_kredit_slots reads the other side")
	var hand := int(g.state.players[seat].hand.size())
	var enemy_hq := int(g.state.players[enemy].max_hp)
	_run_effect(g, {"op": "modify_kredit_slots", "player": "owner", "amount": 1}, context)
	_check(int(g.state.players[seat].hand.size()) == hand + 1, "gaining a slot draws a card")
	_check(int(g.state.players[enemy].max_hp) == enemy_hq + 1, "the enemy's listener sees it too")
	g.state.players[seat].max_credits = 12
	hand = int(g.state.players[seat].hand.size())
	_run_effect(g, {"op": "modify_kredit_slots", "player": "owner", "amount": 1}, context)
	_check(int(g.state.players[seat].hand.size()) == hand, "no slot gained at the cap, no trigger")
	_run_effect(g, {"op": "modify_kredit_slots", "player": "owner", "amount": -1}, context)
	_check(int(g.state.players[seat].hand.size()) == hand, "losing a slot does not trigger")

func _counter_returned() -> void:
	var spec := _base("流水钳蟹")
	spec.abilities = [{"trigger": "own_counter_returned", "effects": [{"op": "modify_hand_cost", "selection": "event_card", "cost_set": 0, "duration": "hand"}]}]
	var crab := _compile_with(spec)
	_check(Runtime.rules_text(crab).contains("己方伏置的反制未触发、返回手牌时") and Runtime.rules_text(crab).contains("这张返回手牌的牌费用变为0"), "counter-return trigger has rules text (#128)")
	var elsewhere := _base("错用事件卡")
	elsewhere.abilities = [{"trigger": "own_turn_start", "effects": [{"op": "modify_hand_cost", "selection": "event_card", "cost_set": 0, "duration": "hand"}]}]
	_compile_with(elsewhere, false)
	var both := _base("两种费用")
	both.abilities = [{"trigger": "own_turn_start", "effects": [{"op": "modify_hand_cost", "selection": "all", "cost_set": 0, "cost_delta": -1, "duration": "hand"}]}]
	_compile_with(both, false)
	var kinds := _base("指令减费")
	kinds.abilities = [{"trigger": "own_turn_start", "effects": [{"op": "modify_hand_cost", "selection": "all", "cost_delta": -1, "duration": "end_of_turn", "filter": {"kind": "counter"}}]}]
	_check(Runtime.rules_text(_compile_with(kinds)).contains("己方手牌中的反制费用-1"), "hand-cost text names the card kind")
	var g := _game()
	var seat := _rich(g)
	g._new_unit(seat, crab)
	var counter := _counter("暗礁", "enemy_hq_attacked", [{"op": "gain_hq_defense", "player": "owner", "amount": 1}])
	counter.cost = 4
	_arm(g, seat, counter)
	var returned_id: String = g.state.players[seat].counters[0].instance_id
	var fresh := _hand_card(g, seat, counter)
	g._reset_budget()
	g._return_counters(seat)
	g._drain_deaths()
	_check(g.play_cost(seat, g._hand(seat, returned_id).card) == 0, "the returned counter now costs 0")
	_check(g.play_cost(seat, g._hand(seat, fresh).card) == 4, "a counter that was never set keeps its cost")

func _remove_abilities() -> void:
	var spec := _base("MAGIC", "order")
	spec.play_target = {"side": "enemy", "row": "any"}
	spec.abilities = [{"trigger": "on_play", "effects": [{"op": "remove_keyword", "target": "chosen", "keyword_id": "core.guard"}, {"op": "remove_abilities", "target": "chosen", "trigger": "on_death", "duration": "battle"}]}]
	var magic := _compile_with(spec)
	_check(Runtime.rules_text(magic).contains("失去“阵亡”能力"), "remove_abilities has rules text (#108)")
	var g := _game()
	var seat := _rich(g)
	var enemy := 1 - seat
	var dying := _base("亡记单位")
	dying.abilities = [{"trigger": "on_death", "effects": [{"op": "gain_hq_defense", "player": "owner", "amount": 3}]}]
	var silenced: Dictionary = g._new_unit(enemy, _compile_with(dying))
	var control: Dictionary = g._new_unit(enemy, _compile_with(dying))
	var context: Dictionary = g._context(seat, -1, magic, int(silenced.uid))
	_run_effect(g, spec.abilities[0].effects[1], context)
	var before := int(g.state.players[enemy].max_hp)
	_run_effect(g, {"op": "destroy", "target": "chosen"}, context)
	_check(int(g.state.players[enemy].max_hp) == before, "the silenced unit's death ability does not fire")
	_run_effect(g, {"op": "destroy", "target": "chosen"}, g._context(seat, -1, magic, int(control.uid)))
	_check(int(g.state.players[enemy].max_hp) == before + 3, "an untouched unit still has its death ability")
	var brief: Dictionary = g._new_unit(enemy, _compile_with(dying))
	_run_effect(g, {"op": "remove_abilities", "target": "chosen", "trigger": "on_death", "duration": "end_of_turn"}, g._context(seat, -1, magic, int(brief.uid)))
	_check(g._abilities(g._context(enemy, int(brief.uid), brief.card), "on_death").is_empty(), "removed for this turn")
	g.state.turn = int(g.state.turn) + 1
	_check(not g._abilities(g._context(enemy, int(brief.uid), brief.card), "on_death").is_empty(), "and back afterwards")

func _distinct_targets() -> void:
	var spec := _base("刀光剑影", "order")
	spec.cost = 6
	spec.abilities = [{"trigger": "on_play", "effects": [{"op": "select_units", "side": "enemy", "min": 3, "max": 3}, {"op": "damage", "target": "selected_units", "amount": 3}]}]
	var card := _compile_with(spec)
	_check(Runtime.rules_text(card).contains("所选单位"), "selected damage has rules text (#133)")
	var loose := _base("未先选择", "order")
	loose.abilities = [{"trigger": "on_play", "effects": [{"op": "damage", "target": "selected_units", "amount": 3}]}]
	_compile_with(loose, false)
	var g := _game()
	var seat := _rich(g)
	var enemy := 1 - seat
	var targets: Array = []
	for i in 3: targets.append(_veteran_unit(g, enemy, "目标%d" % i))
	var id := _hand_card(g, seat, spec)
	_check(g.apply_action(seat, {"type": "play", "hand_id": id, "target_uid": -1}).is_empty(), "play the order")
	var picks := 0
	while g.state.has("pending_choice") and picks < 6:
		var choice: Dictionary = g.state.pending_choice
		var pick: int = choice.targets.filter(func(t): return int(t) > 0)[0]
		_check(g.apply_action(seat, {"type": "choose_target", "choice_id": choice.choice_id, "target_uid": pick}).is_empty(), "choose a target")
		picks += 1
	_check(picks == 3, "three choices are asked")
	_check(targets.all(func(u): return int(g._unit(int(u.uid)).get("hp", 0)) == 1), "each enemy unit took 3 damage once")

func _printed_keywords_rule() -> void:
	var armored := _base("部署重甲")
	armored.abilities = [{"trigger": "on_play", "effects": [{"op": "modify_stacks", "target": "self", "stack": "heavy_armor", "amount": 1, "duration": "battle"}]}]
	_compile_with(armored, false)
	var guarded := _base("部署守护")
	guarded.abilities = [{"trigger": "on_play", "effects": [{"op": "grant_keyword", "target": "self", "keyword_id": "core.guard", "keyword_version": 1, "duration": "battle"}]}]
	_compile_with(guarded, false)
	var brief := _base("本回合守护")
	brief.abilities = [{"trigger": "on_play", "effects": [{"op": "grant_keyword", "target": "self", "keyword_id": "core.guard", "keyword_version": 1, "duration": "end_of_turn"}]}]
	_compile_with(brief)
	var conditional := _base("条件重甲")
	conditional.abilities = [{"trigger": "on_play", "premise": {"test": "compare", "left": {"stat": "friendly_unit_count"}, "cmp": "gte", "right": 2}, "effects": [{"op": "modify_stacks", "target": "self", "stack": "heavy_armor", "amount": 1, "duration": "battle"}]}]
	_compile_with(conditional)
	var on_death := _base("阵亡给友军")
	on_death.abilities = [{"trigger": "on_death", "effects": [{"op": "modify_stacks", "target": "random_friendly_unit", "stack": "heavy_armor", "amount": 1, "duration": "battle"}]}]
	_compile_with(on_death)
