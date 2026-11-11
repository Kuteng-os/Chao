extends "res://tests/test_engine.gd"
## Run: godot --headless --path . --script tests/test_mechanics0911.gd
## Covers issues #26, #27, #28, #29, #30, #31, #37 and #38.

func _initialize() -> void:
	_remove_keyword()
	_aura_reads_stacks()
	_hand_keyword_filter()
	_per_stack_operation_cost()
	_pin_five_turns()
	_forbid_deploy()
	_immediate_return()
	_keyword_param()
	print("MECHANICS 0911: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _registry() -> Array:
	var keywords: Array = Runtime.builtin_keywords()
	keywords.append(JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/registered/standard_charge.json")))
	return keywords

func _compile_with(card: Dictionary, expect_ok := true) -> Dictionary:
	var result := Runtime.compile_card(card, _registry())
	_check(result.ok == expect_ok, ("fixture compiles: " if expect_ok else "fixture is rejected: ") + result.get("error", ""))
	return result

func _run_effect(g: RefCounted, effect: Dictionary, context: Dictionary) -> void:
	g._reset_budget()
	g._effect(effect, context)
	g._checkpoint()
	g._drain_deaths()

func _remove_keyword() -> void:
	var g := _game()
	var seat := _rich(g)
	var spec := _base("烟幕单位")
	spec.keywords = [{"id":"core.smokescreen","version":1,"params":{}}]
	var unit: Dictionary = g._new_unit(seat, _compile(spec))
	_check(g._has_keyword(unit, "core.smokescreen"), "starts with smokescreen")
	_run_effect(g, {"op":"remove_keyword","target":"self","keyword_id":"core.smokescreen"}, g._context(seat, unit.uid, unit.card))
	_check(not g._has_keyword(g._unit(unit.uid), "core.smokescreen"), "the printed keyword is lost")
	_check(not g._unit(unit.uid).get("consumed_keyword_history", {}).has("core.smokescreen"), "removal is not recorded as using the keyword")
	_run_effect(g, {"op":"grant_keyword","target":"self","keyword_id":"core.smokescreen","keyword_version":1,"duration":"battle"}, g._context(seat, unit.uid, g._unit(unit.uid).card))
	_check(g._has_keyword(g._unit(unit.uid), "core.smokescreen"), "a later grant brings it back")

func _aura_reads_stacks() -> void:
	var g := _game()
	var seat := _rich(g)
	var spec := _base("清扫员工")
	spec.attack = 3
	spec.abilities = [{"trigger":"while_active","effects":[{"op":"modify_stats","target":"self","attack_delta":{"stack_count":{"target":"self","stack":"充能"}},"health_delta":0,"duration":"battle"}]}]
	var unit: Dictionary = g._new_unit(seat, _compile_with(spec))
	var context: Dictionary = g._context(seat, unit.uid, unit.card)
	_check(int(g._unit(unit.uid).attack) == 3, "no charge, no bonus")
	_run_effect(g, {"op":"modify_stacks","target":"self","stack":"充能","amount":2,"duration":"battle"}, context)
	_check(int(g._unit(unit.uid).attack) == 5, "each charge adds one attack")
	_run_effect(g, {"op":"set_stacks","target":"self","stack":"充能","amount":0,"duration":"battle"}, context)
	_check(int(g._unit(unit.uid).attack) == 3, "spending the charge removes the bonus")
	var bad := _base("坏光环")
	bad.abilities = [{"trigger":"while_active","effects":[{"op":"modify_stats","target":"self","attack_delta":{"unit_stat":{"target":"self","stat":"health"}},"health_delta":0,"duration":"battle"}]}]
	_compile_with(bad, false)

func _hand_keyword_filter() -> void:
	var g := _game()
	var seat := _rich(g)
	var fast := _base("有闪击")
	fast.cost = 3
	fast.keywords = [{"id":"core.blitz","version":2,"params":{}}]
	var slow := _base("没闪击")
	slow.cost = 3
	var hand: Array = g.state.players[seat].hand
	hand.append({"instance_id":"fast","card":_compile(fast)})
	hand.append({"instance_id":"slow","card":_compile(slow)})
	_run_effect(g, {"op":"modify_hand_cost","selection":"all","cost_delta":-1,"duration":"hand","filter":{"keyword_id":"core.blitz"}}, g._context(seat, -1, _compile(_base("来源"))))
	_check(g.play_cost(seat, g._hand(seat, "fast").card) == 2, "the card with the keyword is cheaper")
	_check(g.play_cost(seat, g._hand(seat, "slow").card) == 3, "the card without it is unchanged")
	_run_effect(g, {"op":"modify_hand_cost","selection":"all","cost_delta":-1,"duration":"hand","filter":{"without_keyword":"core.blitz"}}, g._context(seat, -1, _compile(_base("来源"))))
	_check(g.play_cost(seat, g._hand(seat, "slow").card) == 2 and g.play_cost(seat, g._hand(seat, "fast").card) == 2, "without_keyword picks the other card")

func _per_stack_operation_cost() -> void:
	var g := _game()
	var seat := _rich(g)
	var spec := _base("血腥小组")
	spec.operation_cost = 4
	var source: Dictionary = g._new_unit(seat, _compile(spec))
	var donor: Dictionary = g._new_unit(seat, _compile(_base("充能单位")))
	var context: Dictionary = g._context(seat, source.uid, source.card, donor.uid)
	_run_effect(g, {"op":"modify_stacks","target":"chosen","stack":"充能","amount":3,"duration":"battle"}, context)
	_run_effect(g, {"op":"modify_operation_cost","target":"self","cost_delta":-1,"per_stack":{"target":"chosen","stack":"充能"},"duration":"battle"}, context)
	_run_effect(g, {"op":"set_stacks","target":"chosen","stack":"充能","amount":0,"duration":"battle"}, context)
	_check(int(g._operation_cost(g._unit(source.uid))) == 1, "three charges lower the operation cost by three")
	_check(g.stack_count(g._unit(donor.uid), "充能") == 0, "the charge is spent")
	var empty: Dictionary = g._new_unit(seat, _compile(spec))
	_run_effect(g, {"op":"modify_operation_cost","target":"self","cost_delta":-1,"per_stack":{"target":"chosen","stack":"充能"},"duration":"battle"}, g._context(seat, empty.uid, empty.card, donor.uid))
	_check(int(g._operation_cost(g._unit(empty.uid))) == 4, "no charge changes nothing")

func _pin_five_turns() -> void:
	var order := _base("一眼万年", "order")
	order.play_target = {"side":"any","row":"any"}
	order.abilities = [{"trigger":"on_play","effects":[{"op":"pin","target":"chosen","turns":5}]}]
	_compile_with(order)
	order.abilities[0].effects[0].turns = 6
	_compile_with(order, false)

func _forbid_deploy() -> void:
	var g := _game()
	var seat := _rich(g)
	_run_effect(g, {"op":"forbid_deploy","player":"opponent"}, g._context(seat, -1, _compile(_base("势阱"))))
	var opponent: int = 1-seat
	_check(not g.deploy_banned(opponent), "the ban waits for the opponent's turn")
	_check(g.apply_action(seat, {"type":"end_turn"}).is_empty(), "end the caster's turn")
	g.state.players[opponent].credits = 12
	g.state.players[opponent].hand.append({"instance_id":"unit","card":_compile(_base("被禁部署"))})
	var order := _base("仍可打出", "order")
	order.abilities = [{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]
	g.state.players[opponent].hand.append({"instance_id":"order","card":_compile(order)})
	_check(g.legal_targets(opponent, {"type":"play","hand_id":"unit"}).is_empty(), "unit cards cannot be deployed")
	_check(not g.legal_targets(opponent, {"type":"play","hand_id":"order"}).is_empty(), "orders can still be played")
	_check(g.apply_action(opponent, {"type":"end_turn"}).is_empty() and g.apply_action(seat, {"type":"end_turn"}).is_empty(), "two more turns pass")
	_check(not g.legal_targets(opponent, {"type":"play","hand_id":"unit"}).is_empty(), "the ban lasts one turn")

func _immediate_return() -> void:
	var g := _game()
	var seat := _rich(g)
	var spec := _base("小推车乘客")
	spec.abilities = [{"trigger":"on_leave","effects":[{"op":"draw","player":"owner","amount":1}]}]
	var unit: Dictionary = g._new_unit(seat, _compile(spec))
	var row: String = unit.row
	var hand_before: int = g.state.players[seat].hand.size()
	_run_effect(g, {"op":"temporarily_remove","target":"chosen","return_when":"immediate","destination":"original_position"}, g._context(seat, -1, _compile(_base("W小推车")), unit.uid))
	var back: Dictionary = g._unit(unit.uid)
	_check(not back.is_empty() and back.row == row, "the unit is back where it was")
	_check(g.state.get("suspended", []).is_empty(), "nothing stays suspended")
	_check(g.state.players[seat].hand.size() == hand_before + 1, "leaving still fires on_leave")

func _keyword_param() -> void:
	var g := _game()
	var seat := _rich(g)
	var charged := _base("充能三")
	charged.keywords = [{"id":"standard.charge","version":1,"params":{"n":3}}]
	var unit: Dictionary = g._new_unit(seat, _compile_with(charged))
	var plain: Dictionary = g._new_unit(seat, _compile(_base("没有充能")))
	var fill := {"op":"set_stacks","target":"chosen","stack":"充能","amount":{"keyword_param":{"target":"chosen","keyword_id":"standard.charge","param":"n"}},"duration":"battle"}
	_run_effect(g, fill, g._context(seat, -1, _compile(_base("来源")), unit.uid))
	_check(g.stack_count(g._unit(unit.uid), "充能") == 3, "charge fills to its cap")
	_run_effect(g, fill, g._context(seat, -1, _compile(_base("来源")), plain.uid))
	_check(g.stack_count(g._unit(plain.uid), "充能") == 0, "a unit without the keyword reads zero")
	_check(g._effect_value({"keyword_param":{"target":"chosen","keyword_id":"standard.charge","param":"n"}}, g._context(seat, -1, _compile(_base("来源")), unit.uid)) == 3, "the value is readable anywhere")
