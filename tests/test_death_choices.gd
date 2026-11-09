extends "res://tests/test_engine.gd"

func _initialize() -> void:
	_test_contract()
	_test_selection()
	_test_no_target()
	_test_chain()
	_test_turn_continuation()
	print("DEATH CHOICES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _salvo() -> Dictionary:
	var spec := _base("最后一击")
	spec.abilities = _read("keywords/example_last_salvo.json").implementation.abilities
	spec.abilities[0].target["timing"]="trigger"
	return spec

func _kill(game: RefCounted, uid: int) -> void:
	var order := _base("消灭", "order")
	order.play_target = {"side":"enemy" if game._unit(uid).owner != game.state.active_player else "ally", "row":"any"}
	order.abilities = [{"trigger":"on_play", "effects":[{"op":"destroy", "target":"chosen"}]}]
	_play(game, order, uid)

func _choose(game: RefCounted, uid: int) -> String:
	return game.apply_action(int(game.state.pending_choice.owner), {"type":"choose_target", "choice_id":game.state.pending_choice.choice_id, "target_uid":uid})

func _test_contract() -> void:
	var keyword: Dictionary = _read("keywords/example_last_salvo.json")
	_check(Runtime.validate_keyword(keyword).is_empty(), "dynamic no-parameter template validates")
	var spec := _base()
	spec.keywords = [{"id":keyword.id, "version":1, "params":{}}]
	var compiled := Runtime.compile_card(spec, Runtime.builtin_keywords() + [keyword])
	_check(compiled.ok, "death keyword expands without play_target")
	_check("初始防御力" in Runtime.rules_text(compiled) and "部署时选定的敌方单位" in Runtime.rules_text(compiled), "readable dynamic preview")
	for invalid in [null, {}, {"stat":"source_health"}, {"stat":"source_base_health", "code":"eval"}, {"param":"health"}]:
		spec = _salvo()
		spec.abilities[0].effects[0].amount = invalid
		_check(not Runtime.compile_card(spec, Runtime.builtin_keywords()).ok, "reject invalid dynamic expression")
	spec = _salvo()
	spec.abilities[0].erase("target")
	_check(not Runtime.compile_card(spec, Runtime.builtin_keywords()).ok, "death choice must declare selector")
	keyword.implementation.abilities[0].trigger = "own_turn_end"
	_check(Runtime.validate_keyword(keyword).is_empty(), "periodic selection supported")

func _test_selection() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var source := _play(game, _salvo())
	game._unit(source).modifiers.append({"attack_delta":0, "health_delta":5, "expires_turn":-1})
	game._recompute(game._unit(source))
	game.apply_action(owner, {"type":"end_turn"})
	var target_spec := _base("目标")
	target_spec.health = 20
	var first := _play(game, target_spec)
	var second := _play(game, target_spec)
	_kill(game, source)
	_check(game.state.pending_choice.owner == owner and game.state.active_player != owner, "source controller selects during opponent turn")
	_check(game.state.pending_choice.targets == [first,second], "only living enemy units eligible")
	var view: Dictionary = game.view_for(1-owner)
	_check(not view.has("_resolution") and view.players[owner].hand.is_empty(), "pending origin never leaks hidden hands")
	var before := Runtime.sha(game.state)
	_check(not game.apply_action(1-owner, {"type":"end_turn"}).is_empty() and Runtime.sha(game.state) == before, "block advancing turn while selecting")
	var wrong := {"type":"choose_target", "choice_id":game.state.pending_choice.choice_id, "target_uid":first}
	_check(not game.apply_action(1-owner, wrong).is_empty() and Runtime.sha(game.state) == before, "opponent cannot choose")
	wrong.choice_id = "old-0"
	_check(not game.apply_action(owner, wrong).is_empty() and Runtime.sha(game.state) == before, "stale selection rejected")
	var telemetry_prefix: Array = game.state.telemetry.duplicate(true)
	var credits: int = game.state.players[1-owner].credits
	var seq: int = game.state.state_seq
	_check(_choose(game, second).is_empty(), "controller selects second enemy")
	_check(game._unit(first).hp == 20 and game._unit(second).hp == 16, "uses printed four health, ignores buffed nine or dead hp")
	_check(not game.state.has("pending_choice") and not game.state.has("_resolution"), "resolution completes")
	_check(game.state.players[1-owner].credits == credits and game.state.state_seq == seq+1, "origin costs not charged twice; seq monotonic")
	_check(game.state.telemetry.slice(0,telemetry_prefix.size()) == telemetry_prefix, "replay preserves exported telemetry prefix exactly")
	_check(not game.apply_action(owner, wrong).is_empty(), "resolved selection cannot replay")

func _test_no_target() -> void:
	var game := _game()
	var spec := _salvo()
	spec.abilities[0].effects.append({"op":"draw", "player":"owner", "amount":1})
	var uid := _play(game,spec)
	var count: int = game.state.players[game.state.active_player].hand.size()
	_kill(game,uid)
	_check(not game.state.has("pending_choice"), "no candidates auto skips")
	_check(game.state.players[game.state.active_player].hand.size() == count+1, "non chosen effects continue without candidates")

func _test_chain() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var a := _play(game,_salvo())
	var survivor := _play(game,_base("幸存者"))
	game.apply_action(owner,{"type":"end_turn"})
	var b := _play(game,_salvo())
	_kill(game,a)
	_check(_choose(game,b).is_empty(), "first death kills another death unit")
	_check(game.state.pending_choice.owner == 1-owner and game.state.pending_choice.targets == [survivor], "chained death transfers selection to other controller")
	_check(_choose(game,survivor).is_empty() and game._unit(survivor).is_empty(), "nested choices finish chain")
	_check(not game.state.has("pending_choice"), "no pending choice after chain")
	var deaths: Array = game.state.telemetry.filter(func(e: Dictionary) -> bool: return e.kind == "death")
	_check(deaths.size() == 3, "each chained death recorded once")

func _test_turn_continuation() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var source := _play(game,_salvo())
	game._unit(source).modifiers.append({"attack_delta":0,"health_delta":5,"expires_turn":int(game.state.turn)+1})
	game._unit(source).damage_taken = 5
	game._recompute(game._unit(source))
	game.apply_action(owner,{"type":"end_turn"})
	var enemy := _play(game,_base("临时增益消失目标"))
	var turn: int = game.state.turn
	game.apply_action(1-owner,{"type":"end_turn"})
	_check(game.state.has("pending_choice") and game.state.turn == turn, "expiry deaths suspend turn transition")
	_check(_choose(game,enemy).is_empty() and game.state.turn == turn+1 and game.state.active_player == owner, "resume original turn transition once")
	_check(game._unit(enemy).is_empty(), "expiry reads base health")
