extends "res://tests/test_mechanics.gd"

func _initialize() -> void:
	_test_hand_types()
	_test_summoned_rules()
	_test_generation_limits()
	_test_summon_choices()
	_test_turn_fireball()
	print("GENERATED CARD TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _token(kind: String = "unit") -> Dictionary:
	return {"token_id":"child","name":"衍生测试","kind":kind,"cost":2,"operation_cost":0,"unit_class":"artillery" if kind == "unit" else null,"attack":2 if kind == "unit" else 0,"health":4 if kind == "unit" else 0,"keywords":[],"abilities":[],"play_target":null}

func _create(id: String = "child", player: String = "owner", amount: int = 1) -> Dictionary:
	return {"op":"create_card","token_id":id,"player":player,"amount":amount}

func _maker(token: Dictionary, summon: bool = false) -> Dictionary:
	var c := _base("制造者", "order")
	c.tokens = [token]
	c.abilities = [{"trigger":"on_play","effects":[{"op":"summon","token_id":token.token_id,"amount":1,"row":"support"} if summon else _create(token.token_id)]}]
	return c

func _play_child(game: RefCounted, target: int = -1) -> int:
	var owner := _rich(game)
	var entry: Dictionary = game.state.players[owner].hand.back()
	var cost: int = 0 if entry.card.definition.kind=="counter" else entry.card.definition.cost
	var uid: int = game.state.next_uid
	_check(game.apply_action(owner,{"type":"play","hand_id":entry.instance_id,"target_uid":target}).is_empty(),"play generated card normally")
	_check(game.state.players[owner].credits == 12-cost,"generated card pays its own cost")
	return uid

func _test_hand_types() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var child := _token()
	child.cost = 0
	child.keywords = [{"id":"core.blitz","version":1,"params":{}},{"id":"standard.heavy_armor","version":1,"params":{"x":3}}]
	child.abilities = [{"trigger":"on_play","effects":[{"op":"damage","target":"enemy_hq","amount":2}]},{"trigger":"on_summon","effects":[{"op":"damage","target":"enemy_hq","amount":5}]}]
	var deck_size: int = game.state.players[owner].deck.size()
	_play(game,_maker(child))
	_check(game.state.units.is_empty() and game.state.players[1-owner].hp == 20,"creating in hand does not deploy or trigger effects")
	_check(game.state.players[owner].deck.size() == deck_size,"generation does not consume deck cards")
	var entry: Dictionary = game.state.players[owner].hand.back()
	_check(entry.card.definition.kind == "unit" and entry.card.definition.cost == 0,"generated unit has separate playable definition")
	_check(entry.card.generated_token_id == "child" and not entry.card.generated_origin.definition_hash.is_empty(),"root provenance preserved")
	var uid := _play_child(game)
	_check(game.state.players[1-owner].hp == 18,"hand deployment triggers on_play, not on_summon")
	_check(game.stack_count(game._unit(uid),"heavy_armor") == 3 and game._operation_cost(game._unit(uid)) == 0,"registered armor and configured action cost")
	_check(_attack_hq(game,uid).is_empty(),"generated artillery uses normal legal actions")
	var order := _token("order")
	order.abilities = [{"trigger":"on_play","effects":[{"op":"heal","target":"own_hq","amount":3}]}]
	game.state.players[owner].hp = 10
	_play(game,_maker(order))
	_check(game.state.players[owner].hp == 10,"created order does not resolve early")
	_play_child(game)
	_check(game.state.players[owner].hp == 13,"generated order resolves after being played")
	var counter := _token("counter")
	counter["counter_trigger"] = "enemy_order_played"
	counter.abilities = [{"trigger":"on_reveal","effects":[{"op":"cancel_action"}]}]
	_play(game,_maker(counter))
	_play_child(game)
	_check(game.state.players[owner].counters.size() == 1,"generated counter can be set")
	_check(game.view_for(1-owner).players[owner].counters.is_empty(),"set generated counter remains secret")
	game.apply_action(owner,{"type":"end_turn"})
	var hit := _base("敌方指令","order")
	hit.abilities = [{"trigger":"on_play","effects":[{"op":"damage","target":"enemy_hq","amount":4}]}]
	_play(game,hit)
	_check(game.state.players[owner].hp == 13 and game.state.players[owner].counters.is_empty(),"generated counter cancels once")
	_check(game.state.telemetry.filter(func(e: Dictionary) -> bool: return e.kind == "generated_play").size() == 3,"generated plays tracked separately from maker usage")

func _test_summoned_rules() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var child := _token()
	child.keywords = [{"id":"standard.heavy_armor","version":1,"params":{"x":2}}]
	child.abilities = [{"trigger":"on_summon","effects":[{"op":"damage","target":"enemy_hq","amount":{"stat":"source_base_health"}}]},{"trigger":"own_turn_end","effects":[{"op":"heal","target":"own_hq","amount":1}]},{"trigger":"on_death","effects":[{"op":"damage","target":"enemy_hq","amount":{"stat":"source_base_health"}}]}]
	game.state.players[owner].hp = 10
	var uid := _play(game,_maker(child,true))
	_check(game._unit_definition(game._unit(uid)).name == child.name,"field displays child name")
	_check(game._unit(uid).operation_cost == 0 and game._unit(uid).stacks.heavy_armor == 2,"summoned token gets cost and passive template")
	_check(game.state.players[1-owner].hp == 16,"dynamic summon damage reads child health rather than maker order health zero")
	_check(game.apply_action(owner,{"type":"end_turn"}).is_empty(),"end generated unit turn")
	_check(game.state.players[owner].hp == 11,"generated unit turn effect resolves")
	var destroy := _base("消灭衍生物","order")
	destroy.play_target = {"side":"enemy","row":"any"}
	destroy.abilities = [{"trigger":"on_play","effects":[{"op":"destroy","target":"chosen"}]}]
	_play(game,destroy,uid)
	_check(game.state.players[1-owner].hp == 12,"generated unit death reads its own frozen base health")

func _test_generation_limits() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var child := _token()
	var maker := _maker(child)
	maker.abilities[0].effects[0].player = "opponent"
	maker.abilities[0].effects[0].amount = 3
	var opposite: Dictionary = game.state.players[1-owner]
	while opposite.hand.size() < 9: opposite.hand.append({"instance_id":"fill"+str(opposite.hand.size()),"card":_compile(_base())})
	_play(game,maker)
	opposite = game.state.players[1-owner]
	_check(opposite.hand.size() == 10 and opposite.burned.size() == 2,"generated cards obey recipient hand limit")
	_check(opposite.fatigue == 0,"generation has no fatigue")
	_check(game.view_for(owner).players[1-owner].hand.is_empty(),"opponent generated hand stays private")
	# Self-replacing summon chain must hit the transaction budget, not recurse
	# on the interpreter call stack or hang the server.
	game = _game()
	child.abilities = [{"trigger":"on_summon","effects":[{"op":"destroy","target":"self"},{"op":"summon","token_id":"child","amount":1,"row":"support"}]}]
	var c := _compile(_maker(child,true))
	owner = _rich(game)
	game.state.players[owner].hand = [{"instance_id":"loop","card":c}]
	var original_size: int = game.state.units.size()
	_check(game.apply_action(owner,{"type":"play","hand_id":"loop"}) == "RULE_BUDGET_EXCEEDED","cyclic summon halts at bounded budget")
	_check(game.state.units.size() == original_size and game.state.players[owner].hand.size() == 1,"fault restores origin without partial creations")

func _test_summon_choices() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var child := _token()
	child.abilities = [{"trigger":"on_summon","target":{"side":"ally","row":"any"},"effects":[{"op":"modify_stats","target":"chosen","attack_delta":1,"health_delta":0,"duration":"battle"}]}]
	_play(game,_maker(child,true))
	_check(game.state.pending_choice.trigger == "on_summon","summon choice identified separately from death")
	var choice: Dictionary = game.state.pending_choice.duplicate(true)
	_check(game.apply_action(owner,{"type":"choose_target","choice_id":choice.choice_id,"target_uid":choice.targets[0]}).is_empty(),"summon choice replay resumes")
	_check(game.state.units.size() == 1 and game.state.units[0].attack == 3,"summon choice cannot duplicate the unit or buff")

func _fireballs(entries: Array) -> Array:
	return entries.filter(func(entry: Dictionary) -> bool: return entry.get("card", entry).get("generated_token_id", "") == "fireball")

func _test_turn_fireball() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var fireball := _token("order")
	fireball.token_id = "fireball"
	fireball.name = "火球术"
	fireball.cost = 1
	fireball.play_target = {"side":"enemy","row":"any"}
	fireball.abilities = [{"trigger":"on_play","effects":[{"op":"damage","target":"chosen","amount":3}]}]
	var maker := _base("火焰大师")
	maker.unit_class = "bomber"
	maker.appearance.emblem = "bomber"
	maker.cost = 3
	maker.health = 2
	maker.tokens = [fireball]
	maker.abilities = [{"trigger":"own_turn_start","effects":[_create("fireball")]}]
	var uid := _play(game, maker)
	_check(_fireballs(game.state.players[owner].hand).is_empty(), "fireball is not created on deployment")
	_check(game.apply_action(owner, {"type":"end_turn"}).is_empty(), "end fire mage turn")
	_check(_fireballs(game.state.players[owner].hand).is_empty(), "opponent turn does not create fireball")
	var target := _play(game, _base("敌方目标"))
	_check(game.apply_action(1-owner, {"type":"end_turn"}).is_empty(), "start fire mage owner turn")
	var spells := _fireballs(game.state.players[owner].hand)
	_check(spells.size() == 1, "own turn creates exactly one fireball")
	var credits: int = game.state.players[owner].credits
	_check(game.apply_action(owner, {"type":"play","hand_id":spells[0].instance_id,"target_uid":target}).is_empty(), "generated fireball can target an enemy unit")
	_check(game.state.players[owner].credits == credits-1 and game._unit(target).hp == 1, "fireball pays one and deals three damage")
	_round(game)
	_check(_fireballs(game.state.players[owner].hand).size() == 1, "following own turn creates one more fireball")
	var filler := _compile(_base())
	while game.state.players[owner].hand.size() < 10:
		game.state.players[owner].hand.append({"instance_id":"fill"+str(game.state.players[owner].hand.size()),"card":filler})
	_round(game)
	_check(game.state.players[owner].hand.size() == 10 and _fireballs(game.state.players[owner].burned).size() == 1, "full hand burns the generated fireball")
	_check(game.apply_action(owner, {"type":"end_turn"}).is_empty(), "opponent can remove fire mage")
	var destroy := _base("消灭", "order")
	destroy.play_target = {"side":"enemy","row":"any"}
	destroy.abilities = [{"trigger":"on_play","effects":[{"op":"destroy","target":"chosen"}]}]
	_play(game, destroy, uid)
	_check(game.apply_action(1-owner, {"type":"end_turn"}).is_empty(), "start owner turn after mage death")
	_check(_fireballs(game.state.players[owner].hand).size() == 1 and _fireballs(game.state.players[owner].burned).size() == 1, "removed fire mage stops generating fireballs")
