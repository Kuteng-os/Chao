extends "res://tests/test_mechanics.gd"

func _initialize() -> void:
	_test_stack_contract()
	_test_stack_combat()
	_test_stack_changes()
	print("STACK TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _armor(n: int, duration: String = "battle", target: String = "chosen", op: String = "modify_stacks") -> Dictionary:
	return {"op":op,"stack":"heavy_armor","target":target,"amount":n,"duration":duration}

func _armored(n: int) -> Dictionary:
	var spec := _base("重甲测试")
	spec.health = 20
	spec.keywords = [{"id":"core.blitz","version":1,"params":{}},{"id":"standard.heavy_armor","version":1,"params":{"x":n}}]
	return spec

func _test_stack_contract() -> void:
	for n in range(1, 11):
		var compiled := _compile(_armored(n))
		_check(compiled.definition.abilities[0].effects[0].amount == n, "numeric keyword expands its layer count")
		_check("重甲" in Runtime.rules_text(compiled), "printed rules explain armor")
	for n in [-1, 0, 11]:
		_check(not Runtime.compile_card(_armored(n), Runtime.builtin_keywords()).ok, "invalid keyword count rejected")
	var definition: Dictionary = _read("keywords/standard_heavy_armor.json")
	definition.id = "custom.armor_test"
	definition.parameters.x.minimum = -1
	_check(not Runtime.validate_keyword(definition).is_empty(), "parameter range crossing zero rejected")
	definition.implementation.abilities[0].effects[0].op = "set_stacks"
	definition.parameters.x.minimum = 0
	_check(Runtime.validate_keyword(definition).is_empty(), "zero legal for set/clear")

func _test_stack_combat() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var attacker := _play(game, _armored(1))
	game._unit(attacker).row = "front"
	game.state.active_player = 1 - owner
	var defender := _play(game, _armored(2))
	game.state.active_player = owner
	_rich(game)
	_check(game.apply_action(owner, {"type":"attack","uid":attacker,"target_uid":defender}).is_empty(), "attack on armored unit legal")
	_check(game._unit(defender).hp == 19, "armor 2 reduces 3 attack to 1")
	_check(game._unit(attacker).hp == 18, "armor 1 reduces retaliation to 2")
	_check(game.stack_count(game._unit(defender), "heavy_armor") == 2, "armor is not consumed")
	var spell := _base("穿过重甲的指令", "order")
	spell.play_target = {"side":"enemy","row":"any"}
	spell.abilities = [{"trigger":"on_play","effects":[{"op":"damage","target":"chosen","amount":3}]}]
	_play(game, spell, defender)
	_check(game._unit(defender).hp == 16, "order damage ignores armor")
	game._unit(attacker).attacks_used = 0
	game._unit(attacker).combat_damage_rules = [{"against":"tank","applies_to":"attack","multiplier":2,"expires_turn":-1}]
	_check(game.apply_action(owner, {"type":"attack","uid":attacker,"target_uid":defender}).is_empty(), "multiplied combat resolves")
	_check(game._unit(defender).hp == 12, "multiply 3 by 2 before subtracting armor 2")
	_check(game.state.telemetry.any(func(e: Dictionary) -> bool: return e.kind == "armor_blocked" and e.amount == 2), "blocked damage recorded")
	var enemy_view: Dictionary = game.view_for(1 - owner)
	_check(enemy_view.units[0].stacks.heavy_armor == 1, "public view contains current layers")

func _test_stack_changes() -> void:
	var game := _game()
	var uid := _play(game, _armored(2))
	_buff(game, uid, _armor(2))
	_check(game.stack_count(game._unit(uid),"heavy_armor") == 4, "gains add")
	_buff(game, uid, _armor(-1))
	_check(game.stack_count(game._unit(uid),"heavy_armor") == 3, "loss subtracts")
	_buff(game, uid, _armor(0,"end_of_turn","chosen","set_stacks"))
	_check(game.stack_count(game._unit(uid),"heavy_armor") == 0, "temporary clear")
	_round(game)
	_check(game.stack_count(game._unit(uid),"heavy_armor") == 3, "expiry restores permanent layers")
	_buff(game, uid, _armor(10))
	_check(game.stack_count(game._unit(uid),"heavy_armor") == 10, "gain clamps at ten")
	_buff(game, uid, _armor(-10))
	_buff(game, uid, _armor(-10))
	_buff(game, uid, _armor(1))
	_check(game.stack_count(game._unit(uid),"heavy_armor") == 1, "loss at zero does not accrue debt")
	_buff(game, uid, _armor(10,"battle","chosen","set_stacks"))
	game._unit(uid).attack = 3
	_check(game._combat_damage(game._unit(uid),game._unit(uid),"attack") == 0, "damage cannot become healing")
	var replay := EngineClass.new()
	replay.state = game.state.duplicate(true)
	_check(replay.stack_count(replay._unit(uid),"heavy_armor") == 10, "snapshot restores layer state")
