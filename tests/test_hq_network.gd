extends SceneTree
## Run two independent Godot processes with -- --role=host|client --port=PORT.
const Controller = preload("res://scripts/network/match_controller.gd")
const Runtime = preload("res://scripts/core/card_runtime.gd")

var controller
var role := "host"
var port := 24681
var stage := 0
var checks := 0
var failure := false
var saw_suspend := false
var received_initial := false
var started := 0.0
var last_play_request: Dictionary = {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
	call_deferred("_run")

func _run() -> void:
	controller = Controller.new()
	controller.name = "MatchController"
	root.add_child(controller)
	if role != "unit":
		controller.state_changed.connect(_changed)
	controller.notice.connect(func(message): print(role, " notice: ", message))
	controller.status_changed.connect(func(): print(role, " status: ", controller.status))
	_check(controller._normalize_action({"type": "end_turn", "player": 0}).is_empty(), "extra identity field rejected")
	_check(controller._normalize_action({"type": "attack", "uid": true, "target_uid": -1}).is_empty(), "boolean entity rejected")
	_check(not controller._safe_message({"bad": Vector2.ONE}), "non-JSON variant rejected")
	_check(not controller._safe_message({"bad": "x".repeat(70000)}), "overlong text rejected")
	controller.faction_catalog = {"11111111-1111-4111-8111-111111111111":{"role":"major"}}
	controller.faction_catalog["22222222-2222-4222-8222-222222222222"] = {"role":"major"}
	controller.main_faction_id = "11111111-1111-4111-8111-111111111111" if role=="client" else "22222222-2222-4222-8222-222222222222"
	var definitions: Array = Runtime.builtin_keywords()
	var changed: Dictionary = definitions[0].duplicate(true)
	changed.description += "不同"
	_check(not controller._merge_keywords(definitions, [changed]).ok, "immutable keyword conflict rejected")
	_check(not controller._prepare_deck(_fixtures(role).slice(0, 23), definitions).ok, "23-card deck rejected")
	var copies: Array = []
	for i in 40:
		copies.append(_fixtures(role)[0])
	_check(not controller._prepare_deck(copies, definitions).ok, "excess identical cards rejected")
	if role == "unit":
		_lifecycle_checks(definitions)
		return
	var hq_fixtures: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures835.json"))
	controller.headquarters=hq_fixtures.cards[0 if role=="host" else 1]
	started = Time.get_ticks_msec() / 1000.0
	var error: Error
	if role == "host":
		error = controller.host_game(_fixtures("host"), definitions, port)
	else:
		error = controller.join_game("127.0.0.1", _fixtures("client"), definitions, port)
	_check(error == OK, "ENet open")
	_timeout()

func _timeout() -> void:
	await create_timer(35.0).timeout
	if not failure:
		_fail("network scenario exceeded 35 seconds, stage " + str(stage))

func _lifecycle_checks(definitions: Array) -> void:
	_check(controller.start_solo(_fixtures("solo"), definitions).is_empty(), "solo starts without built-in cards")
	_check(controller.state.players[0].main_faction_id==controller.main_faction_id and controller.state.players[1].main_faction_id==controller.main_faction_id,"Solo cards use chosen main faction, even without matching cards")
	var sequence: int = controller.state.state_seq
	if controller.state.active_player == 0:
		controller.submit_action({"type": "end_turn"})
	for step in 20:
		if controller.state.active_player == 0:
			break
		controller._ai_due = 0.0
		controller._process(0.0)
	_check(controller.state.active_player == 0, "AI completes its turn")
	_check(controller.state.state_seq > sequence, "AI commits legal actions")
	_check(controller.state.players[1].hand.is_empty(), "solo also uses filtered opponent view")
	controller.mode = "host"
	controller._suspended = true
	controller._disconnect_deadline = controller._now() - 1.0
	sequence = controller.state.state_seq
	controller._process(0.0)
	_check(controller.state.winner == 0, "expired disconnect awards host victory")
	_check(controller.state.state_seq == sequence + 1, "disconnect result advances lifecycle sequence")
	_check(not controller.state.suspended, "ended game no longer suspended")
	_check(controller.start_solo(_fixtures("budget"), definitions).is_empty(), "budget scenario starts")
	controller.mode = "host"
	controller._engine.state.active_player = 1
	controller._engine.state.players[1].credits = 12
	var unit: Dictionary = controller._engine._new_unit(1, Runtime.compile_card(_fixtures("budget")[0], definitions))
	for index in 64:
		unit.modifiers.append({"modifier_id": index, "attack_delta": 1, "health_delta": 0, "source_uid": unit.uid, "expires_turn": -1})
	controller._engine._recompute(unit)
	var overflow: Dictionary = _fixtures("budget")[0].duplicate(true)
	overflow.kind = "order"
	overflow.unit_class = null
	overflow.attack = 0
	overflow.health = 0
	overflow.appearance = {"emblem": "order"}
	overflow.play_target = {"side": "ally", "row": "any"}
	overflow.abilities = [{"trigger": "on_play", "effects": [{"op": "modify_stats", "target": "chosen", "attack_delta": 1, "health_delta": 0, "duration": "battle"}]}]
	controller._engine.state.players[1].hand.append({"instance_id": "overflow", "card": Runtime.compile_card(overflow, definitions)})
	controller._refresh_views()
	sequence = controller.state.state_seq
	controller._process_action(1, {"match_id": controller._match_id, "action_id": "test-rule-budget", "expected_state_seq": sequence, "command": {"type": "play", "hand_id": "overflow", "target_uid": int(unit.uid)}})
	_check(controller.state.winner == 3, "remote rule fault also notifies non-submitting host")
	_check(controller.state.state_seq == sequence + 1, "remote rule fault publishes aborted lifecycle sequence")
	controller.leave_game()
	_check(controller.state.is_empty() and controller.mode == "menu", "leave clears frozen match")
	print("NETWORK_PASS unit checks=", checks)
	quit(0)

func _changed() -> void:
	if controller.state.is_empty() or failure:
		return
	var state: Dictionary = controller.state
	var own := 0 if role == "host" else 1
	_check(state.players[1 - own].hand.is_empty(), "opponent hand hidden")
	_check(state.players[0].deck.is_empty() and state.players[1].deck.is_empty(), "both decks hidden")
	_check(state.players[own].hand.size() == state.players[own].hand_count, "own hand count matches")
	if not received_initial:
		received_initial = true
		_check(state.players[0].max_hp==35 and state.players[1].max_hp==25,"LAN freezes distinct headquarters health")
		_check(state.players[0].headquarters.definition.name=="后勤总部" and state.players[1].headquarters.definition.name=="空军总部","LAN publishes both headquarters definitions")
		_check(state.players[0].main_faction_id=="22222222-2222-4222-8222-222222222222" and state.players[1].main_faction_id=="11111111-1111-4111-8111-111111111111","LAN freezes both nominal main factions")
		_check(not JSON.stringify(state).contains("_%s_only_" % ("client" if role == "host" else "host")), "opponent definitions absent from initial snapshot")
	if role == "host":
		_host_step(state)
	else:
		_client_step(state)

func _host_step(state: Dictionary) -> void:
	if bool(state.get("suspended", false)):
		saw_suspend = true
		return
	if stage == 0:
		stage = 1
		call_deferred("_host_initial_action")
	elif stage == 1 and state.active_player == 0 and state.turn >= 3:
		stage = 2
		_check(saw_suspend, "client disconnect suspended host match")
		_check(state.units.size() == 1, "client play executed once before resume")
		controller.submit_action({"type": "concede"})
	elif stage == 2 and state.winner == 1:
		stage = 3
		_finish()

func _host_initial_action() -> void:
	# The engine randomly chooses the first player. Hold the test client until turn 2.
	if controller.state.active_player == 1:
		controller._process_action(1, {"match_id": controller._match_id, "action_id": "test-prepare-first-turn", "expected_state_seq": controller.state.state_seq, "command": {"type": "end_turn"}})
	var before: int = controller.state.state_seq
	var message := {"match_id": controller._match_id, "action_id": "test-fixed-action-1", "expected_state_seq": before, "command": {"type": "end_turn"}}
	controller._process_action(0, message)
	var after: int = controller.state.state_seq
	_check(after == before + 1, "accepted action advances sequence")
	controller._process_action(0, message)
	_check(controller.state.state_seq == after, "same action retry is idempotent")
	var changed := message.duplicate(true)
	changed.command = {"type": "concede"}
	controller._process_action(0, changed)
	_check(controller.state.winner == -1 and controller.state.state_seq == after, "same action ID changed command rejected")
	var stale := message.duplicate(true)
	stale.action_id = "test-stale-action"
	stale.command = {"type": "concede"}
	controller._process_action(0, stale)
	_check(controller.state.winner == -1 and controller.state.state_seq == after, "stale state rejected")
	var turn_cheat := message.duplicate(true)
	turn_cheat.action_id = "test-wrong-turn"
	turn_cheat.expected_state_seq = after
	controller._process_action(0, turn_cheat)
	_check(controller.state.state_seq == after, "host cannot act in client turn")

func _client_step(state: Dictionary) -> void:
	if stage == 0 and state.active_player == 1 and state.turn >= 2:
		stage = 1
		call_deferred("_client_play")
	elif stage == 1 and state.units.size() == 1:
		stage = 2
		call_deferred("_client_disconnect")
	elif stage == 2 and controller.connected and not bool(state.get("suspended", false)):
		stage = 3
		_check(state.units.size() == 1 and state.active_player == 1, "resume preserved board and turn")
		call_deferred("_client_end_turn")
	elif stage == 3 and state.winner == 1:
		stage = 4
		_finish()

func _client_play() -> void:
	var hand: Array = controller.state.players[1].hand
	_check(not hand.is_empty(), "own hand provided to client")
	controller.submit_action({"type": "play", "hand_id": hand[0].instance_id})
	last_play_request = controller._pending_action.duplicate(true)

func _client_disconnect() -> void:
	controller.multiplayer.multiplayer_peer.disconnect_peer(1)
	# ENet sends a graceful disconnect; the production reconnect handler remains responsible.
	await create_timer(0.3).timeout
	if controller.connected:
		controller._server_disconnected()

func _client_end_turn() -> void:
	# A request whose reply was lost before disconnect must still be idempotent.
	controller._action_request.rpc_id(1, last_play_request)
	controller.submit_action({"type": "end_turn"})

func _finish() -> void:
	await create_timer(0.5 if role == "host" else 0.2).timeout
	print("NETWORK_PASS ", role, " checks=", checks)
	controller.leave_game()
	quit(0)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		_fail(description)

func _fail(description: String) -> void:
	if failure:
		return
	failure = true
	push_error("NETWORK_FAIL " + role + ": " + description)
	quit(1)

func _fixtures(prefix: String) -> Array:
	var result: Array = []
	for index in 10:
		var card := {"schema_version": "1.0.0", "ruleset_version": "frontline-1", "name": "_%s_only_%d" % [prefix, index], "flavor_text": "仅限自动测试", "faction_id":"11111111-1111-4111-8111-111111111111", "kind": "unit", "unit_class": "infantry", "cost": 1, "operation_cost": 0, "attack": 2, "health": 3, "keywords": [], "play_target": null, "abilities": [], "tokens": [], "appearance": {"emblem": "infantry"}}
		for copy in 4:
			result.append(card.duplicate(true))
	return result
