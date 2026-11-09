extends "res://tests/test_engine.gd"

func _initialize() -> void:
	_test_counts()
	_test_zero_and_duration()
	_test_sequence()
	print("UNIT COUNTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _counted(stat := "enemy_unit_count", duration := "battle") -> Dictionary:
	var spec := _base("以寡敌众")
	spec.abilities = [{"trigger":"on_play","effects":[{"op":"modify_stats","target":"self","attack_delta":{"stat":stat},"health_delta":0,"duration":duration}]}]
	return spec

func _test_counts() -> void:
	for seat in [0,1]:
		var game := _game()
		game.state.active_player = 1 - seat
		for i in 3:
			var uid := _play(game, _base())
			if i == 0: game._unit(uid).row = "front"
		game.state.active_player = seat
		var source := _play(game, _counted())
		_check(game._unit(source).attack == 6, "Counts both enemy rows, not HQ or hidden zones, from either seat")
		_check(game._unit(source).modifiers[0].attack_delta == 3, "Stores resolved integer in snapshot")
		var printed := Runtime.rules_text(_compile(_counted()))
		_check("敌方在场单位数" in printed and "在场期间" in printed, "Dynamic card text is readable")
		game.state.active_player = 1 - seat
		var extra := _play(game, _base())
		game._leave_battlefield(game._unit(extra), false)
		_check(game._unit(source).attack == 6, "Later deployments/removals do not change the bonus")
		game._leave_battlefield(game.state.units.filter(func(u): return u.owner != seat)[0], false)
		game._leave_battlefield(game._unit(source), true)
		game.state.active_player = seat
		var returned: Dictionary = game.state.players[seat].hand[-1]
		_rich(game)
		_check(game.apply_action(seat, {"type":"play","hand_id":returned.instance_id}).is_empty(), "Returned card redeploys")
		_check(game.state.units[-1].attack == 5, "Redeployment clears old modifier and snapshots new count")
		var snapshot := EngineClass.new()
		snapshot.state = game.state.duplicate(true)
		_check(snapshot.state.units[-1].attack == 5, "Snapshot preserves frozen bonus")

func _test_zero_and_duration() -> void:
	var game := _game()
	var source := _play(game, _counted())
	_check(game._unit(source).attack == 3 and game._unit(source).modifiers.is_empty(), "Empty enemy board is a legal no-op")
	var friendly := _play(game, _counted("friendly_unit_count"))
	_check(game._unit(friendly).attack == 5, "Friendly count includes the deployed source")
	var other := _play(game, _counted("other_friendly_unit_count", "end_of_turn"))
	_check(game._unit(other).attack == 5, "Other-friendly count excludes source")
	game.apply_action(game.state.active_player, {"type":"end_turn"})
	_check(game._unit(other).attack == 3, "Temporary counted modifier expires normally")
	_check(game._unit(friendly).attack == 5, "Permanent counted modifier does not become an aura")
	# Dynamic count must not be truncated to the fixed +5 schema bound.
	game = _game()
	var owner: int = game.state.active_player
	for i in 9:
		var unit: Dictionary = game._new_unit(1 - owner, _compile(_base()))
		unit.row = "front" if i < 5 else "support"
	source = _play(game, _counted())
	_check(game._unit(source).attack == 12, "All nine enemies counted without fixed-value clamping")

func _test_sequence() -> void:
	var game := _game()
	var seat: int = game.state.active_player
	game.state.active_player = 1 - seat
	for i in 3: _play(game, _base())
	game.state.active_player = seat
	var order := _base("战场计数", "order")
	order.abilities = [{"trigger":"on_play","effects":[{"op":"damage","target":"all_enemy_units","amount":{"stat":"enemy_unit_count"}}]}]
	_play(game, order)
	_check(game.state.units.all(func(u): return u.hp == 1), "Multi-target damage shares one pre-effect count")
	order.abilities[0].effects = [{"op":"destroy","target":"random_enemy_unit"},{"op":"damage","target":"enemy_hq","amount":{"stat":"enemy_unit_count"}}]
	_play(game, order)
	_check(game.state.players[1 - seat].hp == 18, "Later effect reads updated living board, excludes destroyed unit")
	var keyword: Dictionary = _read("keywords/standard_heavy_armor.json")
	keyword.id = "custom.unit_count"
	keyword.parameters = {}
	keyword.implementation.abilities = _counted().abilities
	_check(Runtime.validate_keyword(keyword).is_empty(), "No-parameter count keyword validates")
	var spec := _base()
	spec.keywords = [{"id":keyword.id,"version":1,"params":{}}]
	_check(Runtime.compile_card(spec, Runtime.builtin_keywords() + [keyword]).ok, "Count keyword binds and expands")
	for bad in [{"stat":"enemy_hand_count"},{"stat":"enemy_unit_count","code":"x"},{"stat":"enemy_unit_count","multiplier":2},{}]:
		spec = _counted()
		spec.abilities[0].effects[0].attack_delta = bad
		_check(not Runtime.compile_card(spec, []).ok, "Reject unsupported expression")
