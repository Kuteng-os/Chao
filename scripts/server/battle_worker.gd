extends SceneTree
## Private stdin/stdout protocol. Only the authenticated Node supervisor owns this process.
## Card text is compiled as JSON DSL; no supplied scripts, expressions or resources execute.
const Runtime = preload("res://scripts/core/card_runtime.gd")
const Battle = preload("res://scripts/core/battle_engine.gd")
const MAX_BYTES := 4194304
var battle
var suspended := false
var telemetry_cursor := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var pending := PackedByteArray()
	while true:
		# Pipe reads are bounded byte reads, not readline; preserve UTF-8 across blocks.
		# The supervisor pads each JSON line with whitespace to a 1024-byte boundary.
		var chunk := OS.read_buffer_from_stdin(1024)
		if chunk.is_empty():
			break
		pending.append_array(chunk)
		if pending.size() > MAX_BYTES + 1024:
			break
		var newline := pending.find(10)
		while newline >= 0:
			var line := pending.slice(0, newline).get_string_from_utf8().strip_edges()
			pending = pending.slice(newline + 1)
			var parsed: Dictionary = Runtime.parse_json(line, MAX_BYTES)
			if not parsed.ok or not parsed.value is Dictionary:
				print(JSON.stringify({"id": -1, "ok": false, "error": "INVALID_MESSAGE"}))
			else:
				var request: Dictionary = parsed.value
				var result := _execute(request)
				result["id"] = request.get("id", -1)
				print(JSON.stringify(result))
			newline = pending.find(10)
	quit(0)

func _execute(request: Dictionary) -> Dictionary:
	if not request.get("id") is int or request.id < 1 or not request.get("command") is String:
		return _error("INVALID_MESSAGE")
	match request.command:
		"setup":
			var setup_keys := ["id", "command", "decks", "keywords", "seed"]
			if request.has("headquarters"): setup_keys.append("headquarters")
			if request.has("opening_redraw"):
				if not request.opening_redraw is bool: return _error("INVALID_MESSAGE")
				setup_keys.append("opening_redraw")
			if battle != null or not _keys(request, setup_keys): return _error("INVALID_MESSAGE")
			if not request.decks is Array or request.decks.size() != 2 or not request.keywords is Array or not request.seed is int: return _error("INVALID_MESSAGE")
			var keywords: Array = Runtime.builtin_keywords()
			for definition in request.keywords:
				if not definition is Dictionary or not Runtime.validate_keyword(definition).is_empty(): return _error("INVALID_KEYWORD")
				keywords.append(definition)
			var decks: Array = []
			var compiled_cache: Dictionary = {}
			for incoming in request.decks:
				if not incoming is Array or incoming.size() != DeckRules.DECK_SIZE: return _error("INVALID_DECK")
				var deck: Array = []
				for envelope in incoming:
					if not envelope is Dictionary: return _error("INVALID_DECK")
					var fields: Dictionary = envelope.duplicate()
					fields.erase("art_id")
					fields.erase("token_art_ids")
					fields.erase("telemetry_ref")
					if not _keys(fields, ["definition", "definition_hash", "compiled_program_hash"]) or not envelope.definition is Dictionary: return _error("INVALID_DECK")
					if envelope.has("art_id") and (not envelope.art_id is String or not CardArtCache.valid_id(envelope.art_id)): return _error("INVALID_DECK")
					var source_hash: String = Runtime.sha(envelope.definition)
					if source_hash != envelope.definition_hash: return _error("CARD_HASH_MISMATCH")
					if not compiled_cache.has(source_hash):
						var compiled: Dictionary = Runtime.compile_card(envelope.definition, keywords)
						if not compiled.ok: return _error("INVALID_CARD")
						compiled_cache[source_hash] = compiled
					var compiled: Dictionary = compiled_cache[source_hash].duplicate(true)
					if compiled.compiled_program_hash != envelope.compiled_program_hash: return _error("COMPILED_PROGRAM_MISMATCH")
					var token_art: Variant = envelope.get("token_art_ids", {})
					if not CardArtCache.valid_token_art_ids(token_art, envelope.definition): return _error("INVALID_DECK")
					compiled["token_art_ids"] = token_art.duplicate(true)
					if envelope.has("art_id"): compiled["art_id"] = envelope.art_id
					if envelope.has("telemetry_ref"): compiled["telemetry_ref"] = envelope.telemetry_ref
					deck.append(compiled)
				decks.append(deck)
			var headquarters := []
			var incoming_hqs: Variant = request.get("headquarters",[null,null])
			if not incoming_hqs is Array or incoming_hqs.size()!=2: return _error("INVALID_HEADQUARTERS")
			for envelope in incoming_hqs:
				if envelope == null:
					headquarters.append({})
					continue
				if not envelope is Dictionary or not envelope.get("definition") is Dictionary: return _error("INVALID_HEADQUARTERS")
				var hq: Dictionary = Runtime.compile_card(envelope.definition,keywords)
				if not hq.ok or hq.definition.kind!="hq" or hq.definition_hash!=envelope.get("definition_hash") or hq.compiled_program_hash!=envelope.get("compiled_program_hash"): return _error("INVALID_HEADQUARTERS")
				if envelope.has("art_id"):
					if not envelope.art_id is String or not CardArtCache.valid_id(envelope.art_id): return _error("INVALID_HEADQUARTERS")
					hq["art_id"]=envelope.art_id
				var token_art: Variant = envelope.get("token_art_ids", {})
				if not CardArtCache.valid_token_art_ids(token_art, envelope.definition): return _error("INVALID_HEADQUARTERS")
				hq["token_art_ids"] = token_art.duplicate(true)
				if envelope.has("telemetry_ref"): hq["telemetry_ref"]=envelope.telemetry_ref
				headquarters.append(hq)
			battle = Battle.new()
			var error: String = battle.setup(decks[0], decks[1], request.seed,headquarters,request.get("opening_redraw",false))
			if not error.is_empty():
				battle = null
				return _error("INVALID_DECK")
			return _snapshot(true, "")
		"action":
			if battle == null or not _keys(request, ["id", "command", "player", "action"]) or not request.player is int or request.player not in [0, 1] or not request.action is Dictionary: return _error("INVALID_MESSAGE")
			if suspended: return _snapshot(false, "MATCH_SUSPENDED")
			var error: String = battle.apply_action(request.player, request.action)
			return _snapshot(error.is_empty(), error)
		"pause":
			if battle == null or not _keys(request, ["id", "command", "paused"]) or not request.paused is bool: return _error("INVALID_MESSAGE")
			if suspended != request.paused and battle.state.winner == -1:
				suspended = request.paused
				battle.state.state_seq += 1
			return _snapshot(true, "")
		"finish":
			if battle == null or not _keys(request, ["id", "command", "winner", "reason"]) or not request.winner is int or request.winner not in [0, 1, 2, 3] or request.reason not in ["PLAYER_LEFT", "DISCONNECT_TIMEOUT", "BOTH_OFFLINE", "IDLE_TIMEOUT", "SERVER_ERROR"]: return _error("INVALID_MESSAGE")
			if battle.state.winner == -1:
				battle.state.winner = request.winner
				battle.state.state_seq += 1
				suspended = false
				battle.state.log.append("云端裁定：" + request.reason)
			return _snapshot(true, "")
	return _error("INVALID_MESSAGE")

func _snapshot(accepted: bool, error: String) -> Dictionary:
	var views: Array = []
	for player in 2:
		var view: Dictionary = battle.view_for(player)
		view["suspended"] = suspended
		views.append(view)
	var events: Array = battle.state.telemetry.slice(telemetry_cursor)
	telemetry_cursor = battle.state.telemetry.size()
	return {"ok": true, "result": {"telemetry": events, "telemetry_truncated": battle.state.telemetry_truncated, "first_player": battle.state.first_player, "accepted": accepted, "error": error, "state_seq": int(battle.state.state_seq), "winner": int(battle.state.winner), "views": views}}

func _keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true

func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}
