class_name MatchController
extends Node
## Direct ENet LAN matches. The host is trusted; this is not the production net-1 protocol.

const Runtime = preload("res://scripts/core/card_runtime.gd")
const Battle = preload("res://scripts/core/battle_engine.gd")
const PROTOCOL := "frontline-lan-40"
const MAX_PACKET_BYTES := 1048576
const GRACE_SECONDS := 30.0

signal emote_received(player: int, emote_id: String, point: Vector2, display_scale: float)
var emote_service: Node
var _emote_seen := 0
var _emote_cooldowns: Dictionary = {}
var _emote_inflight := 0
signal state_changed
signal notice(message: String)
signal status_changed

var state: Dictionary = {}
var faction_catalog: Dictionary = {}
var headquarters: Dictionary = {}
var _headquarters_source: Dictionary = {}
var main_sin := ""
var ally_sin := ""
var _match_sins: Array = ["", ""]
var main_faction_id := ""
var _match_factions: Array = ["",""]
var commander_name := "指挥官"
var _match_names: Array = ["指挥官","对方指挥官"]
var local_player := 0
var spectating := false
var debug_console_open := false
var debug_ai_paused := false
var debug_session = preload("res://scripts/debug_console.gd").new()
var mode := "menu"
var status := "尚未开始对局"
var connected := false
var cloud_room_id := ""
var cloud_room_code := ""
var _cloud_store: Node
var _cloud_epoch := 0
var _cloud_poll_due := 0.0
var _cloud_polling := false
var _cloud_pending := false

var _engine
var _deck: Array = []
var _keywords: Array = []
var _remote_peer := 0
var _match_id := ""
var _resume_token := ""
var _address := ""
var _port := 24567
var _suspended := false
var _disconnect_deadline := 0.0
var _reconnect_deadline := 0.0
var _next_reconnect := 0.0
var _handshakes: Dictionary = {}
var _rates: Dictionary = {}
var _action_cache: Dictionary = {}
var _pending_action: Dictionary = {}
var _pending_sent := 0.0
var _pending_retries := 0
var _action_serial := 0
var _ai_due := 0.0
var _last_snapshot_seq := -1
var _last_snapshot_hash := ""
var _closing := false

func _ready() -> void:
	multiplayer.allow_object_decoding = false
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected_to_server)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)

func _process(_delta: float) -> void:
	var now := _now()
	# Keep heartbeats flowing while an idempotent action request is retried.
	if mode == "cloud" and not cloud_room_id.is_empty() and not _cloud_polling and now >= _cloud_poll_due and (state.is_empty() or int(state.get("winner", -1)) == -1):
		_cloud_poll_due = now + (0.35 if connected and not state.is_empty() else 1.5)
		_cloud_poll()
	if mode == "solo" and not debug_console_open and not debug_ai_paused and _engine != null and int(_engine.state.get("winner", -1)) == -1:
		if ((_engine.state.has("mulligan") and not _engine.state.mulligan.confirmed[1]) or (not _engine.state.has("mulligan") and int(_engine.state.get("pending_choice", {}).get("owner", _engine.state.get("active_player", 0))) == 1)) and now >= _ai_due:
			_ai_due = now + 0.55
			var command: Dictionary = _engine.ai_action(1)
			if command.is_empty():
				command = {"type": "end_turn"}
			var error: String = _engine.apply_action(1, command)
			if not error.is_empty():
				_engine.apply_action(1, {"type": "end_turn"})
			_refresh_views()
	if mode == "host":
		for peer_id in _handshakes.keys():
			if now > float(_handshakes[peer_id]):
				_reject_peer(int(peer_id), "连接准备超时，请重新加入。")
		if _suspended and now >= _disconnect_deadline and _engine != null:
			_expire_disconnect()
	if mode == "client" and not connected and not _resume_token.is_empty() and _reconnect_deadline > 0.0:
		if now >= _reconnect_deadline:
			_reconnect_deadline = 0.0
			_pending_action.clear()
			if not state.is_empty():
				state["winner"] = 3
				state["suspended"] = false
				state_changed.emit()
			_set_status("无法恢复房主连接，对局已中止")
		elif now >= _next_reconnect:
			_next_reconnect = now + 3.0
			reconnect_game()
	if mode == "client" and connected and not _pending_action.is_empty() and now - _pending_sent >= 3.0:
		if _pending_retries < 2:
			_pending_retries += 1
			_pending_sent = now
			_action_request.rpc_id(1, _pending_action)
		else:
			_pending_action.clear()
			_sync_request.rpc_id(1, {"match_id": _match_id})
			notice.emit("行动回执超时，正在同步局面。")

func start_solo(deck: Array, keyword_defs: Array) -> String:
	var prepared := _prepare_deck(deck, keyword_defs)
	var hq := _prepare_headquarters(headquarters, keyword_defs)
	if not hq.ok: prepared=hq
	if not prepared.ok:
		return prepared.error
	leave_game()
	mode = "solo"
	local_player = 0
	_engine = Battle.new()
	var error: String = _engine.setup(prepared.cards, prepared.cards, randi(),[hq.card,hq.card],true)
	if not error.is_empty():
		leave_game()
		return error
	connected = true
	_ai_due = _now() + 0.55
	var selected := DeckRules.factions(prepared.sources,faction_catalog,main_faction_id,"",true)
	_match_sins = [main_sin,main_sin]
	_match_names = [commander_name,"训练 AI"]
	_match_factions = [selected.get("main_faction_id",""),selected.get("main_faction_id","")]
	_set_status("单人演练 · AI 使用你的同一副牌组")
	_refresh_views()
	return ""

func host_game(deck: Array, keyword_defs: Array, port: int = 24567) -> Error:
	var prepared := _prepare_deck(deck, keyword_defs)
	var hq := _prepare_headquarters(headquarters, keyword_defs)
	if not hq.ok: prepared=hq
	if not prepared.ok:
		notice.emit(prepared.error)
		return ERR_INVALID_DATA
	if port < 1024 or port > 65535:
		notice.emit("端口必须介于 1024 和 65535。")
		return ERR_INVALID_PARAMETER
	leave_game()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, 2)
	if error != OK:
		notice.emit("无法建立房间，请检查端口是否被占用。")
		return error
	mode = "host"
	local_player = 0
	_port = port
	_deck = prepared.sources
	_headquarters_source = hq.source
	_keywords = prepared.keywords
	_match_sins[0] = main_sin
	_match_names[0] = commander_name
	_match_factions[0] = DeckRules.factions(prepared.sources,faction_catalog,main_faction_id,"",true).get("main_faction_id","")
	_match_id = _random_token()
	multiplayer.multiplayer_peer = peer
	_set_status("房间已建立 · UDP %d · 等待对手" % port)
	return OK

func join_game(address: String, deck: Array, keyword_defs: Array, port: int = 24567) -> Error:
	var prepared := _prepare_deck(deck, keyword_defs)
	var hq := _prepare_headquarters(headquarters, keyword_defs)
	if not hq.ok: prepared=hq
	if not prepared.ok:
		notice.emit(prepared.error)
		return ERR_INVALID_DATA
	if address.strip_edges().is_empty() or address.length() > 253 or port < 1024 or port > 65535:
		return ERR_INVALID_PARAMETER
	leave_game()
	mode = "client"
	local_player = 1
	_deck = prepared.sources
	_headquarters_source = hq.source
	_keywords = prepared.keywords
	_address = address.strip_edges()
	_port = port
	return _connect_peer()

func reconnect_game() -> Error:
	if mode == "cloud":
		_cloud_poll_due = 0.0
		return OK
	if mode != "client" or _resume_token.is_empty() or connected:
		return ERR_UNAVAILABLE
	return _connect_peer()

func submit_action(action: Dictionary) -> void:
	if spectating: return
	if debug_console_open: return
	var command := _normalize_action(action)
	if command.is_empty():
		notice.emit("无效的行动格式。")
		return
	if state.is_empty() or not connected or _suspended or bool(state.get("suspended", false)):
		notice.emit("等待连接与对局恢复后才能行动。")
		return
	if mode == "cloud":
		_cloud_submit(command)
		return
	if mode == "solo":
		var previous_sequence: int = _engine.state.get("state_seq", 0)
		var error: String = _engine.apply_action(local_player, command)
		if not error.is_empty():
			notice.emit(error)
		if error.is_empty() or int(_engine.state.get("state_seq", 0)) != previous_sequence:
			_ai_due = _now() + 0.55
			_refresh_views()
		return
	if mode != "host" and mode != "client":
		return
	if mode == "client" and not _pending_action.is_empty():
		notice.emit("上一行动正在确认中。")
		return
	_action_serial += 1
	var message := {"match_id": _match_id, "action_id": "%s-%d" % [_random_token().substr(0, 24), _action_serial], "expected_state_seq": int(state.get("state_seq", 0)), "command": command}
	if mode == "host":
		_process_action(0, message)
	else:
		_pending_action = message
		_pending_sent = _now()
		_pending_retries = 0
		_action_request.rpc_id(1, message)

func leave_game() -> void:
	debug_console_open=false;debug_ai_paused=false;debug_session.undo_states.clear()
	_emote_seen=0;_emote_cooldowns.clear();_emote_inflight=0
	if mode == "cloud" and is_instance_valid(_cloud_store) and not cloud_room_id.is_empty():
		_cloud_store.request("/v1/rooms/" + cloud_room_id + ("/unwatch" if spectating else "/leave"), HTTPClient.METHOD_POST, {})
	spectating = false
	_cloud_epoch += 1
	_cloud_store = null
	cloud_room_id = ""
	cloud_room_code = ""
	_cloud_polling = false
	_cloud_pending = false
	_closing = true
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = "menu"
	connected = false
	state = {}
	_engine = null
	_deck.clear()
	_keywords.clear()
	_remote_peer = 0
	_match_id = ""
	_resume_token = ""
	_suspended = false
	_disconnect_deadline = 0.0
	_reconnect_deadline = 0.0
	_handshakes.clear()
	_rates.clear()
	_action_cache.clear()
	_pending_action.clear()
	_last_snapshot_seq = -1
	_last_snapshot_hash = ""
	_closing = false
	_set_status("尚未开始对局")
	state_changed.emit()

func start_cloud(api_store: Node, deck_refs: Array, room_id: String = "", hq_ref: Variant = null) -> Error:
	if deck_refs.size() != DeckRules.DECK_SIZE or not is_instance_valid(api_store):
		notice.emit("中央对局需要 40 张已上传服务器的卡牌引用。")
		return ERR_INVALID_DATA
	leave_game()
	mode = "cloud"
	_cloud_store = api_store
	var epoch := _cloud_epoch
	_set_status("正在连接独立权威对局服务器…")
	var route := "/v1/rooms" if room_id.is_empty() else "/v1/rooms/" + room_id.uri_encode() + "/join"
	var body := {"request_id": _cloud_uuid(), "deck": deck_refs}
	if hq_ref!=null: body["headquarters"]=hq_ref
	var chosen_sin: Variant = api_store.get("main_sin")
	if chosen_sin != null and SinCatalog.valid(chosen_sin): body["main_sin"] = chosen_sin
	var chosen_ally: Variant = api_store.get("ally_sin")
	if chosen_ally is String: body["ally_sin"] = chosen_ally
	var chosen_faction: Variant = api_store.get("main_faction_id")
	if chosen_faction is String and not chosen_faction.is_empty(): body["main_faction_id"] = chosen_faction
	var result: Dictionary = await api_store.request(route, HTTPClient.METHOD_POST, body)
	if epoch != _cloud_epoch or mode != "cloud":
		# A cancelled create/join can already have assigned a server-side seat.
		var late_data = result.get("data", {})
		if result.get("ok", false) and late_data is Dictionary and late_data.get("room_id") is String and is_instance_valid(api_store):
			var late_room: String = late_data.room_id
			if not late_room.is_empty() and (mode != "cloud" or cloud_room_id != late_room):
				api_store.request("/v1/rooms/" + late_room.uri_encode() + "/leave", HTTPClient.METHOD_POST, {})
		return ERR_SKIP
	if not result.get("ok", false):
		var message := str(result.get("error", "无法连接云端房间。"))
		leave_game()
		notice.emit(message)
		return ERR_CANT_CONNECT
	if not _cloud_apply(result.get("data", {})):
		leave_game()
		notice.emit("服务器返回了无效房间。")
		return ERR_INVALID_DATA
	_cloud_poll_due = _now() + 0.25
	return OK

func watch_cloud(api_store: Node, room_id: String, followed_player: int) -> Error:
	if not is_instance_valid(api_store) or room_id.is_empty() or followed_player not in [0,1]: return ERR_INVALID_PARAMETER
	leave_game()
	mode = "cloud"
	spectating = true
	local_player = followed_player
	_cloud_store = api_store
	_cloud_pending = true
	var epoch := _cloud_epoch
	_set_status("正在连接观战…")
	var result: Dictionary = await api_store.request("/v1/rooms/"+room_id.uri_encode()+"/watch",HTTPClient.METHOD_POST,{"seat":followed_player})
	if epoch != _cloud_epoch or mode != "cloud":
		var late: Variant = result.get("data",{})
		if result.get("ok",false) and late is Dictionary and late.get("room_id") is String and is_instance_valid(api_store):
			if mode!="cloud" or cloud_room_id!=late.room_id: api_store.request("/v1/rooms/"+str(late.room_id).uri_encode()+"/unwatch",HTTPClient.METHOD_POST,{})
		return ERR_SKIP
	_cloud_pending = false
	if not result.get("ok",false) or not _cloud_apply(result.get("data",{})):
		var message := str(result.get("error","无法加入观战。"))
		leave_game()
		notice.emit(message)
		return ERR_CANT_CONNECT
	_cloud_poll_due = _now()+0.35
	return OK

func _cloud_poll() -> void:
	if not is_instance_valid(_cloud_store): return
	_cloud_polling = true
	var epoch := _cloud_epoch
	var result: Dictionary = await _cloud_store.request("/v1/rooms/" + cloud_room_id + "/state")
	if epoch != _cloud_epoch or mode != "cloud": return
	_cloud_polling = false
	if result.get("ok", false) and _cloud_apply(result.get("data", {})):
		return
	var changed := connected
	connected = false
	if not state.is_empty(): state["suspended"] = true
	var message := "同步暂时失败，正在重试。"
	if int(result.get("code",0)) in [401,403]: message="登录或房间权限已失效，请重新登录。"
	elif not str(result.get("error","")).is_empty(): message += " " + str(result.error)
	if int(result.get("code", 0)) in [404, 410]:
		message = "云端房间已结束或过期。"
		if not state.is_empty(): state["winner"] = 3
		_cloud_poll_due = _now() + 10.0
	if status != message: _set_status(message)
	if changed: state_changed.emit()

func _cloud_apply(payload) -> bool:
	if not payload is Dictionary or not payload.get("room_id") is String or not payload.get("code") is String or not payload.get("status") is String:
		return false
	var data: Dictionary = Runtime._normalized(payload)
	if not data.get("local_player") is int or data.local_player not in [0, 1] or data.get("protocol_version") != "cloud-1": return false
	if bool(data.get("spectator",false)) != spectating: return false
	if spectating and (data.get("followed_player") != local_player or data.local_player != local_player): return false
	if not cloud_room_id.is_empty() and cloud_room_id != data.room_id: return false
	var view = data.get("state")
	if view != null and (not view is Dictionary or not _valid_view(view, data.local_player)): return false
	_receive_cloud_emotes(data)
	if view is Dictionary and not state.is_empty() and int(view.state_seq) < int(state.get("state_seq",0)): return true
	var was_connected := connected
	connected = true
	cloud_room_id = data.room_id
	cloud_room_code = data.code
	local_player = data.local_player
	var changed := not was_connected
	if view is Dictionary:
		if state.is_empty() or int(view.state_seq) > int(state.get("state_seq", -1)) or bool(state.get("suspended", false)) != bool(view.get("suspended", false)):
			state = view.duplicate(true)
			changed = true
	var new_status := "云端房间 %s · 独立服务器裁定" % cloud_room_code
	if data.status in ["waiting", "starting"]: new_status = "云端房间 %s · 等待对手" % cloud_room_code
	elif data.status == "suspended": new_status = "云端房间 %s · 对手离线，等待恢复" % cloud_room_code
	elif data.status in ["ended", "aborted", "closed"]: new_status = "云端房间 %s · 对局已结束" % cloud_room_code
	if spectating:
		var followed := str(state.get("players",[{},{}])[local_player].get("commander_name","指挥官"))
		new_status = "观战 · " + followed + (" · 对局已结束" if data.status in ["ended","aborted","closed"] else " · 等待玩家重连" if data.status=="suspended" else "")
	if status != new_status: _set_status(new_status)
	if changed: state_changed.emit()
	return true

func _cloud_submit(command: Dictionary) -> void:
	if spectating: return
	if _cloud_pending:
		notice.emit("上一行动正在等待服务器确认。")
		return
	if not is_instance_valid(_cloud_store): return
	_cloud_pending = true
	var epoch := _cloud_epoch
	var payload := {"action_id": _cloud_uuid(), "expected_state_seq": int(state.get("state_seq", 0)), "command": command}
	var result: Dictionary = {}
	for attempt in 3:
		result = await _cloud_store.request("/v1/rooms/" + cloud_room_id + "/actions", HTTPClient.METHOD_POST, payload)
		if epoch != _cloud_epoch or mode != "cloud": return
		if result.get("ok", false) or int(result.get("code", 0)) in [400, 401, 403, 404, 409, 410, 422, 429]: break
		if attempt < 2: await get_tree().create_timer(0.7).timeout
		if epoch != _cloud_epoch or mode != "cloud": return
	_cloud_pending = false
	if result.get("ok", false):
		_cloud_apply(result.get("data", {}))
		var action_result: Dictionary = result.get("data", {}).get("action_result", {})
		if not action_result.get("accepted", false):
			var message := str(action_result.get("message", ""))
			notice.emit("行动未执行：" + (message if not message.is_empty() else str(action_result.get("code", "服务器拒绝"))))
	else:
		notice.emit(str(result.get("error", "行动确认失败，正在重新同步。")))
	_cloud_poll_due = 0.0

func _cloud_uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var encoded := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [encoded.substr(0, 8), encoded.substr(8, 4), encoded.substr(12, 4), encoded.substr(16, 4), encoded.substr(20, 12)]

func _connect_peer() -> Error:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(_address, _port)
	if error != OK:
		_set_status("无法建立连接，请检查房主地址和端口")
		return error
	multiplayer.multiplayer_peer = peer
	_set_status("正在连接 %s:%d…" % [_address, _port])
	return OK

func _connected_to_server() -> void:
	if mode != "client":
		return
	_set_status("连接成功，房主正在校验并冻结牌组…")
	var message := {"protocol": PROTOCOL, "resume_token": _resume_token, "match_id": _match_id, "deck": _deck if _resume_token.is_empty() else [], "keywords": _keywords if _resume_token.is_empty() else []}
	message["main_sin"] = main_sin
	message["ally_sin"] = ally_sin
	if not main_faction_id.is_empty(): message["main_faction_id"] = main_faction_id
	if _resume_token.is_empty() and not _headquarters_source.is_empty(): message["headquarters"]=_headquarters_source
	message["commander_name"] = commander_name.left(32)
	_hello.rpc_id(1, message)

func _connection_failed() -> void:
	if mode == "client":
		connected = false
		_set_status("连接失败，请检查房主地址、防火墙和 UDP 端口")

func _server_disconnected() -> void:
	if _closing or mode != "client":
		return
	connected = false
	if _resume_token.is_empty():
		_set_status("房主关闭了连接")
		return
	_reconnect_deadline = _now() + GRACE_SECONDS
	_next_reconnect = _now() + 1.0
	if not state.is_empty():
		state["suspended"] = true
		state_changed.emit()
	_set_status("房主连接已断开，30 秒内尝试恢复…")

func _peer_connected(peer_id: int) -> void:
	if mode == "host":
		_handshakes[peer_id] = _now() + 10.0

func _peer_disconnected(peer_id: int) -> void:
	_handshakes.erase(peer_id)
	_rates.erase(peer_id)
	if mode != "host" or peer_id != _remote_peer or _closing:
		return
	_remote_peer = 0
	connected = false
	if _engine != null and int(_engine.state.get("winner", -1)) == -1:
		_suspended = true
		_disconnect_deadline = _now() + GRACE_SECONDS
		_engine.state["state_seq"] += 1
		_set_status("对手断线，暂停对局并等待重连（30 秒）")
		_refresh_views()

@rpc("any_peer", "call_remote", "reliable")
func _hello(message: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if mode != "host" or not _handshakes.has(sender) or not _rate_ok(sender):
		return
	var fields := ["protocol", "resume_token", "match_id", "deck", "keywords"]
	if message.has("main_sin"): fields.append("main_sin")
	if message.has("ally_sin"): fields.append("ally_sin")
	if message.has("main_faction_id"): fields.append("main_faction_id")
	if message.has("headquarters"): fields.append("headquarters")
	if message.has("commander_name"): fields.append("commander_name")
	if not message.get("commander_name","") is String or str(message.get("commander_name","")).length()>32:
		_reject_peer(sender,"昵称格式不正确。")
		return
	if not _safe_message(message) or not _exact_keys(message, fields) or not message.get("main_faction_id", "") is String or not SinCatalog.valid(message.get("main_sin", "")) or not SinCatalog.valid(message.get("ally_sin", "")):
		_reject_peer(sender, "房间请求格式不正确。")
		return
	if message.protocol != PROTOCOL or not message.resume_token is String or not message.match_id is String or not message.deck is Array or not message.keywords is Array:
		_reject_peer(sender, "游戏协议不一致，请使用相同版本。")
		return
	if not message.resume_token.is_empty():
		if _engine == null or message.match_id != _match_id or message.resume_token != _resume_token or _remote_peer != 0:
			_reject_peer(sender, "重连身份失效或该席位已连接。")
			return
		if _suspended and _now() >= _disconnect_deadline:
			_expire_disconnect()
		_remote_peer = sender
		_handshakes.erase(sender)
		connected = true
		if _suspended:
			_suspended = false
			_engine.state["state_seq"] += 1
		_set_status("局域网对局 · 对手已重连")
		_welcome.rpc_id(sender, {"protocol": PROTOCOL, "match_id": _match_id, "resume_token": _resume_token})
		_refresh_views()
		return
	if _engine != null or _remote_peer != 0:
		_reject_peer(sender, "房间已开始或已有对手。")
		return
	var merged := _merge_keywords(_keywords, message.keywords)
	if not merged.ok:
		_reject_peer(sender, merged.error)
		return
	var own := _prepare_deck(_deck, merged.keywords)
	var other := _prepare_deck(message.deck, merged.keywords, str(message.get("main_sin","")), str(message.get("ally_sin","")))
	var own_hq := _prepare_headquarters(_headquarters_source,merged.keywords)
	var other_hq := _prepare_headquarters(message.get("headquarters",{}),merged.keywords)
	var selection := DeckRules.factions(message.deck,faction_catalog,str(message.get("main_faction_id","")),"",true)
	if not str(selection.get("error","")).is_empty():
		_reject_peer(sender,str(selection.error))
		return
	if not own.ok or not other.ok or not own_hq.ok or not other_hq.ok:
		_reject_peer(sender, "牌组校验失败：需要 40 张合法卡牌，携带数量须符合稀有度上限。")
		return
	var next_engine = Battle.new()
	var error: String = next_engine.setup(own.cards, other.cards, randi(),[own_hq.card,other_hq.card],true)
	if not error.is_empty():
		_reject_peer(sender, "牌组无法用于此规则版本。")
		return
	_engine = next_engine
	_match_sins[1] = str(message.get("main_sin", "")) if message.get("main_sin") is String else ""
	_match_factions[1] = selection.main_faction_id
	_match_names[1] = str(message.get("commander_name","对方指挥官"))
	_keywords = merged.keywords.duplicate(true)
	_remote_peer = sender
	_resume_token = _random_token()
	_handshakes.erase(sender)
	connected = true
	_set_status("局域网对局 · 房主裁定")
	_welcome.rpc_id(sender, {"protocol": PROTOCOL, "match_id": _match_id, "resume_token": _resume_token})
	_refresh_views()

@rpc("authority", "call_remote", "reliable")
func _welcome(message: Dictionary) -> void:
	if mode != "client" or multiplayer.get_remote_sender_id() != 1:
		return
	if not _safe_message(message) or not _exact_keys(message, ["protocol", "match_id", "resume_token"]) or message.protocol != PROTOCOL or not message.match_id is String or not message.resume_token is String:
		return
	if message.match_id.length() != 64 or message.resume_token.length() != 64:
		return
	if not _match_id.is_empty() and _match_id != message.match_id:
		return
	_match_id = message.match_id
	_resume_token = message.resume_token
	_reconnect_deadline = 0.0
	connected = true
	_set_status("局域网对局 · 已连接房主")
	if not _pending_action.is_empty():
		_pending_sent = _now()
		_pending_retries = 0
		_action_request.rpc_id(1, _pending_action)

@rpc("any_peer", "call_remote", "reliable")
func _action_request(message: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if mode != "host" or sender != _remote_peer or not _rate_ok(sender):
		return
	_process_action(1, message)

func _process_action(player: int, message: Dictionary) -> void:
	if not _safe_message(message) or not _exact_keys(message, ["match_id", "action_id", "expected_state_seq", "command"]):
		return
	if message.match_id != _match_id or not message.action_id is String or message.action_id.is_empty() or message.action_id.length() > 64 or not message.expected_state_seq is int or not message.command is Dictionary:
		return
	var command := _normalize_action(message.command)
	if command.is_empty():
		_send_action_result(player, {"action_id": message.action_id, "accepted": false, "error": "INVALID_MESSAGE"})
		return
	var key := "%d:%s" % [player, message.action_id]
	var fingerprint := JSON.stringify({"seq": message.expected_state_seq, "command": command})
	if _action_cache.has(key):
		var previous: Dictionary = _action_cache[key]
		if previous.fingerprint != fingerprint:
			_send_action_result(player, {"action_id": message.action_id, "accepted": false, "error": "ACTION_ID_CONFLICT"})
		else:
			_send_action_result(player, previous.result)
			_send_view(player)
		return
	var error := ""
	var previous_sequence := -1 if _engine == null else int(_engine.state.get("state_seq", 0))
	if _engine == null:
		error = "MATCH_NOT_STARTED"
	elif _suspended:
		error = "MATCH_SUSPENDED"
	elif int(_engine.state.get("winner", -1)) != -1:
		error = "MATCH_ENDED"
	elif message.expected_state_seq != int(_engine.state.get("state_seq", 0)) and not (command.type=="mulligan" and message.expected_state_seq<int(_engine.state.state_seq) and _engine.state.has("mulligan") and not _engine.state.mulligan.confirmed[player]):
		error = "STALE_STATE"
	else:
		error = _engine.apply_action(player, command)
	var result := {"action_id": message.action_id, "accepted": error.is_empty(), "error": error}
	_action_cache[key] = {"fingerprint": fingerprint, "result": result}
	_send_action_result(player, result)
	# A rule-budget fault rejects the action but commits an aborted lifecycle state.
	# Both peers must receive that result, including the non-submitting player.
	if error.is_empty() or (_engine != null and int(_engine.state.get("state_seq", 0)) != previous_sequence):
		_refresh_views()
	else:
		_send_view(player)

func _send_action_result(player: int, result: Dictionary) -> void:
	if player == 0:
		if not result.accepted:
			notice.emit("行动未执行：" + str(result.error))
	elif _remote_peer != 0:
		_action_result.rpc_id(_remote_peer, result)

@rpc("authority", "call_remote", "reliable")
func _action_result(result: Dictionary) -> void:
	if mode != "client" or multiplayer.get_remote_sender_id() != 1 or not _safe_message(result) or not _exact_keys(result, ["action_id", "accepted", "error"]):
		return
	if not result.action_id is String or not result.accepted is bool or not result.error is String:
		return
	if _pending_action.get("action_id", "") == result.action_id:
		_pending_action.clear()
	if not result.accepted:
		notice.emit("行动未执行：" + result.error.substr(0, 200))

@rpc("any_peer", "call_remote", "reliable")
func _sync_request(message: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if mode == "host" and sender == _remote_peer and _rate_ok(sender) and _exact_keys(message, ["match_id"]) and message.match_id == _match_id:
		_send_view(1)

func _refresh_views() -> void:
	_send_view(0)
	if mode == "host" and _remote_peer != 0:
		_send_view(1)

func _send_view(player: int) -> void:
	if _engine == null:
		return
	# Never send engine.state, registry, RNG, or the rival deck to the client.
	var view: Dictionary = _wire_value(_engine.view_for(player))
	for owner in 2:
		view.players[owner]["main_faction_id"] = _match_factions[owner]
		view.players[owner]["main_sin"] = _match_sins[owner]
		view.players[owner]["commander_name"] = _match_names[owner]
	view["suspended"] = _suspended
	if player == 0:
		state = view
		state_changed.emit()
	elif mode == "host" and _remote_peer != 0:
		var message := {"match_id": _match_id, "state": view}
		if _safe_message(message):
			_snapshot.rpc_id(_remote_peer, message)
		else:
			_abort_network_match()

func _expire_disconnect() -> void:
	_suspended = false
	_engine.state["winner"] = 0
	_engine.state["state_seq"] += 1
	_engine.state["log"].append("对手断线超过 30 秒，房主获胜。")
	_set_status("对手断线超时，你获胜")
	_refresh_views()

func _abort_network_match() -> void:
	_engine.state["winner"] = 3
	_engine.state["state_seq"] += 1
	_suspended = false
	state = _wire_value(_engine.view_for(0))
	state["suspended"] = false
	_set_status("局面超过传输预算，对局中止")
	notice.emit(status)
	state_changed.emit()
	if _remote_peer != 0:
		_match_aborted.rpc_id(_remote_peer, {"match_id": _match_id, "state_seq": int(_engine.state.state_seq)})

@rpc("authority", "call_remote", "reliable")
func _match_aborted(message: Dictionary) -> void:
	if mode != "client" or multiplayer.get_remote_sender_id() != 1 or not _exact_keys(message, ["match_id", "state_seq"]):
		return
	if message.match_id != _match_id or not message.state_seq is int or message.state_seq < _last_snapshot_seq:
		return
	_pending_action.clear()
	if not state.is_empty():
		state["winner"] = 3
		state["suspended"] = false
		state["state_seq"] = message.state_seq
		_last_snapshot_seq = message.state_seq
		_last_snapshot_hash = JSON.stringify(state).sha256_text()
		state_changed.emit()
	_set_status("局面超过传输预算，对局中止")

@rpc("authority", "call_remote", "reliable")
func _snapshot(message: Dictionary) -> void:
	if mode != "client" or multiplayer.get_remote_sender_id() != 1 or not _safe_message(message) or not _exact_keys(message, ["match_id", "state"]):
		return
	if message.match_id != _match_id or not message.state is Dictionary:
		return
	var view: Dictionary = message.state
	if not _valid_view(view, local_player):
		notice.emit("房主发送了无效的局面。")
		return
	var sequence: int = view.state_seq
	if sequence < _last_snapshot_seq:
		return
	var digest := JSON.stringify(view).sha256_text()
	if sequence == _last_snapshot_seq and digest != _last_snapshot_hash:
		notice.emit("相同序号的局面不一致，拒绝更新。")
		return
	_last_snapshot_seq = sequence
	_last_snapshot_hash = digest
	state = view.duplicate(true)
	state_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _room_error(message: String) -> void:
	if mode == "client" and multiplayer.get_remote_sender_id() == 1:
		_set_status(message.substr(0, 200))
		notice.emit(status)

func _reject_peer(peer_id: int, message: String) -> void:
	_handshakes.erase(peer_id)
	_room_error.rpc_id(peer_id, message.substr(0, 200))
	# Let the reliable rejection flush before closing this peer only.
	var current_peer = multiplayer.multiplayer_peer
	get_tree().create_timer(0.2).timeout.connect(func():
		if is_instance_valid(self) and mode == "host" and multiplayer.multiplayer_peer == current_peer:
			current_peer.disconnect_peer(peer_id)
	)

func _prepare_deck(deck: Array, keyword_defs: Array, primary: Variant = null, secondary: Variant = null) -> Dictionary:
	if not SinCatalog.valid(main_sin): return {"ok":false,"error":"罪孽选择无效。"}
	if deck.size() != DeckRules.DECK_SIZE or not _safe_message({"deck": deck, "keywords": keyword_defs}):
		return {"ok": false, "error": "牌组必须恰有 40 张牌，且内容不能超过 1 MiB。"}
	var merged := _merge_keywords(Runtime.builtin_keywords(), keyword_defs)
	if not merged.ok:
		return merged
	var cards: Array = []
	var sources: Array = []
	var composition := DeckRules.composition(deck, faction_catalog, main_sin if primary==null else str(primary), ally_sin if secondary==null else str(secondary))
	if not composition.error.is_empty(): return {"ok":false,"error":composition.error}
	var copy_error := DeckRules.check_copies(deck)
	if not copy_error.is_empty(): return {"ok":false, "error":copy_error}
	for entry in deck:
		if not entry is Dictionary:
			return {"ok": false, "error": "牌组包含无效条目。"}
		var source = entry.get("source", entry.get("definition", entry))
		if not source is Dictionary:
			return {"ok": false, "error": "卡牌缺少来源定义。"}
		var compiled: Dictionary = Runtime.compile_card(source, merged.keywords)
		if not compiled.get("ok", false):
			return {"ok": false, "error": "卡牌校验失败：" + str(compiled.get("error", "无效定义"))}
		cards.append(compiled)
		var artwork := str(entry.get("art_id", ""))
		if CardArtCache.valid_id(artwork): compiled["art_id"] = artwork
		var token_art: Variant = entry.get("token_art_ids", {})
		if not CardArtCache.valid_token_art_ids(token_art, source): return {"ok":false,"error":"衍生卡卡面引用无效。"}
		compiled["token_art_ids"] = token_art.duplicate(true)
		var envelope := {"definition":source.duplicate(true)}
		var identity: Dictionary=_card_identity(entry)
		if not identity.ok: return identity
		if not identity.ref.is_empty():
			compiled["telemetry_ref"]=identity.ref
			envelope["telemetry_ref"]=identity.ref
		if CardArtCache.valid_id(artwork): envelope["art_id"] = artwork
		if not token_art.is_empty(): envelope["token_art_ids"] = token_art.duplicate(true)
		sources.append(envelope if envelope.size() > 1 else source.duplicate(true))
	var selection := DeckRules.factions(sources, faction_catalog, main_faction_id, "", true)
	if not selection.error.is_empty(): return {"ok":false, "error":selection.error}
	return {"ok": true, "error": "", "cards": cards, "sources": sources, "keywords": merged.keywords}

func _prepare_headquarters(raw: Variant, keywords: Array) -> Dictionary:
	if not raw is Dictionary: return {"ok":false,"error":"总部格式无效。"}
	if raw.is_empty(): return {"ok":true,"card":{},"source":{}}
	var definition: Variant = raw.get("source",raw.get("definition",{}))
	if not definition is Dictionary: return {"ok":false,"error":"总部定义无效。"}
	var compiled: Dictionary=Runtime.compile_card(definition,keywords)
	if not compiled.ok or compiled.definition.kind!="hq": return {"ok":false,"error":"总部卡校验失败。"}
	if raw.has("definition_hash") and raw.definition_hash!=compiled.definition_hash: return {"ok":false,"error":"总部版本不匹配。"}
	if raw.has("compiled_program_hash") and raw.compiled_program_hash!=compiled.compiled_program_hash: return {"ok":false,"error":"总部规则不匹配。"}
	var envelope := {"definition":definition.duplicate(true),"definition_hash":compiled.definition_hash,"compiled_program_hash":compiled.compiled_program_hash}
	var identity: Dictionary=_card_identity(raw)
	if not identity.ok: return identity
	if not identity.ref.is_empty():
		compiled["telemetry_ref"]=identity.ref
		envelope["telemetry_ref"]=identity.ref
	if CardArtCache.valid_id(str(raw.get("art_id",""))):
		compiled["art_id"]=raw.art_id
		envelope["art_id"]=raw.art_id
	var token_art: Variant = raw.get("token_art_ids", {})
	if not CardArtCache.valid_token_art_ids(token_art, definition): return {"ok":false,"error":"总部衍生卡卡面引用无效。"}
	compiled["token_art_ids"] = token_art.duplicate(true)
	if not token_art.is_empty(): envelope["token_art_ids"] = token_art.duplicate(true)
	return {"ok":true,"card":compiled,"source":envelope}

func _merge_keywords(first: Array, second: Array) -> Dictionary:
	if first.size() + second.size() > 1024:
		return {"ok": false, "error": "词条目录过大。"}
	var by_id: Dictionary = {}
	for definition in first + second:
		if not definition is Dictionary:
			return {"ok": false, "error": "词条定义格式错误。"}
		var validation: String = Runtime.validate_keyword(definition)
		if not validation.is_empty():
			return {"ok": false, "error": "词条校验失败。"}
		var key := "%s@%d" % [definition.id, int(definition.version)]
		var digest := _canonical(definition)
		if by_id.has(key) and _canonical(by_id[key]) != digest:
			return {"ok": false, "error": "双方存在同名同版本但内容不同的词条，请发布新版本。"}
		by_id[key] = definition.duplicate(true)
	var keys := by_id.keys()
	keys.sort()
	var result: Array = []
	for key in keys:
		result.append(by_id[key])
	return {"ok": true, "error": "", "keywords": result}

func _normalize_action(action: Dictionary) -> Dictionary:
	if not action.get("type") is String:
		return {}
	match action.type:
		"activate":
			if _exact_keys(action,["type","uid","ability_index"]) and action.uid is int and action.uid>0 and action.ability_index is int and action.ability_index>=0 and action.ability_index<=63: return action.duplicate()
		"mulligan":
			if not _exact_keys(action,["type","hand_ids"]) or not action.hand_ids is Array or action.hand_ids.size()>5: return {}
			var ids: Array=[]
			for id in action.hand_ids:
				if not _positive_id(id) or id in ids: return {}
				ids.append(id)
			return action.duplicate(true)
		"choose_card":
			if _exact_keys(action,["type","choice_id","option_index"]) and action.choice_id is String and action.choice_id.length() <= 64 and action.option_index is int and action.option_index >= 0 and action.option_index < 10: return action.duplicate()
		"choose_target":
			if _exact_keys(action, ["type", "choice_id", "target_uid"]) and action.choice_id is String and action.choice_id.length() <= 64 and action.target_uid is int and (action.target_uid > 0 or action.target_uid in [-101,-102,-1000]):
				return action.duplicate()
		"play":
			var allowed := ["type", "hand_id", "target_uid"] if action.has("target_uid") else ["type", "hand_id"]
			if action.has("position"): allowed.append("position")
			if not _exact_keys(action, allowed) or not _positive_id(action.get("hand_id")):
				return {}
			var command := {"type": "play", "hand_id": action.hand_id}
			if action.has("target_uid"):
				if not action.target_uid is int or action.target_uid < 1:
					return {}
				command["target_uid"] = action.target_uid
			if action.has("position"):
				if not action.position is int or action.position < 0 or action.position > 4: return {}
				command["position"] = action.position
			return command
		"move":
			var allowed := ["type", "uid", "position"] if action.has("position") else ["type", "uid"]
			if _exact_keys(action, allowed) and action.uid is int and action.uid > 0:
				if action.has("position") and (not action.position is int or action.position < 0 or action.position > 4): return {}
				return action.duplicate()
		"attack":
			if _exact_keys(action, ["type", "uid", "target_uid"]) and action.uid is int and action.uid > 0 and action.target_uid is int and (action.target_uid > 0 or action.target_uid == -1):
				return {"type": "attack", "uid": action.uid, "target_uid": action.target_uid}
		"end_turn", "concede":
			if _exact_keys(action, ["type"]):
				return {"type": action.type}
	return {}

func _positive_id(value) -> bool:
	return (value is int and value > 0) or (value is String and not value.is_empty() and value.length() <= 64)

func _valid_view(view: Dictionary, viewer: int) -> bool:
	if view.has("mulligan"):
		if not view.mulligan is Dictionary or not view.mulligan.get("confirmed") is Array or view.mulligan.confirmed.size()!=2: return false
		for value in view.mulligan.confirmed:
			if not value is bool:return false
	if not view.get("state_seq") is int or view.state_seq < 0 or not view.get("players") is Array or view.players.size() != 2 or not view.get("units") is Array:
		return false
	if not view.get("turn") is int or not view.get("active_player") is int or view.active_player not in [0, 1] or not view.get("winner") is int or view.winner not in [-1, 0, 1, 2, 3]:
		return false
	for slot in range(2):
		var player = view.players[slot]
		if not player is Dictionary or not player.get("hand") is Array or not player.get("deck") is Array:
			return false
		if not player.deck.is_empty() or (slot != viewer and not player.hand.is_empty()):
			return false
		for field in ["hp", "max_hp", "credits", "max_credits", "deck_count", "hand_count"]:
			if not player.get(field) is int:
				return false
	return true

func _safe_message(message: Dictionary) -> bool:
	var budget := [50000]
	return _safe_value(message, 0, budget) and var_to_bytes(message).size() <= MAX_PACKET_BYTES

func _wire_value(value):
	# GDScript's dot syntax can add StringName keys to local dictionaries. The wire
	# contract is plain JSON values; normalize trusted engine output before encoding.
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[str(key)] = _wire_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_wire_value(item))
		return result
	if value is StringName:
		return str(value)
	return value

func _safe_value(value, depth: int, budget: Array) -> bool:
	budget[0] -= 1
	if depth > 32 or budget[0] < 0:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_STRING:
			return value.length() <= 65536
		TYPE_ARRAY:
			if value.size() > 4096:
				return false
			for item in value:
				if not _safe_value(item, depth + 1, budget):
					return false
			return true
		TYPE_DICTIONARY:
			if value.size() > 4096:
				return false
			for key in value:
				if not key is String or key.length() > 128 or not _safe_value(value[key], depth + 1, budget):
					return false
			return true
	return false

func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true

func _rate_ok(peer_id: int) -> bool:
	var second := int(_now())
	var entry: Dictionary = _rates.get(peer_id, {"second": second, "count": 0})
	if entry.second != second:
		entry = {"second": second, "count": 0}
	entry.count += 1
	_rates[peer_id] = entry
	if entry.count > 60:
		_reject_peer(peer_id, "请求过于频繁，连接已关闭。")
	return entry.count <= 20

func _canonical(value) -> String:
	return Runtime.canonical(value)

func _random_token() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _set_status(value: String) -> void:
	status = value
	status_changed.emit()

func _card_identity(entry: Dictionary) -> Dictionary:
	var ref: Variant=entry.get("telemetry_ref",{})
	if not ref is Dictionary: return {"ok":false,"error":"卡牌来源标识无效。"}
	if ref.is_empty(): return {"ok":true,"ref":{}}
	var pattern:=RegEx.new();pattern.compile("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	if not _exact_keys(ref,["card_id","revision"]) or not ref.card_id is String or pattern.search(ref.card_id)==null or not (ref.revision is int or ref.revision is float) or not is_finite(float(ref.revision)) or float(ref.revision)!=floor(float(ref.revision)) or ref.revision<1:
		return {"ok":false,"error":"卡牌来源标识无效。"}
	return {"ok":true,"ref":{"card_id":ref.card_id,"revision":int(ref.revision)}}


func send_emote(id: String, point: Vector2=Vector2(-1,-1)) -> void:
	if spectating: return
	if not connected or state.is_empty() or int(state.get("winner",-1))!=-1 or not is_instance_valid(emote_service) or emote_service.entry(id).is_empty(): return
	if _emote_inflight>=4 or _now()-float(_emote_cooldowns.get(local_player,-10.0))<0.08: return
	_emote_cooldowns[local_player]=_now()
	if mode=="cloud":
		_emote_inflight+=1
		var serial := _cloud_epoch
		var payload := {"request_id":_cloud_uuid(),"emote_id":id}
		if _valid_emote_point(point): payload["point"]=[roundi(point.x*10000),roundi(point.y*10000)]
		var response: Dictionary=await _cloud_store.request("/v1/rooms/"+cloud_room_id+"/emotes",HTTPClient.METHOD_POST,payload)
		if serial!=_cloud_epoch: return
		_emote_inflight=maxi(0,_emote_inflight-1)
		if response.ok: _cloud_apply(response.data)
		else: notice.emit(str(response.get("error","表情发送失败")))
	elif mode=="client": _emote_request.rpc_id(1,_match_id,id,point)
	elif mode=="host": _broadcast_emote(local_player,id,point)
	else: emote_received.emit(local_player,id,point,_emote_scale(id))

func _receive_cloud_emotes(data: Dictionary) -> void:
	if not data.get("emote_events") is Array: return
	for event in data.emote_events.slice(0,64):
		if not event is Dictionary or not event.get("id") is int or not event.get("player") is int or event.player not in [0,1] or not event.get("emote_id") is String or event.emote_id.length()!=36: continue
		if event.id<=_emote_seen: continue
		_emote_seen=event.id
		var point := Vector2(-1,-1)
		if event.get("point") is Array and event.point.size()==2 and (event.point[0] is float or event.point[0] is int) and (event.point[1] is float or event.point[1] is int):
			var candidate := Vector2(event.point[0],event.point[1])/10000.0
			if _valid_emote_point(candidate): point=candidate
		emote_received.emit(event.player,event.emote_id,point,preload("res://scripts/ui/emote_cache.gd").entry_scale(event))

func _broadcast_emote(player: int, id: String, point: Vector2) -> void:
	if point!=Vector2(-1,-1) and not _valid_emote_point(point): return
	var size_scale := _emote_scale(id)
	emote_received.emit(player,id,point,size_scale)
	if _remote_peer>0: _emote_event.rpc_id(_remote_peer,_match_id,player,id,point,size_scale)

@rpc("any_peer","call_remote","reliable")
func _emote_request(match_id: String, id: String, point: Vector2) -> void:
	if mode!="host" or multiplayer.get_remote_sender_id()!=_remote_peer or match_id!=_match_id or not connected or state.is_empty() or int(state.get("winner",-1))!=-1: return
	if id.length()!=36 or not is_instance_valid(emote_service) or emote_service.entry(id).is_empty(): return
	if _now()-float(_emote_cooldowns.get(1,-10.0))<0.08: return
	if point!=Vector2(-1,-1) and not _valid_emote_point(point): return
	_emote_cooldowns[1]=_now();_broadcast_emote(1,id,point)

@rpc("authority","call_remote","reliable")
func _emote_event(match_id: String, player: int, id: String, point: Vector2, display_scale: float) -> void:
	if mode!="client" or multiplayer.get_remote_sender_id()!=1 or match_id!=_match_id or player not in [0,1] or id.length()!=36 or state.is_empty() or int(state.get("winner",-1))!=-1: return
	if point!=Vector2(-1,-1) and not _valid_emote_point(point): return
	emote_received.emit(player,id,point,preload("res://scripts/ui/emote_cache.gd").display_scale(display_scale))

func _emote_scale(id: String) -> float:
	return preload("res://scripts/ui/emote_cache.gd").entry_scale(emote_service.entry(id))

static func _valid_emote_point(point: Vector2) -> bool:
	return point.is_finite() and point.x>=0 and point.x<=1 and point.y>=0 and point.y<=1
