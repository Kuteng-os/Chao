extends "res://tests/test_engine.gd"
## Real rules actions, including expiry, retaliation and invalid-action rollback.

func _initialize() -> void:
	_test_keyword_contract()
	_test_multiple_attacks()
	_test_limit_changes()
	_test_readiness_and_retaliation()
	_test_cost_layers()
	_test_destroy()
	_test_shared_layer_budget()
	_test_combat_multipliers()
	print("MECHANICS TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _limit(n: int = 2, duration: String = "battle", target: String = "self") -> Dictionary:
	return {"op":"set_attack_limit", "target":target, "attacks":n, "duration":duration}

func _fighter(blitz: bool = true) -> Dictionary:
	var spec := _base("多次攻击测试")
	spec.unit_class = "artillery"
	if blitz: spec.keywords = [{"id":"core.blitz", "version":1, "params":{}}]
	spec.abilities = [{"trigger":"on_play", "effects":[_limit()]}]
	return spec

func _attack_hq(game: RefCounted, uid: int) -> String:
	return game.apply_action(game.state.active_player, {"type":"attack", "uid":uid, "target_uid":-1})

func _buff(game: RefCounted, uid: int, effect: Dictionary) -> void:
	var spec := _base("改变单位规则", "order")
	spec.play_target = {"side":"ally", "row":"any"}
	spec.abilities = [{"trigger":"on_play", "effects":[effect]}]
	_play(game, spec, uid)

func _round(game: RefCounted) -> void:
	_check(game.apply_action(game.state.active_player, {"type":"end_turn"}).is_empty(), "end own turn")
	_check(game.apply_action(game.state.active_player, {"type":"end_turn"}).is_empty(), "start next own turn")

func _test_keyword_contract() -> void:
	var keyword: Dictionary = _read("keywords/example_fight.json")
	_check(Runtime.validate_keyword(keyword).is_empty(), "fight can register as a template")
	var registry := Runtime.builtin_keywords()
	registry.append(keyword)
	var spec := _base()
	spec.keywords = [{"id":keyword.id, "version":1, "params":{}}]
	var compiled := Runtime.compile_card(spec, registry)
	_check(compiled.ok and compiled.definition.abilities[0].effects[0] == _limit(), "keyword expands exact permanent cap once")
	_check("攻击2次" in Runtime.rules_text(compiled), "preview explains attack limit")
	keyword.parameters = {"n":{"type":"integer", "minimum":1, "maximum":4}}
	keyword.implementation.abilities[0].effects[0].attacks = {"param":"n"}
	_check(Runtime.validate_keyword(keyword).is_empty(), "parameter supports all one through four limits")
	keyword.parameters.n.maximum = 5
	_check(not Runtime.validate_keyword(keyword).is_empty(), "parameter range above four rejected")
	keyword.parameters.n.maximum = 4
	keyword.parameters.n.minimum = 0
	_check(not Runtime.validate_keyword(keyword).is_empty(), "parameter range below one rejected")
	for n in [0, 5]:
		spec = _fighter()
		spec.abilities[0].effects[0].attacks = n
		_check(not Runtime.compile_card(spec, Runtime.builtin_keywords()).ok, "invalid literal cap rejected")

func _test_multiple_attacks() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var uid := _play(game, _fighter())
	var credits: int = game.state.players[owner].credits
	_check(_attack_hq(game, uid).is_empty(), "first attack accepted")
	_check(not game._unit(uid).attacked and game._unit(uid).attacks_used == 1, "first attack leaves one use")
	game.state.players[owner].hand.clear()
	_check(game.ai_action(owner).type == "attack", "AI uses remaining attack")
	var view: Dictionary = game.view_for(owner)
	var client := EngineClass.new()
	client.state = view
	_check(-1 in client.legal_targets(owner, {"type":"attack", "uid":uid}), "private network view preserves legal second attack")
	_check(_attack_hq(game, uid).is_empty(), "second attack accepted")
	_check(game.state.players[owner].credits == credits - 2 and game.state.players[1-owner].hp == 14, "both attacks pay and resolve once")
	_check(game._unit(uid).attacked and game._unit(uid).attacks_used == 2, "two attacks exhaust unit")
	var before := Runtime.sha(game.state)
	_check(not _attack_hq(game, uid).is_empty() and Runtime.sha(game.state) == before, "third attack rejected without any mutation")
	_round(game)
	_check(game._unit(uid).attacks_used == 0 and game.attack_limit(game._unit(uid)) == 2, "turn reset retains persistent limit")
	_check(_attack_hq(game, uid).is_empty(), "can attack on next own turn")
	game.state.players[owner].credits = 0
	before = Runtime.sha(game.state)
	_check(not _attack_hq(game, uid).is_empty() and Runtime.sha(game.state) == before, "remaining attack requires credits")
	# A legacy one-attack snapshot must still show an exhausted unit as unavailable.
	client.state = game.view_for(owner)
	client.state.players[owner].credits = 12
	var legacy: Dictionary = client._unit(uid)
	legacy.erase("attacks_used")
	legacy.erase("attack_limits")
	legacy.attacked = true
	_check(client.legal_targets(owner, {"type":"attack", "uid":uid}).is_empty(), "legacy exhausted flag remains authoritative in old snapshots")

func _test_limit_changes() -> void:
	var game := _game()
	var spec := _fighter()
	spec.abilities = []
	var uid := _play(game, spec)
	_check(_attack_hq(game, uid).is_empty() and game._unit(uid).attacked, "ordinary unit still attacks once")
	_buff(game, uid, _limit(2, "battle", "chosen"))
	_check(game._unit(uid).attacks_used == 1 and not game._unit(uid).attacked, "increasing cap preserves consumed attacks")
	_buff(game, uid, _limit(2, "battle", "chosen"))
	_check(game.attack_limit(game._unit(uid)) == 2, "reapplication is a cap, not additive")
	_check(_attack_hq(game, uid).is_empty(), "one attack remains after cap increase")
	_buff(game, uid, _limit(1, "end_of_turn", "chosen"))
	_check(game._unit(uid).attacked, "temporary lower cap immediately restricts attacks")
	_buff(game, uid, _limit(3, "end_of_turn", "chosen"))
	_check(game.attack_limit(game._unit(uid)) == 3 and game._unit(uid).attacks_used == 2, "newest active cap wins without refresh")
	_check(_attack_hq(game, uid).is_empty(), "latest cap allows exactly one remaining use")
	_check(game.apply_action(game.state.active_player, {"type":"end_turn"}).is_empty(), "expire temporary limits")
	_check(game.attack_limit(game._unit(uid)) == 2 and game._unit(uid).attacks_used == 3, "expiry restores permanent cap without refund")
	game.apply_action(game.state.active_player, {"type":"end_turn"})
	_check(game._unit(uid).attacks_used == 0, "only own turn refreshes attacks")

func _test_readiness_and_retaliation() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var uid := _play(game, _fighter(false))
	_check(game.legal_targets(owner, {"type":"attack", "uid":uid}).is_empty(), "multiattack does not bypass deployment delay")
	_round(game)
	_check(-1 in game.legal_targets(owner, {"type":"attack", "uid":uid}), "deployment delay ends normally")
	var foot := _fighter()
	foot.unit_class = "infantry"
	var infantry := _play(game, foot)
	_check(game.apply_action(owner, {"type":"move", "uid":infantry}).is_empty(), "blitz infantry can advance")
	_buff(game, infantry, _limit(4, "battle", "chosen"))
	_check(game.legal_targets(owner, {"type":"attack", "uid":infantry}).is_empty(), "even four attacks cannot bypass infantry advance lock")
	game = _game()
	owner = game.state.active_player
	var tank := _fighter()
	tank.unit_class = "tank"
	uid = _play(game, tank)
	game.apply_action(owner, {"type":"move", "uid":uid})
	var guard := _base("脆弱守护")
	guard.health = 3
	guard.keywords = [{"id":"core.guard", "version":1, "params":{}}]
	var defender: Dictionary = game._new_unit(1-owner, _compile(guard))
	_check(not -1 in game.legal_targets(owner, {"type":"attack", "uid":uid}), "guard still restricts first attack")
	_check(game.apply_action(owner, {"type":"attack", "uid":uid, "target_uid":defender.uid}).is_empty(), "tank attacks after advance")
	_check(game._unit(uid).hp == 1 and game._unit(defender.uid).is_empty(), "first attack resolves retaliation and death")
	_check(_attack_hq(game, uid).is_empty(), "guard death opens HQ for second attack")
	game = _game()
	owner = game.state.active_player
	uid = _play(game, tank)
	game.apply_action(owner, {"type":"move", "uid":uid})
	guard.attack = 4
	defender = game._new_unit(1-owner, _compile(guard))
	game.apply_action(owner, {"type":"attack", "uid":uid, "target_uid":defender.uid})
	_check(game._unit(uid).is_empty() and not _attack_hq(game, uid).is_empty(), "retaliation death removes remaining attacks")

func _test_cost_layers() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var uid := _play(game, _fighter())
	_buff(game, uid, {"op":"modify_operation_cost", "target":"chosen", "cost_delta":-1, "duration":"battle"})
	game.state.players[owner].credits = 0
	_check(game._operation_cost(game._unit(uid)) == 0 and _attack_hq(game, uid).is_empty(), "zero-cost attack allowed")
	_check(_attack_hq(game, uid).is_empty() and not _attack_hq(game, uid).is_empty(), "free attacks remain bounded by cap")
	_buff(game, uid, {"op":"modify_operation_cost", "target":"chosen", "cost_delta":4, "duration":"end_of_turn"})
	_buff(game, uid, {"op":"modify_operation_cost", "target":"chosen", "cost_delta":4, "duration":"end_of_turn"})
	_check(game._unit(uid).operation_cost == 8, "cost layers accumulate below the current twelve-point cap")
	_round(game)
	_check(game._operation_cost(game._unit(uid)) == 0, "temporary cost expiry preserves permanent discount")
	var tank := _fighter()
	tank.unit_class = "tank"
	var moving := _play(game, tank)
	_buff(game, moving, {"op":"modify_operation_cost", "target":"chosen", "cost_delta":2, "duration":"battle"})
	game.state.players[owner].credits = 2
	_check(not game.can_move(moving) and game.legal_targets(owner, {"type":"attack", "uid":moving}).is_empty(), "increased costs apply to movement and attacks")
	game.state.players[owner].credits = 6
	_check(game.apply_action(owner, {"type":"move", "uid":moving}).is_empty(), "movement uses modified cost")
	_check(_attack_hq(game, moving).is_empty() and game.state.players[owner].credits == 0, "movement and attack each pay modified cost")
	var face := preload("res://scripts/ui/card_face.gd").new()
	face.spec = tank
	face.current_operation_cost = game._operation_cost(game._unit(moving))
	_check(face._operation_cost() == 3 and tank.operation_cost == 1, "card face shows current fee without mutating source")
	face.free()

func _test_destroy() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var victim := _base("阵亡回响")
	victim.health = 20
	victim.keywords = [{"id":"core.guard", "version":1, "params":{}}]
	victim.abilities = [{"trigger":"on_death", "effects":[{"op":"damage", "target":"enemy_hq", "amount":2}]}]
	for i in 2: game._new_unit(1-owner, _compile(victim))
	var order := _base("消灭全部", "order")
	order.abilities = [{"trigger":"on_play", "effects":[{"op":"destroy", "target":"all_enemy_units"}, {"op":"heal", "target":"all_enemy_units", "amount":10}]}]
	_play(game, order)
	_check(game.state.units.is_empty(), "destroy ignores health and guard; later heal cannot restore removed units")
	_check(game.state.players[owner].hp == 16, "all destroyed units trigger death exactly once")
	_play(game, order)
	_check(game.state.players[owner].hp == 16, "empty destroy target is a paid no-op")
	var self_destruct := _base("牺牲")
	self_destruct.abilities = [{"trigger":"on_play", "effects":[{"op":"destroy", "target":"self"}, {"op":"draw", "player":"owner", "amount":1}]}, {"trigger":"on_death", "effects":[{"op":"damage", "target":"enemy_hq", "amount":2}]}]
	var uid := _play(game, self_destruct)
	_check(game._unit(uid).is_empty() and game.state.players[1-owner].hp == 18, "self destruction retains source snapshot and death effects")

func _test_shared_layer_budget() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var uid := _play(game, _fighter())
	for i in 63:
		game._unit(uid).operation_costs.append({"modifier_id":i+100, "source_uid":uid, "cost_delta":-1, "expires_turn":-1})
	var order := _base("层数溢出", "order")
	order.play_target = {"side":"ally", "row":"any"}
	order.abilities = [{"trigger":"on_play", "effects":[_limit(3, "battle", "chosen")]}]
	game.state.players[owner].hand.append({"instance_id":"overflow", "card":_compile(order)})
	var previous: Dictionary = game.state.duplicate(true)
	var error: String = game.apply_action(owner, {"type":"play", "hand_id":"overflow", "target_uid":uid})
	_check(error == "RULE_BUDGET_EXCEEDED", "all modifier kinds share layer cap")
	_check(game.state.units == previous.units and game.state.players == previous.players, "layer overflow rolls back full action")

func _multiplier(against: String = "infantry", phase: String = "attack", value: int = 2, duration: String = "battle", target: String = "self") -> Dictionary:
	return {"op":"set_combat_damage_multiplier", "target":target, "against":against, "applies_to":phase, "multiplier":value, "duration":duration}

func _test_combat_multipliers() -> void:
	for defender_class in ["infantry", "tank", "artillery", "fighter", "bomber"]:
		var game := _game()
		var owner: int = game.state.active_player
		var attacker := _fighter()
		attacker.abilities[0].effects.append(_multiplier())
		var uid := _play(game, attacker)
		var victim := _base("兵种过滤目标")
		victim.unit_class = defender_class
		victim.health = 20
		var defender: Dictionary = game._new_unit(1-owner, _compile(victim))
		_check(game.apply_action(owner, {"type":"attack", "uid":uid, "target_uid":defender.uid}).is_empty(), "filtered combat accepted")
		_check(game._unit(defender.uid).hp == (14 if defender_class == "infantry" else 17), "only matching class doubled")
		_check(game._unit(uid).hp == 4, "artillery still avoids retaliation")
		_check(_attack_hq(game, uid).is_empty() and game.state.players[1-owner].hp == 17, "HQ not accidentally treated as infantry")
	var game := _game()
	var owner: int = game.state.active_player
	var tank := _fighter()
	tank.unit_class = "tank"
	tank.health = 20
	tank.abilities[0].effects.append(_multiplier("infantry", "attack"))
	var uid := _play(game, tank)
	game.apply_action(owner, {"type":"move", "uid":uid})
	var defender_spec := _base("反击倍率")
	defender_spec.unit_class = "infantry"
	defender_spec.health = 20
	var defender: Dictionary = game._new_unit(1-owner, _compile(defender_spec))
	defender.combat_damage_rules.append({"against":"tank", "applies_to":"retaliation", "multiplier":3, "expires_turn":-1})
	_check(game.apply_action(owner, {"type":"attack", "uid":uid, "target_uid":defender.uid}).is_empty(), "active and retaliation multipliers resolve in same battle")
	_check(game._unit(defender.uid).hp == 14 and game._unit(uid).hp == 11, "each combatant uses own matching phase")
	_check(game._combat_damage(game._unit(uid), defender, "retaliation") == 3, "attack only layer cannot multiply retaliation")
	_buff(game, uid, _multiplier("any", "both", 4, "end_of_turn", "chosen"))
	_check(game._combat_damage(game._unit(uid), defender, "attack") == 12, "latest matching setting replaces instead of multiplying")
	_buff(game, uid, _multiplier("tank", "attack", 3, "battle", "chosen"))
	_check(game._combat_damage(game._unit(uid), defender, "attack") == 12, "later nonmatching layer does not suppress earlier match")
	var spell := _base("固定技能伤害", "order")
	spell.abilities = [{"trigger":"on_play", "effects":[{"op":"damage", "target":"all_enemy_units", "amount":2}]}]
	_play(game, spell)
	_check(game._unit(defender.uid).hp == 12, "DSL skill damage remains unchanged")
	_round(game)
	_check(game._combat_damage(game._unit(uid), defender, "attack") == 6, "temporary expiry restores permanent multiplier")
	_check(game._combat_damage(game._unit(uid), {}, "attack") == 3, "expiry removes temporary HQ multiplier")
	game._unit(uid).attack = 0
	_check(game._combat_damage(game._unit(uid), defender, "attack") == 0, "zero attack remains zero")
	for value in [-1, 5]:
		tank.abilities = [{"trigger":"on_play", "effects":[_multiplier("infantry", "attack", value)]}]
		_check(not Runtime.compile_card(tank, Runtime.builtin_keywords()).ok, "invalid multiplier rejected")
	var keyword: Dictionary = _read("keywords/example_fight.json")
	keyword.parameters = {"x":{"type":"integer", "minimum":1, "maximum":4}}
	keyword.implementation.abilities[0].effects = [_multiplier()]
	keyword.implementation.abilities[0].effects[0].multiplier = {"param":"x"}
	_check(Runtime.validate_keyword(keyword).is_empty(), "multiplier template parameter range accepted")
	keyword.parameters.x.maximum = 5
	_check(not Runtime.validate_keyword(keyword).is_empty(), "multiplier template range above four rejected")
