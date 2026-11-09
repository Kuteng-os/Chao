extends SceneTree
## Spawned by the Node central-matches test with an isolated HTTP service and test identities.
const Controller = preload("res://scripts/network/match_controller.gd")
var checks := 0
var failed := false
var first
var second
var second_updates := 0
var cancelled_start_result := -1

class TestEmotes extends Node:
	var id := ""
	func entry(value: String) -> Dictionary: return {"emote_id":id} if value==id else {}

class TestApi extends "res://scripts/app_store.gd":
	var base := ""
	var token := ""
	var create_response_delay := 0.0
	func _ready() -> void: pass
	func request(path: String, method: int = HTTPClient.METHOD_GET, payload: Dictionary = {}) -> Dictionary:
		settings.backend_url = base
		settings.api_token = token
		var result: Dictionary = await super.request(path, method, payload)
		if path == "/v1/rooms" and method == HTTPClient.METHOD_POST and create_response_delay > 0.0:
			await get_tree().create_timer(create_response_delay).timeout
		return result

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var store_a := TestApi.new()
	store_a.base = OS.get_environment("CLOUD_TEST_URL")
	store_a.token = OS.get_environment("CLOUD_TEST_TOKEN_A")
	store_a.main_sin="envy"
	store_a.ally_sin="gloom"
	root.add_child(store_a)
	var store_b := TestApi.new()
	store_b.base = store_a.base
	store_b.token = OS.get_environment("CLOUD_TEST_TOKEN_B")
	store_b.main_sin="wrath"
	store_b.ally_sin="gloom"
	root.add_child(store_b)
	_check(store_a.client_build() == 906, "real AppStore reports running client version")
	first = Controller.new()
	first.name = "CloudOne"
	root.add_child(first)
	second = Controller.new()
	second.name = "CloudTwo"
	root.add_child(second)
	second.state_changed.connect(func(): second_updates += 1)
	var decks: Array = JSON.parse_string(OS.get_environment("CLOUD_TEST_DECKS"))
	_check(await first.start_cloud(store_a, decks[0]) == OK, "cloud create")
	_check(first.mode == "cloud" and first.connected and first.state.is_empty(), "cloud waiting room state")
	_check(await second.start_cloud(store_b, decks[1], first.cloud_room_code) == OK, "cloud join by code")
	for index in 40:
		if not first.state.is_empty(): break
		await create_timer(0.1).timeout
	_check(not first.state.is_empty() and not second.state.is_empty(), "HTTP polling starts both clients")
	if first.state.is_empty() or second.state.is_empty(): quit(1); return
	_check(first.local_player == 0 and second.local_player == 1, "server assigned seats")
	_check(first.state.players[1].hand.is_empty() and second.state.players[0].hand.is_empty(), "opponent hands filtered")
	var emotes := TestEmotes.new();emotes.id=OS.get_environment("CLOUD_TEST_EMOTE_ID");root.add_child(emotes)
	first.emote_service=emotes;second.emote_service=emotes
	var emotes_a: Array=[];var emotes_b: Array=[]
	first.emote_received.connect(func(player,id,point,display_scale):emotes_a.append([player,id,point,display_scale]))
	second.emote_received.connect(func(player,id,point,display_scale):emotes_b.append([player,id,point,display_scale]))
	var emote_seq: int=first.state.state_seq
	first.send_emote(emotes.id,Vector2(0.25,0.75))
	for index in 40:
		if emotes_a.size()==1 and emotes_b.size()==1: break
		await create_timer(0.05).timeout
	_check(emotes_a.size()==1 and emotes_b.size()==1,"both cloud clients receive emote")
	_check(not emotes_a.is_empty() and not emotes_b.is_empty() and emotes_a[0][3]==1.5 and emotes_b[0][3]==1.5,"both cloud clients use server author scale despite stale local cache")
	_check(not emotes_b.is_empty() and emotes_b[0][2].is_equal_approx(Vector2(0.25,0.75)),"emote position crosses HTTP unchanged")
	await create_timer(0.1).timeout
	first.send_emote(emotes.id,Vector2(0.4,0.5))
	for index in 40:
		if emotes_a.size()==2 and emotes_b.size()==2: break
		await create_timer(0.05).timeout
	_check(emotes_a.size()==2 and emotes_b.size()==2,"rapid emotes are delivered separately")
	_check(first.state.state_seq==emote_seq and second.state.state_seq==emote_seq,"emotes do not change battle sequence")
	var actor = first if first.state.active_player == 0 else second
	var before: int = actor.state.state_seq
	var hand: Array = actor.state.players[actor.local_player].hand
	actor.submit_action({"type": "play", "hand_id": str(hand[0].instance_id)})
	for index in 50:
		if first.state.state_seq > before and second.state.state_seq > before: break
		await create_timer(0.1).timeout
	_check(first.state.units.size() == 1 and second.state.units.size() == 1, "cloud play and peer polling")
	_check(not actor._cloud_pending, "action acknowledgment releases pending lock")
	await create_timer(0.3).timeout
	var update_count := second_updates
	await create_timer(1.3).timeout
	_check(second_updates == update_count, "unchanged polls do not reset UI selection")
	second.leave_game()
	_check(second.mode == "menu" and second.cloud_room_id.is_empty(), "leave immediately clears local session")
	for index in 40:
		if first.state.winner != -1: break
		await create_timer(0.1).timeout
	_check(first.state.winner == 0, "leave is adjudicated by server")
	first.leave_game()
	await create_timer(0.2).timeout
	store_a.create_response_delay = 0.4
	_cancelled_start(store_a, decks[0])
	await create_timer(0.1).timeout
	first.leave_game()
	await create_timer(0.8).timeout
	_check(cancelled_start_result == ERR_SKIP and first.mode == "menu", "cancelled delayed create cannot restore local state")
	var rooms_result: Dictionary = await store_a.request("/v1/rooms")
	var active_owned := false
	for room in rooms_result.get("data", {}).get("rooms", []):
		if room.get("mine", false) and room.get("status") in ["waiting", "starting", "active", "suspended"]: active_owned = true
	_check(rooms_result.get("ok", false) and not active_owned, "cancelled delayed create releases its server seat")
	if not failed: print("CLOUD_CONTROLLER_PASS checks=", checks)
	quit(1 if failed else 0)

func _cancelled_start(api: Node, deck: Array) -> void:
	cancelled_start_result = await first.start_cloud(api, deck)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("CLOUD_CONTROLLER_FAIL " + description)
