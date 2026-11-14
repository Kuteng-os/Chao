extends "res://tests/test_engine.gd"
## Run: godot --headless --path . --script tests/test_mechanics0110.gd
## Covers issues #47-#102 handled in 0.11.0: #49 #52 #55 #66 #67 #68 #80 #81 #85 #90 #91 #100 #102.

func _initialize() -> void:
	_cost_cap()
	_draw_counts_and_dynamic_amounts()
	_cost_per_draw()
	_draw_filters()
	_random_summon_beside_hq()
	_swap_and_move()
	_redirect_attack()
	_grant_action()
	_counter_listeners()
	_ability_and_move_counters()
	_attack_changed()
	_first_unit_played()
	_compile_rules()
	_deck_rules()
	print("MECHANICS 0110: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _compile_with(card: Dictionary, expect_ok := true) -> Dictionary:
	var result := Runtime.compile_card(card, Runtime.builtin_keywords())
	_check(result.ok == expect_ok, ("fixture compiles: " if expect_ok else "fixture is rejected: ") + str(card.get("name", "")) + " " + result.get("error", ""))
	return result

func _run_effect(g: RefCounted, effect: Dictionary, context: Dictionary) -> void:
	g._reset_budget()
	g._effect(effect, context)
	g._checkpoint()
	g._drain_deaths()

func _token(id: String, name: String, attack := 1, health := 3) -> Dictionary:
	return {"token_id": id, "name": name, "unit_class": "infantry", "attack": attack, "health": health, "keywords": []}

func _veteran_unit(g: RefCounted, seat: int, name: String, row := "support") -> Dictionary:
	var unit: Dictionary = g._new_unit(seat, _compile(_base(name)))
	unit.born_turn = int(g.state.turn) - 1
	if row == "front":
		g._remove_from_line(unit)
		unit.row = "front"
		g._position_unit(unit)
	return unit

func _arm(g: RefCounted, owner: int, counter: Dictionary) -> void:
	var entry := {"instance_id": "c" + str(g.state.next_hand_id), "card": _compile_with(counter), "armed_turn": int(g.state.turn) - 1}
	g.state.next_hand_id += 1
	g.state.players[owner].get_or_add("counters", []).append(entry)
	g.state.players[owner].credits = 12
	g.state.players[owner].max_credits = 12

func _counter(name: String, trigger: String, effects: Array) -> Dictionary:
	var counter := _base(name, "counter")
	counter.appearance.emblem = "counter"
	counter["counter_trigger"] = trigger
	counter.abilities = [{"trigger": "on_reveal", "effects": effects}]
	return counter

func _cost_cap() -> void:
	var big := _base("十五费")
	big.cost = 15
	_compile_with(big)
	big.cost = 20
	_compile_with(big)
	big.cost = 21
	_compile_with(big, false)

func _draw_counts_and_dynamic_amounts() -> void:
	var g := _game()
	var seat := _rich(g)
	var enemy := 1 - seat
	var source := _compile(_base("来源"))
	var context: Dictionary = g._context(seat, -1, source)
	var before := int(g.state.players[seat].get("draws", 0))
	_check(before > 0, "opening draws are counted")
	_run_effect(g, {"op": "draw", "player": "owner", "amount": 2}, context)
	_check(int(g.state.players[seat].draws) == before + 2, "each draw is counted")
	_check(g._effect_value({"stat": "friendly_draws_this_game"}, context) == before + 2, "friendly_draws_this_game reads the count")
	_check(g._effect_value({"stat": "enemy_draws_this_game"}, context) == int(g.state.players[enemy].get("draws", 0)), "enemy_draws_this_game reads the other side")
	g.state.players[seat].hand = []
	g.state.players[enemy].hand = []
	for i in 3: g.state.players[enemy].hand.append({"instance_id": "e%d" % i, "card": source})
	_check(g._effect_value({"stat": "hand_shortfall"}, context) == 3, "hand_shortfall is the gap to the enemy hand")
	_run_effect(g, {"op": "draw", "player": "owner", "amount": {"stat": "hand_shortfall"}}, context)
	_check(g.state.players[seat].hand.size() == 3, "draw until hands are level (#85)")
	_run_effect(g, {"op": "draw", "player": "owner", "amount": {"stat": "hand_shortfall"}}, context)
	_check(g.state.players[seat].hand.size() == 3, "no shortfall, no draw")
	g.state.players[seat]["draws"] = 25
	var hq_before := int(g.state.players[seat].max_hp)
	_run_effect(g, {"op": "gain_hq_defense", "player": "owner", "amount": {"stat": "friendly_draws_this_game"}}, context)
	_check(int(g.state.players[seat].max_hp) == hq_before + 10, "HQ defense from a value stops at 10 (#67)")

func _cost_per_draw() -> void:
	var spec := _base("黄金档播出员")
	spec.cost = 15
	spec["cost_reduction"] = {"per_draw": true, "amount": 1}
	var compiled := _compile_with(spec)
	_check(Runtime.rules_text(compiled).contains("每抽一张牌"), "per-draw reduction has rules text")
	var g := _game()
	var seat := _rich(g)
	g.state.players[seat].hand = []
	g._receive_card(seat, compiled, "draw")
	var card: Dictionary = g.state.players[seat].hand[0].card
	_check(g.play_cost(seat, card) == 15, "full cost when it arrives")
	for i in 3: g._draw(seat)
	_check(g.play_cost(seat, card) == 12, "one cheaper for each card drawn since")
	_check(g.cost_breakdown(seat, card).parts.any(func(p): return p.get("source") == "按抽牌减费"), "breakdown names the draw reduction")
	var both := _base("两种减费")
	both["cost_reduction"] = {"per_draw": true, "per_unit": {"side": "ally", "row": "any"}, "amount": 1}
	_compile_with(both, false)

func _draw_filters() -> void:
	var g := _game()
	var seat := _rich(g)
	g.state.players[seat].hand = []
	var context: Dictionary = g._context(seat, -1, _compile(_base("来源")))
	var deck_before: int = g.state.players[seat].deck.size()
	_run_effect(g, {"op": "draw", "player": "owner", "amount": 1, "filter": {"kind": "unit", "unit_classes": ["infantry"]}}, context)
	_check(g.state.players[seat].hand.is_empty() and g.state.players[seat].deck.size() == deck_before, "no match, nothing happens (#102)")
	_run_effect(g, {"op": "draw", "player": "owner", "amount": 1, "filter": {"kind": "unit", "unit_classes": ["tank"], "max_cost": 1}}, context)
	_check(g.state.players[seat].hand.size() == 1, "a matching card is drawn")
	var filtered := _base("按条件检索", "order")
	filtered.abilities = [{"trigger": "on_play", "effects": [{"op": "draw", "player": "owner", "amount": 1, "filter": {"kind": "unit", "sins": ["wrath"], "min_cost": 2, "max_cost": 5, "keyword_id": "core.guard"}}]}]
	_check(Runtime.rules_text(_compile_with(filtered)).contains("费用2至5"), "filtered draw has rules text")

func _random_summon_beside_hq() -> void:
	var spec := _base("山地攻势", "order")
	spec.tokens = [_token("a", "甲"), _token("b", "乙")]
	spec.abilities = [{"trigger": "on_play", "effects": [{"op": "summon", "token_ids": ["a", "b"], "amount": 1, "row": "support", "position": "beside_hq"}]}]
	var card := _compile_with(spec)
	var g := _game()
	var seat := _rich(g)
	_veteran_unit(g, seat, "已有单位")
	var context: Dictionary = g._context(seat, -1, card)
	_run_effect(g, spec.abilities[0].effects[0], context)
	var uid: int = context.summoned_uids.back()
	var unit: Dictionary = g._unit(uid)
	_check(g._unit_definition(unit).name in ["甲", "乙"], "one of the listed tokens (#80)")
	var line: Array = g.line_order(seat, "support")
	_check(line.find(uid) == line.find(-1) + 1, "it stands beside the HQ (#90)")
	var names := {}
	for i in 12:
		var ctx: Dictionary = g._context(seat, -1, card)
		_run_effect(g, spec.abilities[0].effects[0], ctx)
		if not ctx.get("summoned_uids", []).is_empty():
			names[g._unit_definition(g._unit(ctx.summoned_uids.back())).name] = true
			g._remove_from_line(g._unit(ctx.summoned_uids.back()))
			g.state.units.erase(g._unit(ctx.summoned_uids.back()))
	_check(names.size() == 2, "both tokens come up over several summons")

func _swap_and_move() -> void:
	var g := _game()
	var seat := _rich(g)
	var a := _veteran_unit(g, seat, "飞霄一室", "front")
	var b := _veteran_unit(g, seat, "后援单位")
	_run_effect(g, {"op": "swap_position", "target": "chosen", "with": "self"}, g._context(seat, a.uid, a.card, b.uid))
	_check(g._unit(a.uid).row == "support" and g._unit(b.uid).row == "front", "the two units trade rows (#91)")
	var order := _base("推进", "order")
	order.tokens = [_token("t", "先锋")]
	order.abilities = [{"trigger": "on_play", "effects": [{"op": "summon", "token_id": "t", "amount": 1, "row": "support"}, {"op": "move_unit", "target": "summoned", "row": "front"}]}]
	var card := _compile_with(order)
	var context: Dictionary = g._context(seat, -1, card)
	for effect in order.abilities[0].effects: _run_effect(g, effect, context)
	_check(g._unit(context.summoned_uids.back()).row == "front", "the summoned unit moves to the front")
	var wrong := _base("没召唤就移动", "order")
	wrong.abilities = [{"trigger": "on_play", "effects": [{"op": "move_unit", "target": "summoned", "row": "front"}]}]
	_compile_with(wrong, false)

func _redirect_attack() -> void:
	var g := _game()
	var seat := _rich(g)
	var enemy := 1 - seat
	var counter := _counter("关键防御", "enemy_hq_attacked", [{"op": "summon", "token_id": "w", "amount": 1, "row": "support", "position": "beside_hq"}, {"op": "redirect_attack", "target": "summoned"}])
	counter.tokens = [_token("w", "西部2科", 1, 9)]
	_arm(g, enemy, counter)
	var attacker := _veteran_unit(g, seat, "攻击者", "front")
	var hq_before := int(g.state.players[enemy].hp)
	var error: String = g.apply_action(seat, {"type": "attack", "uid": attacker.uid, "target_uid": -1})
	_check(error.is_empty(), "attack resolves: " + error)
	_check(int(g.state.players[enemy].hp) == hq_before, "the HQ is spared (#90)")
	var guard: Array = g.state.units.filter(func(u): return g._unit_definition(u).name == "西部2科")
	_check(not guard.is_empty() and int(guard[0].hp) < 9, "the summoned unit takes the attack")
	_check(int(g._unit(attacker.uid).hp) < 4, "and strikes back")
	var wrong := _counter("错时机改向", "enemy_order_played", [{"op": "redirect_attack", "target": "random_friendly_unit"}])
	_compile_with(wrong, false)
	var reads := _counter("读攻击者", "enemy_hq_attacked", [{"op": "damage", "target": "trigger_unit", "amount": {"unit_stat": {"target": "trigger_unit", "stat": "attack"}}}])
	_compile_with(reads)

func _grant_action() -> void:
	var g := _game()
	var seat := _rich(g)
	var enemy := 1 - seat
	var unit := _veteran_unit(g, seat, "暗礁单位", "front")
	var target := _veteran_unit(g, enemy, "敌方单位")
	var credits := int(g.state.players[seat].credits)
	var context: Dictionary = g._context(seat, unit.uid, unit.card)
	context["trigger_unit"] = target.uid
	_run_effect(g, {"op": "grant_action", "target": "self", "action": "attack", "attack_target": "trigger_unit"}, context)
	_check(int(g._unit(target.uid).hp) < 4 or g._unit(target.uid).is_empty(), "the granted attack lands (#55)")
	_check(int(g.state.players[seat].credits) == credits and int(g._unit(unit.uid).attacks_used) == 0, "it costs nothing and uses no attack")
	var listener := _base("伏击者")
	listener.abilities = [{"trigger": "enemy_unit_entered", "effects": [{"op": "grant_action", "target": "self", "action": "attack", "attack_target": "trigger_unit"}]}]
	_compile_with(listener)
	var missing := _base("没有对象")
	missing.abilities = [{"trigger": "enemy_unit_entered", "effects": [{"op": "grant_action", "target": "self", "action": "attack"}]}]
	_compile_with(missing, false)
	var mover := _veteran_unit(g, seat, "推进者")
	_run_effect(g, {"op": "grant_action", "target": "self", "action": "move"}, g._context(seat, mover.uid, mover.card))
	_check(g._unit(mover.uid).row == "front", "a granted move goes to the front")

func _counter_listeners() -> void:
	var g := _game()
	var seat := _rich(g)
	var enemy := 1 - seat
	_arm(g, enemy, _counter("加固", "enemy_hq_attacked", [{"op": "gain_hq_defense", "player": "owner", "amount": 1}]))
	var spec := _base("暗礁哨兵")
	spec.abilities = [{"trigger": "own_counter_triggered", "effects": [{"op": "gain_hq_defense", "player": "owner", "amount": 2}]}]
	var sentinel: Dictionary = g._new_unit(enemy, _compile_with(spec))
	var attacker := _veteran_unit(g, seat, "攻击者", "front")
	var before := int(g.state.players[enemy].max_hp)
	g.apply_action(seat, {"type": "attack", "uid": attacker.uid, "target_uid": -1})
	_check(int(g.state.players[enemy].max_hp) == before + 3, "the counter and its listener both resolve (#52)")
	_check(not sentinel.is_empty(), "listener stays")

func _ability_and_move_counters() -> void:
	var g := _game()
	var seat := _rich(g)
	var enemy := 1 - seat
	_arm(g, enemy, _counter("干扰能力", "enemy_unit_ability_triggered", [{"op": "gain_hq_defense", "player": "owner", "amount": 1}]))
	var before := int(g.state.players[enemy].max_hp)
	var spec := _base("有部署能力")
	spec.abilities = [{"trigger": "on_play", "effects": [{"op": "gain_hq_defense", "player": "owner", "amount": 1}]}]
	_play(g, spec)
	_check(int(g.state.players[enemy].max_hp) == before + 1, "an enemy unit's ability springs the counter (#49)")
	g = _game()
	seat = _rich(g)
	enemy = 1 - seat
	_arm(g, enemy, _counter("拦截推进", "enemy_unit_moved_to_front", [{"op": "gain_hq_defense", "player": "owner", "amount": 1}]))
	_arm(g, enemy, _counter("干扰行动", "enemy_unit_acted", [{"op": "gain_hq_defense", "player": "owner", "amount": 2}]))
	before = int(g.state.players[enemy].max_hp)
	var mover := _veteran_unit(g, seat, "推进者")
	var error: String = g.apply_action(seat, {"type": "move", "uid": mover.uid})
	_check(error.is_empty(), "move: " + error)
	_check(int(g.state.players[enemy].max_hp) == before + 3, "moving to the front springs both counters (#49)")

func _attack_changed() -> void:
	var g := _game()
	var seat := _rich(g)
	var enemy := 1 - seat
	var spec := _base("观察者")
	spec.abilities = [{"trigger": "unit_attack_changed", "event_filter": {"side": "enemy", "direction": "down"}, "effects": [{"op": "gain_hq_defense", "player": "owner", "amount": 1}]}]
	g._new_unit(seat, _compile_with(spec))
	var victim := _veteran_unit(g, enemy, "被削弱者")
	g._checkpoint()
	var before := int(g.state.players[seat].max_hp)
	var source := _compile(_base("削弱"))
	_run_effect(g, {"op": "modify_stats", "target": "chosen", "attack_delta": -1, "health_delta": 0, "duration": "battle"}, g._context(seat, -1, source, victim.uid))
	_check(int(g.state.players[seat].max_hp) == before + 1, "an enemy unit losing attack triggers the listener (#68)")
	_run_effect(g, {"op": "modify_stats", "target": "chosen", "attack_delta": 2, "health_delta": 0, "duration": "battle"}, g._context(seat, -1, source, victim.uid))
	_check(int(g.state.players[seat].max_hp) == before + 1, "a rise does not match a 'down' filter")
	_check(Runtime.rules_text(_compile_with(spec)).contains("敌方单位攻击力下降时"), "the filter shows in the rules text")
	_arm(g, enemy, _counter_with_filter())
	var enemy_before := int(g.state.players[enemy].max_hp)
	_run_effect(g, {"op": "modify_stats", "target": "chosen", "attack_delta": -1, "health_delta": 0, "duration": "battle"}, g._context(seat, -1, source, victim.uid))
	_check(int(g.state.players[enemy].max_hp) == enemy_before + 1, "an attack-change counter fires with its filter")
	var wrong := _counter("错过滤", "enemy_hq_attacked", [{"op": "gain_hq_defense", "player": "owner", "amount": 1}])
	wrong["counter_filter"] = {"side": "own"}
	_compile_with(wrong, false)

func _counter_with_filter() -> Dictionary:
	var counter := _counter("削弱反应", "unit_attack_changed", [{"op": "gain_hq_defense", "player": "owner", "amount": 1}])
	counter["counter_filter"] = {"side": "own", "direction": "down"}
	return counter

func _first_unit_played() -> void:
	var spec := _base("祥纹二室")
	spec.abilities = [{"trigger": "on_play", "premise": {"test": "compare", "left": {"stat": "friendly_units_played_this_game"}, "cmp": "eq", "right": 1}, "effects": [{"op": "gain_hq_defense", "player": "owner", "amount": 1}]}]
	_compile_with(spec)
	var g := _game()
	var seat := _rich(g)
	var before := int(g.state.players[seat].max_hp)
	_play(g, spec)
	_check(int(g.state.players[seat].max_hp) == before + 1, "the first unit of the game gets the bonus (#80)")
	_play(g, spec)
	_check(int(g.state.players[seat].max_hp) == before + 1, "later units do not")

func _compile_rules() -> void:
	var both := _base("两种召唤", "order")
	both.tokens = [_token("a", "甲"), _token("b", "乙")]
	both.abilities = [{"trigger": "on_play", "effects": [{"op": "summon", "token_id": "a", "token_ids": ["a", "b"], "amount": 1, "row": "support"}]}]
	_compile_with(both, false)
	var fight := _base("召唤后交战", "counter")
	fight.appearance.emblem = "counter"
	fight["counter_trigger"] = "enemy_unit_deployed"
	fight.tokens = [_token("f", "突击者", 3, 3)]
	fight.abilities = [{"trigger": "on_reveal", "effects": [{"op": "summon", "token_id": "f", "amount": 1, "row": "support"}, {"op": "fight", "source": "summoned", "target": "random_enemy_unit"}]}]
	_compile_with(fight)
	var cancel := _counter("取消移动", "enemy_unit_moved_to_front", [{"op": "cancel_action"}])
	_compile_with(cancel, false)

func _deck_rules() -> void:
	var registry := {"11111111-1111-4111-8111-111111111111": {"category": "normal"}, "22222222-2222-4222-8222-222222222222": {"category": "small", "test": true}}
	var gold := {"name": "雪绒花开", "kind": "unit", "sin": "wrath", "rarity": "elite", "faction_id": "11111111-1111-4111-8111-111111111111"}
	var plain := {"name": "普通卡", "kind": "unit", "sin": "wrath", "rarity": "standard", "faction_id": "11111111-1111-4111-8111-111111111111"}
	_check(DeckRules.composition([gold], registry, "gloom", "wrath", false).error.contains("金卡"), "a gold card outside its main sin is refused (#81)")
	_check(DeckRules.composition([gold], registry, "wrath", "gloom", false).error.is_empty(), "with its sin as the main sin it is fine")
	_check(DeckRules.composition([plain], registry, "gloom", "wrath", false).error.is_empty(), "other rarities keep the old rule")
	var tester := {"name": "测试卡", "kind": "unit", "sin": "lust", "rarity": "elite", "faction_id": "22222222-2222-4222-8222-222222222222"}
	var result := DeckRules.composition([tester], registry, "gloom", "wrath", false)
	_check(result.error.is_empty() and result.neutral_count == 1, "test-faction cards ignore sin and category limits (#100)")
