extends SceneTree
## LAN spectating. Run three processes on one port (see tests/run_lan_watch.sh):
##   godot --headless --path . --script tests/test_lan_watch.gd -- --role=host|client|watch --port=PORT
## The host and client confirm their opening hands; the spectator follows the host and must see each update,
## the host's hand only, and must not be able to act.
const Controller = preload("res://scripts/network/match_controller.gd")
const Runtime = preload("res://scripts/core/card_runtime.gd")

var controller
var role := "host"
var port := 24691
var checks := 0
var failure := false
var done := false
var mulliganed := false
var seen_sequences: Dictionary = {}
var host_saw_spectator := false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="): role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="): port = int(argument.trim_prefix("--port="))
	call_deferred("_run")

func _run() -> void:
	controller = Controller.new()
	controller.name = "MatchController"
	controller.main_sin = "wrath"
	controller.ally_sin = "gloom"
	controller.commander_name = {"host": "房主", "client": "对手", "watch": "观众甲"}.get(role, role)
	controller.faction_catalog = {"11111111-1111-4111-8111-111111111111": {"role": "major"}, "22222222-2222-4222-8222-222222222222": {"role": "major"}}
	controller.main_faction_id = "11111111-1111-4111-8111-111111111111"
	root.add_child(controller)
	controller.state_changed.connect(_changed)
	controller.notice.connect(func(message):
		print(role, " notice: ", message)
		if role == "host" and str(message).contains("观众甲 正在观战"): host_saw_spectator = true)
	controller.status_changed.connect(func(): print(role, " status: ", controller.status))
	var definitions: Array = Runtime.builtin_keywords()
	var error: Error
	match role:
		"host": error = controller.host_game(_fixtures("host"), definitions, port)
		"client":
			await create_timer(1.5).timeout
			error = controller.join_game("127.0.0.1", _fixtures("client"), definitions, port)
		"watch":
			await create_timer(0.5).timeout
			_check(controller.watch_game("127.0.0.1", 2, port) == ERR_INVALID_PARAMETER, "only side 0 or 1 can be followed")
			error = controller.watch_game("127.0.0.1", 0, port)
	_check(error == OK, "ENet open")
	_timeout()

func _timeout() -> void:
	await create_timer(30.0).timeout
	if not done: _fail("scenario exceeded 30 seconds")

func _changed() -> void:
	var state: Dictionary = controller.state
	if state.is_empty() or done: return
	match role:
		"host", "client":
			if state.has("mulligan") and not mulliganed:
				mulliganed = true
				controller.submit_action({"type": "mulligan", "hand_ids": []})
			if role == "host" and not state.has("mulligan"):
				_check(host_saw_spectator, "the host is told who is watching")
				# Leave time for the last snapshot to reach the spectator before closing the room.
				await create_timer(2.0).timeout
				_finish()
			if role == "client" and not state.has("mulligan"):
				await create_timer(3.0).timeout
				_finish()
		"watch":
			_check(controller.spectating and controller.local_player == 0, "the spectator follows the host")
			_check(not state.players[0].hand.is_empty(), "the followed side's hand is visible")
			_check(state.players[1].hand.is_empty() and int(state.players[1].hand_count) > 0, "the other hand stays hidden")
			_check(state.players[1].get("commander_name") == "对手", "player names come through")
			seen_sequences[int(state.state_seq)] = true
			var before := int(state.state_seq)
			controller.submit_action({"type": "end_turn"})
			_check(int(controller.state.state_seq) == before, "a spectator cannot act")
			if not state.has("mulligan"):
				_check(seen_sequences.size() >= 2, "the spectator saw the match move on")
				_check(controller.status.begins_with("观战 · 房主"), "status names the followed player")
				_finish()

func _finish() -> void:
	if done: return
	done = true
	print(role, " LAN WATCH: ", checks, " checks, ", 1 if failure else 0, " failures")
	controller.leave_game()
	quit(1 if failure else 0)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: _fail(description)

func _fail(description: String) -> void:
	if failure and done: return
	failure = true
	push_error(role + " FAIL: " + description)
	if not done:
		done = true
		print(role, " LAN WATCH: ", checks, " checks, 1 failures")
		quit(1)

func _fixtures(prefix: String) -> Array:
	var result: Array = []
	for index in 10:
		var card := {"schema_version": "1.0.0", "ruleset_version": "frontline-1", "name": "_%s_only_%d" % [prefix, index], "flavor_text": "仅限自动测试", "faction_id":"11111111-1111-4111-8111-111111111111", "kind": "unit", "unit_class": "infantry", "cost": 1, "operation_cost": 0, "attack": 2, "health": 3, "keywords": [], "play_target": null, "abilities": [], "tokens": [], "appearance": {"emblem": "infantry"}}
		for copy in 4:
			result.append(card.duplicate(true))
	return result
