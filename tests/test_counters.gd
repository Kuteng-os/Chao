extends "res://tests/test_engine.gd"

func _initialize() -> void:
	_test_contract()
	_test_order()
	_test_deployment_counter()
	_test_order_counter()
	_test_hq_counter()
	_test_limit_and_privacy()
	print("COUNTER TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func counter(trigger: String, effects: Array) -> Dictionary:
	var c := _base("隐蔽伏击", "counter")
	c.appearance.emblem = "counter"
	c["counter_trigger"] = trigger
	c.abilities = [{"trigger":"on_reveal", "effects":effects}]
	return c

func next_player(game: RefCounted) -> int:
	_check(game.apply_action(game.state.active_player, {"type":"end_turn"}).is_empty(), "end turn")
	return _rich(game)

func _test_contract() -> void:
	var c := counter("enemy_unit_deployed", [{"op":"damage", "target":"trigger_unit", "amount":2}])
	_check(Runtime.compile_card(c, []).ok, "deploy counter compiles")
	c["counter_trigger"] = "enemy_order_played"
	_check(not Runtime.compile_card(c, []).ok, "order has no triggering unit")
	c.abilities[0].effects = [{"op":"cancel_action"}]
	_check(Runtime.compile_card(c, []).ok, "cancel order compiles")
	c["counter_trigger"] = "enemy_unit_deployed"
	_check(not Runtime.compile_card(c, []).ok, "cannot cancel a resolved deployment")
	c["counter_trigger"] = "enemy_hq_attacked"
	c.abilities[0].effects = [{"op":"heal", "target":"self", "amount":2}]
	_check(not Runtime.compile_card(c, []).ok, "counter has no self unit")
	c.abilities = []
	_check(not Runtime.compile_card(c, []).ok, "empty counter rejected")
	c = _base("错误指令", "order")
	c.abilities = [{"trigger":"on_reveal", "effects":[{"op":"draw", "player":"owner", "amount":1}]}]
	_check(not Runtime.compile_card(c, []).ok, "on reveal cannot be ordinary order")

func _test_order() -> void:
	var game := _game()
	var owner := _rich(game)
	var before: int = game.state.players[owner].hand.size()
	var c := _base("补给指令", "order")
	c.abilities = [{"trigger":"on_play", "effects":[{"op":"draw", "player":"owner", "amount":2}]}]
	_play(game, c)
	_check(game.state.players[owner].hand.size() == before + 2, "order draws two")
	_check(game.state.units.is_empty() and game.state.discard.size() == 1, "order resolves then discards")

func _test_deployment_counter() -> void:
	var game := _game()
	var owner := _rich(game)
	_play(game, counter("enemy_unit_deployed", [{"op":"destroy", "target":"trigger_unit"}]))
	var opponent := next_player(game)
	var before: int = game.state.players[opponent].hand.size()
	var unit := _base("登场补给单位")
	unit.abilities = [{"trigger":"on_play", "effects":[{"op":"draw", "player":"owner", "amount":1}]}]
	var uid := _play(game, unit)
	_check(game._unit(uid).is_empty(), "deploying unit destroyed")
	_check(game.state.players[opponent].hand.size() == before + 1, "deployment effect resolves before counter")
	_check(game.state.players[owner].counters.is_empty(), "counter consumed")
	var second := _play(game, _base("第二单位"))
	_check(not game._unit(second).is_empty(), "counter fires only once")

func _test_order_counter() -> void:
	var game := _game()
	var owner := _rich(game)
	_play(game, counter("enemy_order_played", [{"op":"cancel_action"}, {"op":"draw", "player":"owner", "amount":1}]))
	_play(game, counter("enemy_order_played", [{"op":"cancel_action"}]))
	var opponent := next_player(game)
	var before: int = game.state.players[owner].hand.size()
	var order := _base("致命打击", "order")
	order.abilities = [{"trigger":"on_play", "effects":[{"op":"damage", "target":"enemy_hq", "amount":10}]}]
	_play(game, order)
	_check(game.state.players[owner].hp == 20, "order cancelled before damage")
	_check(game.state.players[opponent].credits == 11, "cancelled order still pays")
	_check(game.state.players[owner].hand.size() == before + 1, "remaining effects of revealed counter resolve")
	_check(game.state.players[owner].counters.size() == 1, "later counter remains after action cancelled")
	_check(game.view_for(opponent).players[owner].counter_count == 0, "opponent cannot see remaining count")

func _test_hq_counter() -> void:
	for effect in [{"op":"cancel_action"}, {"op":"destroy", "target":"trigger_unit"}]:
		var game := _game()
		var owner := _rich(game)
		_play(game, counter("enemy_hq_attacked", [effect]))
		var opponent := next_player(game)
		var unit := _base("突击炮兵")
		unit.unit_class = "artillery"
		unit.keywords = [{"id":"core.blitz", "version":1, "params":{}}]
		var uid := _play(game, unit)
		_check(game.state.players[owner].counters.size() == 1, "different event does not reveal counter")
		_check(game.apply_action(opponent, {"type":"attack", "uid":uid, "target_uid":-1}).is_empty(), "HQ attack accepted")
		_check(game.state.players[owner].hp == 20, "HQ takes no damage after cancel or attacker destruction")
		_check(game.state.players[opponent].credits == 10, "attack operation cost consumed")
		if effect.op == "cancel_action": _check(game._unit(uid).attacks_used == 1, "cancelled attack consumes attack use")

func _test_limit_and_privacy() -> void:
	var game := _game()
	var owner := _rich(game)
	var c := counter("enemy_hq_attacked", [{"op":"cancel_action"}])
	for i in 3: _play(game, c)
	game.state.players[owner].hand.clear()
	var view: Dictionary = game.view_for(1 - owner)
	_check(view.players[owner].counters.is_empty() and view.players[owner].counter_count == 0, "hidden counter count and bodies redacted")
	_check(not JSON.stringify(view).contains(c.name), "counter name absent from opponent view and log")
	_check(game.view_for(owner).players[owner].counters.size() == 3, "owner can inspect all counters")
	game.state.players[owner].hand.append({"instance_id":"fourth", "card":_compile(c)})
	var snapshot := Runtime.canonical(game.state)
	_check(not game.apply_action(owner, {"type":"play", "hand_id":"fourth"}).is_empty(), "fourth counter rejected")
	_check(Runtime.canonical(game.state) == snapshot, "rejected set preserves hand and credits")
	# Same state/action produces identical result, including counter discard and hidden views.
	var copy := EngineClass.new()
	copy.state = game.state.duplicate(true)
	game.apply_action(owner, {"type":"end_turn"})
	copy.apply_action(owner, {"type":"end_turn"})
	_check(Runtime.canonical(game.state) == Runtime.canonical(copy.state), "counter state deterministic replay")
