extends "res://tests/test_mechanics.gd"

func _initialize() -> void:
	_test_named_summon()
	_test_capacity_and_search()
	_test_death_and_replay()
	_test_counter_and_periodic()
	print("DECK SEARCH TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _fetch(op: String = "summon_from_deck", name: String = "玉石", amount: int = 1) -> Dictionary:
	return {"op":op,"card_name":name,"amount":amount}

func _order(effect: Dictionary) -> Dictionary:
	var c := _base("检索指令", "order")
	c.abilities = [{"trigger":"on_play","effects":[effect]}]
	return c

func _jade() -> Dictionary:
	var c := _base("玉石")
	c.keywords = [{"id":"core.blitz","version":1,"params":{}},{"id":"standard.heavy_armor","version":1,"params":{"x":2}}]
	c.abilities = [{"trigger":"on_play","effects":[{"op":"damage","target":"enemy_hq","amount":7},_limit(2)]},{"trigger":"on_death","effects":[{"op":"damage","target":"enemy_hq","amount":2}]}]
	return c

func _test_named_summon() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var actual := _compile(_jade())
	actual["telemetry_ref"] = {"card_id":"frozen-jade","revision":2}
	actual["art_id"] = "frozen-art"
	var other := _compile(_base("底牌"))
	var older := actual.duplicate(true)
	older.telemetry_ref.revision = 1
	var same_name_order := _compile(_order({"op":"draw","player":"owner","amount":1}))
	same_name_order.definition.name = "玉石"
	game.state.players[owner].deck = [older,other,actual,same_name_order]
	var uid := _play(game, _order(_fetch()))
	var unit: Dictionary = game._unit(uid)
	_check(unit.card == actual, "moves frozen version including identity and artwork")
	_check(game.state.players[owner].deck == [older,other,same_name_order], "top matching unit removed once; same-name order skipped and order preserved")
	_check(game.stack_count(unit,"heavy_armor") == 2 and game.attack_limit(unit) == 2, "intrinsic armor and attack limit initialized")
	_check(game.state.players[1-owner].hp == 20, "summon does not trigger deployment damage")
	_check(unit.token_id.is_empty(), "real card is not a token")
	_check(game.can_move(uid), "native blitz still works")
	_check(game.state.telemetry.any(func(e: Dictionary) -> bool: return e.kind == "summon" and e.get("from_deck",false)), "summon telemetry retained")
	var kill := _order({"op":"destroy","target":"chosen"})
	kill.play_target = {"side":"ally","row":"any"}
	_play(game, kill, uid)
	_check(game.state.players[1-owner].hp == 18, "summoned card still triggers its own death ability")
	_check(game.state.discard.any(func(e: Dictionary) -> bool: return e.card == actual), "real card goes to discard with frozen identity")
	_check(game.state.players[1-owner].deck.size() > 0, "opponent deck untouched")

func _test_capacity_and_search() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var jade := _compile(_base("玉石"))
	game.state.players[owner].deck = [jade,jade,jade]
	for i in 3: _play(game, _base("占位"))
	var uid := _play(game, _order(_fetch("summon_from_deck","玉石",3)))
	_check(game._count_row(owner,"support") == 4 and game.state.players[owner].deck.size() == 2, "partial summon stops at support capacity and leaves remainder")
	_check(not game.can_move(uid), "non-blitz summoned unit waits")
	_play(game, _order(_fetch()))
	_check(game.state.players[owner].deck.size() == 2, "full board cannot burn a searched card")
	game.state.players[owner].hand.clear()
	_play(game, _order(_fetch("search_deck","玉石",3)))
	_check(game.state.players[owner].hand.size() == 2 and game.state.players[owner].deck.is_empty(), "search can fetch multiple into hand even on full board")
	_check(game.state.players[owner].hand[0].instance_id != game.state.players[owner].hand[1].instance_id, "searched copies have distinct hand instances")
	_check(game.state.players[owner].fatigue == 0, "missing matches do not cause fatigue")
	var view: Dictionary = game.view_for(1-owner)
	_check(view.players[owner].hand.is_empty() and view.players[owner].deck.is_empty() and not view.has("telemetry"), "search does not disclose hidden cards")
	game.state.players[owner].deck = [jade]
	while game.state.players[owner].hand.size() < 10:
		game.state.players[owner].hand.append({"instance_id":"full"+str(game.state.players[owner].hand.size()),"card":jade})
	_play(game, _order(_fetch("search_deck")))
	_check(game.state.players[owner].burned.size() == 1 and game.state.players[owner].deck.is_empty(), "full hand burns matching card once")
	game.state.players[owner].deck = [jade]
	_play(game, _order(_fetch("search_deck","玉")))
	_check(game.state.players[owner].deck.size() == 1, "matching is exact, not substring")

func _test_death_and_replay() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	game.state.players[owner].deck = [_compile(_jade())]
	var source := _base("遗赠")
	source.abilities = [{"trigger":"on_death","effects":[_fetch()]}]
	var uid := _play(game, source)
	for i in 3: _play(game, _base("占位"))
	var kill := _order({"op":"destroy","target":"chosen"})
	kill.play_target = {"side":"ally","row":"any"}
	_play(game, kill, uid)
	_check(game._count_row(owner,"support") == 4 and game.state.players[owner].deck.is_empty(), "death vacates a slot before named summon")
	_check(game.state.units.any(func(u: Dictionary) -> bool: return u.card.definition.name == "玉石"), "screenshot death effect resolves")
	# A later death choice replays the whole action. The deck move and summon
	# must occur only once in the committed result.
	game = _game()
	owner = game.state.active_player
	game.state.players[owner].deck = [_compile(_base("玉石"))]
	source.abilities = [{"trigger":"on_death","effects":[_fetch()]},{"trigger":"on_death","target":{"side":"ally","row":"any","timing":"trigger"},"effects":[{"op":"heal","target":"chosen","amount":1}]}]
	uid = _play(game, source)
	_play(game, kill, uid)
	_check(game.state.has("pending_choice"), "choice after summon pauses resolution")
	var choice: Dictionary = game.state.pending_choice.duplicate(true)
	_check(game.apply_action(owner,{"type":"choose_target","choice_id":choice.choice_id,"target_uid":choice.targets[0]}).is_empty(), "choice resumes replay")
	_check(game.state.units.size() == 1 and game.state.players[owner].deck.is_empty(), "choice replay cannot duplicate summoned card")
	_check(game.state.telemetry.filter(func(e: Dictionary) -> bool: return e.kind == "summon").size() == 1, "choice replay cannot duplicate summon statistics")

func _test_counter_and_periodic() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var counter := _base("部署陷阱", "counter")
	counter.appearance.emblem = "counter"
	counter["counter_trigger"] = "enemy_unit_deployed"
	counter.abilities = [{"trigger":"on_reveal","effects":[{"op":"destroy","target":"trigger_unit"}]}]
	game.state.active_player = 1-owner
	_play(game,counter)
	game.state.active_player = owner
	var jade := _base("玉石")
	jade.abilities = [{"trigger":"own_turn_end","effects":[{"op":"damage","target":"enemy_hq","amount":2}]}]
	game.state.players[owner].deck = [_compile(jade)]
	_play(game,_order(_fetch()))
	_check(game.state.players[1-owner].counters.size() == 1 and game.state.units.size() == 1, "deck summon does not activate deployment trap")
	_check(game.apply_action(owner,{"type":"end_turn"}).is_empty(), "summoned unit reaches end turn")
	_check(game.state.players[1-owner].hp == 18, "summoned real card retains periodic abilities")
