extends "res://tests/test_engine.gd"
## Run: godot --headless --path . --script tests/test_mechanics0910.gd
## Covers the mechanics requested in issues #3, #6, #10, #12 and #15.

func _initialize() -> void:
	_revive()
	_charge()
	_max_unit_stat()
	_shuffle_into_deck()
	_play_tax()
	print("MECHANICS 0910: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _registry() -> Array:
	var keywords: Array = Runtime.builtin_keywords()
	keywords.append(JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/registered/standard_charge.json")))
	return keywords

func _compile_with(card: Dictionary) -> Dictionary:
	var result := Runtime.compile_card(card, _registry())
	_check(result.ok, "fixture compiles: " + result.get("error", ""))
	return result

func _settle(g: RefCounted) -> void:
	g._checkpoint()
	g._drain_deaths()

func _revive() -> void:
	var g := _game()
	var seat := _rich(g)
	var spec := _base("复生单位")
	spec.health = 6
	spec.keywords = [{"id":"core.revive","version":1,"params":{"n":2}}]
	var compiled := _compile_with(spec)
	_check(Runtime.short_rules_text(compiled.definition).contains("复生 2") or Runtime.keyword_labels(compiled.definition).has("复生 2"), "card shows 复生 2")
	var unit: Dictionary = g._new_unit(seat, compiled)
	var hit := func(target: Dictionary, amount: int): g._reset_budget(); g._effect({"op":"damage","target":"chosen","amount":amount}, g._context(1-seat, -1, _compile(_base()), target.uid)); _settle(g)
	hit.call(unit, 10)
	_check(not g._unit(unit.uid).is_empty() and int(g._unit(unit.uid).hp) == 2, "lethal damage leaves exactly n health")
	hit.call(g._unit(unit.uid), 1)
	_check(int(g._unit(unit.uid).hp) == 1, "ordinary damage still applies afterwards")
	hit.call(g._unit(unit.uid), 5)
	_check(g._unit(unit.uid).is_empty(), "a second lethal hit in the same stay kills")

	var destroyed: Dictionary = g._new_unit(seat, compiled)
	g._reset_budget(); g._effect({"op":"destroy","target":"chosen"}, g._context(1-seat, -1, _compile(_base()), destroyed.uid)); _settle(g)
	_check(g._unit(destroyed.uid).is_empty(), "destroy is not damage and is not prevented")

	var suppressed: Dictionary = g._new_unit(seat, compiled)
	g._suppress(suppressed)
	hit.call(suppressed, 10)
	_check(g._unit(suppressed.uid).is_empty(), "a suppressed unit cannot revive")

	var big := _base("高复生")
	big.health = 3
	big.keywords = [{"id":"core.revive","version":1,"params":{"n":9}}]
	var capped: Dictionary = g._new_unit(seat, _compile_with(big))
	hit.call(capped, 5)
	_check(int(g._unit(capped.uid).hp) == 3, "revive never exceeds the health cap")

	var returning: Dictionary = g._new_unit(seat, compiled)
	hit.call(returning, 10)
	g._leave_battlefield(g._unit(returning.uid), true)
	var again: Dictionary = g._new_unit(seat, g.state.players[seat].hand.back().card)
	hit.call(again, 10)
	_check(int(g._unit(again.uid).hp) == 2, "returning to hand starts a new stay")

func _charge() -> void:
	var g := _game()
	var seat := _rich(g)
	var spec := _base("充能单位")
	spec.keywords = [{"id":"standard.charge","version":1,"params":{"n":2}}]
	var unit: Dictionary = g._new_unit(seat, _compile_with(spec))
	_check(g.stack_count(unit, "充能") == 0, "no charge on entry")
	var counts := []
	for i in 3:
		g._reset_budget()
		g._run_roots(g._abilities(g._context(seat, unit.uid, unit.card), "own_turn_start"))
		g._drain_deaths()
		counts.append(g.stack_count(g._unit(unit.uid), "充能"))
	_check(counts == [1, 2, 2], "charge rises once per turn and stops at n: " + str(counts))
	g._reset_budget()
	g._effect({"op":"modify_stacks","target":"self","stack":"充能","amount":-2,"duration":"battle"}, g._context(seat, unit.uid, unit.card))
	g._run_roots(g._abilities(g._context(seat, unit.uid, unit.card), "own_turn_start"))
	g._drain_deaths()
	_check(g.stack_count(g._unit(unit.uid), "充能") == 1, "spent charge refills from its new value")

func _max_unit_stat() -> void:
	var g := _game()
	var seat := _rich(g)
	for stats in [[2, 7], [6, 3]]:
		var spec := _base()
		spec.attack = stats[0]
		spec.health = stats[1]
		g._new_unit(seat, _compile(spec))
	var target_spec := _base("靶子")
	target_spec.health = 20
	var enemy: Dictionary = g._new_unit(1-seat, _compile(target_spec))
	var context: Dictionary = g._context(seat, -1, _compile(_base("来源")), enemy.uid)
	_check(g._effect_value({"max_unit_stat":{"side":"ally","stat":"health"}}, context) == 7, "highest friendly health")
	_check(g._effect_value({"max_unit_stat":{"side":"ally","stat":"attack"}}, context) == 6, "highest friendly attack")
	_check(g._premise_value({"max_unit_stat":{"side":"enemy","stat":"health"}}, context) == 20, "premises read the enemy side")
	g._reset_budget(); g._effect({"op":"damage","target":"chosen","amount":{"max_unit_stat":{"side":"ally","stat":"health"}}}, context); _settle(g)
	_check(int(g._unit(enemy.uid).hp) == 13, "damage uses the highest friendly health")
	var empty := _game()
	_check(empty._effect_value({"max_unit_stat":{"side":"ally","stat":"health"}}, {"owner":0}) == 0, "no units reads zero")

	var order := _base("上门寻访", "order")
	order.play_target = {"side":"enemy","row":"any"}
	order.abilities = [{"trigger":"on_play","effects":[{"op":"damage","target":"chosen","amount":{"max_unit_stat":{"side":"ally","stat":"health"}}}]}]
	var compiled := _compile_with(order)
	_check(compiled.ok and Runtime.rules_text(compiled.definition).contains("友方单位中最高的防御力"), "rules text names the source")

func _shuffle_into_deck() -> void:
	var g := _game()
	var seat := _rich(g)
	var victim_spec := _base("被洗入的单位")
	victim_spec.abilities = [{"trigger":"on_death","effects":[{"op":"draw","player":"owner","amount":1}]}]
	var victim: Dictionary = g._new_unit(1-seat, _compile(victim_spec))
	var my_deck: int = g.state.players[seat].deck.size()
	var their_deck: int = g.state.players[1-seat].deck.size()
	var their_hand: int = g.state.players[1-seat].hand.size()
	g._reset_budget(); g._effect({"op":"shuffle_into_deck","target":"chosen"}, g._context(seat, -1, _compile(_base("来源")), victim.uid)); _settle(g)
	_check(g._unit(victim.uid).is_empty(), "the unit leaves the battlefield")
	_check(g.state.players[seat].deck.size() == my_deck + 1 and g.state.players[1-seat].deck.size() == their_deck, "it joins the caster's deck by default")
	_check(g.state.players[seat].deck.any(func(card): return card.definition.name == "被洗入的单位"), "the card itself is in the caster's deck")
	_check(g.state.players[1-seat].hand.size() == their_hand, "leaving this way does not trigger death effects")

	var owned: Dictionary = g._new_unit(1-seat, _compile(_base("回到原主")))
	var before: int = g.state.players[1-seat].deck.size()
	g._reset_budget(); g._effect({"op":"shuffle_into_deck","target":"chosen","deck":"owner","position":"top"}, g._context(seat, -1, _compile(_base("来源")), owned.uid)); _settle(g)
	_check(g.state.players[1-seat].deck.size() == before + 1 and g.state.players[1-seat].deck.back().definition.name == "回到原主", "owner deck and top position are honoured")

	var order := _base("GOLDEN TIMING", "order")
	order.cost = 7
	order.play_target = {"side":"enemy","row":"any"}
	order.abilities = [{"trigger":"on_play","effects":[{"op":"shuffle_into_deck","target":"chosen"}]}]
	var compiled := _compile_with(order)
	_check(compiled.ok and Runtime.rules_text(compiled.definition).contains("洗入己方牌库"), "rules text describes the move")

func _play_tax() -> void:
	var g := _game()
	var seat := _rich(g)
	var order := _base("时间征收", "order")
	order.cost = 4
	order.abilities = [{"trigger":"on_play","effects":[{"op":"tax_opponent_plays","card_kind":"unit","amount":2,"refund_per":2}]}]
	var compiled := _compile_with(order)
	_check(compiled.ok and Runtime.rules_text(compiled.definition).contains("费用+2"), "rules text describes the tax")
	var id := "tax-order"
	g.state.players[seat].hand.append({"instance_id": id, "card": compiled})
	_check(g.apply_action(seat, {"type":"play","hand_id":id,"target_uid":-1}).is_empty(), "play the tax order")
	var unit_card := _compile(_base("被征收单位"))
	var plain_order := _base("不受影响的指令", "order")
	plain_order.abilities = [{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]
	var order_card := _compile(plain_order)
	_check(g.play_cost(1-seat, unit_card) == int(unit_card.definition.cost), "the tax waits for the opponent's turn")
	_check(g.apply_action(seat, {"type":"end_turn"}).is_empty(), "end the caster's turn")
	var opponent: int = 1-seat
	_check(int(g.state.active_player) == opponent, "opponent's turn")
	_check(g.play_cost(opponent, unit_card) == int(unit_card.definition.cost) + 2, "unit cards cost 2 more")
	_check(g.play_cost(opponent, order_card) == int(order_card.definition.cost), "other kinds are not taxed")
	g.state.players[opponent].max_credits = 12
	g.state.players[opponent].credits = 12
	for i in 2:
		var hand_id := "taxed-%d" % i
		g.state.players[opponent].hand.append({"instance_id": hand_id, "card": unit_card})
		_check(g.apply_action(opponent, {"type":"play","hand_id":hand_id,"target_uid":-1}).is_empty(), "opponent pays the tax")
	_check(int(g.state.players[opponent].credits) == 12 - 2 * (int(unit_card.definition.cost) + 2), "the extra cost was paid")
	g.state.players[opponent].credits = 0
	g.state.players[opponent].hand.append({"instance_id": "broke", "card": unit_card})
	_check(not g.apply_action(opponent, {"type":"play","hand_id":"broke","target_uid":-1}).is_empty(), "a player who cannot pay the tax cannot play")
	_check(g.apply_action(opponent, {"type":"end_turn"}).is_empty(), "end the opponent's turn")
	_check(int(g.state.active_player) == seat, "back to the caster")
	_check(int(g.state.players[seat].credits) == int(g.state.players[seat].max_credits) + 2, "four extra paid refunds two command points above the cap")
	_check(g.play_cost(opponent, unit_card) == int(unit_card.definition.cost), "the tax is gone afterwards")
	_check(g.state.players.all(func(p): return p.get("play_taxes", []).is_empty()), "settled taxes are dropped")
