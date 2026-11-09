class_name AppStore
extends Node
signal deck_edited
signal changed
signal message(text: String)
## The online service is retired. This value only remains as the catalog scope key of existing profiles.
const DEFAULT_SERVER := "https://wzb.rainplay.cn:36410"
const BUNDLED_CATALOG := "res://data/catalog.json"
const GITHUB_PULL_INTERVAL_MS := 300000
const GITHUB_REPO := "https://github.com/xiangwu738-design/Chao"
const Runtime = preload("res://scripts/core/card_runtime.gd")
const SYNC_BYTES := 250000
var cards: Array = []
var keyword_definitions: Array = []
var deck_ids: Array = []
var factions: Dictionary = {}
var _faction_catalogs: Dictionary = {}
var _series_catalogs: Dictionary = {}
const CardSeries = preload("res://scripts/core/card_series.gd")

func series_catalog() -> Dictionary:
	return CardSeries.parse(_series_catalogs.get(_bound_server,{"current":2,"available":[1,2]}))

var headquarters_id := ""
var main_sin := ""
var ally_sin := ""
var main_faction_id := ""
var ally_faction_id := ""
var local_decks: Array = []
var active_deck_id := ""
var deck_name := "新牌组"
var deck_publish_pending: Dictionary = {}
var _deck_publish_busy := false
var settings := {"backend_url":DEFAULT_SERVER,"api_token":"","player_name":"指挥官","owner_id":""}
var online := false
var model_configured := false
var connection_note := "正在连接"
var profile_path := "user://profile.json"
var central_mode := false
var authenticated := false
var account_identity: Dictionary = {}
var _account_busy := false
var pending_sync: Dictionary = {}
var _refresh_running := false
var _refresh_elapsed := 0.0
var _refresh_serial := 0
var _context_epoch := 0
var _bound_server := ""
var _bound_token := ""
var _bound_owner := ""
var _credentials: Dictionary = {}
var _outbox: Dictionary = {}
var _keyword_archive: Dictionary = {}
var _catalogs: Dictionary = {}
var _content_catalogs: Dictionary = {}
var _sync_after: Dictionary = {}
var _draft_contexts: Dictionary = {}
var _load_failed := false
var bundled_ready := false
var catalog_version := 0
var catalog_etag := ""
var _bundled_version := 0
var _pull_running := false
var _pull_after := 0
var _sync_warning := ""
var _display_cache: Dictionary = {}
var _catalog_fingerprints: Dictionary = {}

func _ready() -> void:
	if not OS.get_environment("FRONTLINE_PROFILE_PATH").is_empty(): profile_path = OS.get_environment("FRONTLINE_PROFILE_PATH")
	keyword_definitions = Runtime.builtin_keywords()
	_bound_server = _server(str(settings.backend_url))
	_load_profile()
	settings.backend_url = DEFAULT_SERVER
	_bound_server = DEFAULT_SERVER
	CardArtCache.origin = _bound_server if not _bound_server.is_empty() else DEFAULT_SERVER
	CardArtCache.directory = profile_path.get_base_dir().path_join("card-art")
	_activate_factions()
	_infer_deck_factions()
	_remember_keywords(keyword_definitions, _bound_owner.is_empty())

func _server(value: String) -> String:
	var pattern := RegEx.new()
	pattern.compile("^(https?)://(\\[[0-9A-Fa-f:]+\\]|[A-Za-z0-9.-]+)(?::([0-9]{1,5}))?/?$")
	var found := pattern.search(value.strip_edges())
	if found == null: return ""
	var protocol := found.get_string(1)
	var host := found.get_string(2).to_lower()
	var port := found.get_string(3)
	if not port.is_empty() and (int(port) < 1 or int(port) > 65535): return ""
	if protocol == "http" and not host in ["localhost","127.0.0.1","[::1]"]: return ""
	if port == ("443" if protocol == "https" else "80"): port = ""
	return protocol + "://" + host + (":" + port if not port.is_empty() else "")

func _scope() -> String:
	return _bound_server + "|" + _bound_owner

func _stash_pending() -> void:
	if not pending_sync.is_empty():
		_outbox[str(pending_sync.get("server",_bound_server)) + "|" + str(pending_sync.get("owner_id",_bound_owner))] = pending_sync.duplicate(true)

func _ensure_context() -> void:
	var origin := _server(str(settings.backend_url))
	var token := str(settings.api_token)
	if origin == _bound_server and token == _bound_token: return
	_stash_pending()
	if not _bound_server.is_empty(): _credentials[_bound_server] = {"api_token":_bound_token,"owner_id":_bound_owner}
	if origin != _bound_server and (token == _bound_token or token.is_empty()):
		var saved: Dictionary = _credentials.get(origin,{})
		token = str(saved.get("api_token",""))
		settings.owner_id = str(saved.get("owner_id",""))
	else: settings.owner_id = ""
	_bound_server = origin
	CardArtCache.origin = origin if not origin.is_empty() else DEFAULT_SERVER
	_bound_token = token
	_bound_owner = str(settings.owner_id)
	settings.api_token = token
	_context_epoch += 1
	_refresh_serial += 1
	_refresh_running = false
	online = false
	authenticated = false
	account_identity = {}
	central_mode = false
	pending_sync = _outbox.get(_scope(),{}).duplicate(true)
	_activate_keywords()
	_activate_factions()

func _activate_factions() -> void:
	factions = FactionCatalog.parse(_faction_catalogs.get(_bound_server, []))
	FactionCatalog.entries = factions

func _infer_deck_factions() -> void:
	if not main_faction_id.is_empty() or deck_ids.is_empty(): return
	var selected := DeckRules.factions(deck_ids.map(func(id): return get_card(id)), factions, "", "", true)
	if selected.error.is_empty():
		main_faction_id = selected.main_faction_id
		ally_faction_id = selected.ally_faction_id

func deck_factions() -> Dictionary:
	if not _valid_deck_sins(main_sin, ally_sin): return {"error":"罪孽选择无效。"}
	var composition := deck_composition(true)
	if not composition.error.is_empty(): return composition
	return DeckRules.factions(deck_ids.map(func(id): return get_card(id)), factions, main_faction_id, ally_faction_id)

func deck_composition(complete := false) -> Dictionary:
	return DeckRules.composition(deck_ids.map(func(id): return get_card(id)), factions, main_sin, ally_sin, complete)

func select_deck_sins(primary: String, secondary: String) -> String:
	if primary.is_empty() or secondary.is_empty() or not _valid_deck_sins(primary, secondary): return "请选择两种不同的主罪孽与副罪孽。"
	main_sin=primary
	ally_sin=secondary
	deck_edited.emit()
	return ""

func select_factions(main_id: String, _ally_id: String) -> void:
	main_faction_id = main_id
	ally_faction_id = ""
	save_profile()
	changed.emit()

func _load_profile() -> void:
	if not FileAccess.file_exists(profile_path): return
	var parsed := Runtime.parse_json(FileAccess.get_file_as_string(profile_path),67108864)
	if not parsed.ok or not parsed.value is Dictionary:
		_load_failed = true
		message.emit("本地档案无法读取，已停止写入以保留原文件。")
		return
	var data: Dictionary = parsed.value
	if data.get("settings") is Dictionary:
		for key in settings:
			if data.settings.get(key) is String: settings[key] = data.settings[key]
	_bound_server = _server(str(settings.backend_url))
	_bound_token = str(settings.api_token)
	_bound_owner = str(settings.owner_id)
	if data.get("catalog_fingerprints") is Dictionary: _catalog_fingerprints = data.catalog_fingerprints
	if data.get("credentials") is Dictionary: _credentials = data.credentials
	if data.get("sync_outbox") is Dictionary: _outbox = data.sync_outbox
	if data.get("sync_after") is Dictionary: _sync_after = data.sync_after
	if data.get("catalog_version") is int or data.get("catalog_version") is float: catalog_version = int(data.catalog_version)
	if data.get("catalog_etag") is String: catalog_etag = data.catalog_etag
	if data.get("faction_catalogs") is Dictionary: _faction_catalogs = data.faction_catalogs
	if data.get("series_catalogs") is Dictionary: _series_catalogs = data.series_catalogs
	main_sin = str(data.get("main_sin", "")) if data.get("main_sin") is String and SinCatalog.valid(data.main_sin) else ""
	ally_sin = str(data.get("ally_sin", "")) if data.get("ally_sin") is String and _valid_deck_sins(main_sin, data.ally_sin) else ""
	main_faction_id = str(data.get("main_faction_id", ""))
	headquarters_id = str(data.get("headquarters_id", ""))
	ally_faction_id = ""
	if data.get("content_catalogs") is Dictionary: _content_catalogs = data.content_catalogs
	if data.get("keyword_catalogs") is Dictionary: _catalogs = data.keyword_catalogs
	if data.get("keyword_archive") is Dictionary:
		for entry in data.keyword_archive.values():
			if entry is Dictionary and entry.get("definition") is Dictionary: _remember_keywords([entry.definition],bool(entry.get("authored",false)))
	if data.get("keyword_definitions") is Array:
		_remember_keywords(data.keyword_definitions,_bound_owner.is_empty())
		keyword_definitions = _valid_keywords(data.keyword_definitions)
	if keyword_definitions.is_empty(): keyword_definitions = Runtime.builtin_keywords()
	if data.get("cards") is Array:
		for raw in data.cards:
			if not raw is Dictionary: continue
			var record := _checked_record(raw)
			if record.is_empty():
				_load_failed = true
				message.emit("本地卡牌校验失败，已停止写入以保留完整原档案。")
				continue
			if not record.has("local_authored"): record["local_authored"] = bool(record.get("local_only",false)) or not record.has("server_origin") or bool(record.get("owned_by_me",false)) or str(record.get("owner_id","")) == "local-player"
			if not record.has("cloud_refs"): record["cloud_refs"] = {}
			var old_origin := _server(str(record.get("server_origin","")))
			if not old_origin.is_empty() and not bool(record.get("local_only",false)) and record.cloud_refs.is_empty(): record.cloud_refs[old_origin] = {"card_id":record.card_id,"revision":record.revision,"definition_hash":record.definition_hash,"compiled_program_hash":record.compiled_program_hash}
			cards.append(record)
	if data.get("deck_ids") is Array: deck_ids = data.deck_ids.filter(func(id): return id is String)
	if data.get("local_decks") is Array:
		for entry in data.local_decks:
			if not entry is Dictionary or not entry.get("id") is String or not entry.get("name") is String or not entry.get("cards") is Array or entry.cards.any(func(id): return not id is String):
				_load_failed = true
				continue
			local_decks.append(entry)
	active_deck_id = str(data.get("active_deck_id", ""))
	deck_name = str(data.get("deck_name", "新牌组"))
	if data.get("deck_publish_pending") is Dictionary: deck_publish_pending = data.deck_publish_pending
	if data.get("pending_sync") is Dictionary and not data.pending_sync.is_empty():
		var old: Dictionary = data.pending_sync.duplicate(true)
		old["server"] = _server(str(old.get("server",_bound_server)))
		old["owner_id"] = str(old.get("owner_id",_bound_owner))
		if not old.has("dependencies"): old["dependencies"] = keyword_definitions.duplicate(true)
		_outbox[str(old.server)+"|"+str(old.owner_id)] = old
	pending_sync = _outbox.get(_scope(),{}).duplicate(true)
	_deduplicate_cards()
	_follow_latest_decks()

func save_profile() -> bool:
	_ensure_context()
	if _load_failed: return false
	_stash_pending()
	_remember_keywords(keyword_definitions,true,true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(profile_path.get_base_dir()))
	var temp_path := profile_path + ".tmp"
	var file := FileAccess.open(temp_path,FileAccess.WRITE)
	if file == null:
		message.emit("无法保存本地档案，请检查目录权限。")
		return false
	file.store_string(JSON.stringify({"series_catalogs":_series_catalogs,"catalog_fingerprints":_catalog_fingerprints,"content_catalogs":_content_catalogs,"cards":cards,"keyword_definitions":keyword_definitions,"deck_ids":deck_ids,"headquarters_id":headquarters_id,"faction_catalogs":_faction_catalogs,"main_sin":main_sin,"ally_sin":ally_sin,"main_faction_id":main_faction_id,"ally_faction_id":ally_faction_id,"local_decks":local_decks,"active_deck_id":active_deck_id,"deck_name":deck_name,"deck_publish_pending":deck_publish_pending,"settings":settings,"pending_sync":pending_sync,"sync_outbox":_outbox,"credentials":_credentials,"keyword_archive":_keyword_archive,"keyword_catalogs":_catalogs,"sync_after":_sync_after,"catalog_version":catalog_version,"catalog_etag":catalog_etag},"\t"))
	file.flush()
	var err := file.get_error()
	file.close()
	if err == OK: err = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path),ProjectSettings.globalize_path(profile_path))
	if err != OK:
		message.emit("本地档案保存失败：%s" % error_string(err))
		return false
	return true

func client_build() -> int:
	var updater := get_node_or_null("/root/ClientUpdate")
	# Old installers retain their bootstrap; current_build is the verified loaded patch.
	return int(updater.current_build) if updater != null else preload("res://scripts/client_update.gd").BASE_BUILD

func request(endpoint: String, method: int = HTTPClient.METHOD_GET, payload: Dictionary = {}) -> Dictionary:
	if true: return _error("联机服务已停用。", 503)
	_ensure_context()
	var epoch := _context_epoch
	var origin := _bound_server
	var credential := _bound_token
	if origin.is_empty() or not endpoint.begins_with("/") or endpoint.begins_with("//"): return _error("服务地址无效：请使用 HTTPS；本机开发服务可使用 HTTP。")
	var certificate: X509Certificate
	if origin == DEFAULT_SERVER:
		certificate = X509Certificate.new()
		if certificate.load("res://assets/server_ca.crt") != OK: return _error("服务器证书缺失，请使用最新版客户端。")
	var http := HTTPRequest.new()
	http.timeout = 6.0 if endpoint.begins_with("/v1/rooms/") and endpoint.ends_with("/state") else 10.0 if endpoint.begins_with("/v1/rooms/") and endpoint.ends_with("/actions") else 15.0
	http.body_size_limit = 8388608
	http.max_redirects = 0
	if certificate != null: http.set_tls_options(TLSOptions.client(certificate))
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json", "X-Frontline-Client-Build: %d" % client_build()])
	if not credential.is_empty() and endpoint != "/v1/sessions":
		if "\r" in credential or "\n" in credential:
			http.queue_free()
			return _error("业务令牌格式无效。")
		headers.append("Authorization: Bearer " + credential)
	var body := "" if method in [HTTPClient.METHOD_GET,HTTPClient.METHOD_DELETE] else JSON.stringify(payload)
	var err := http.request(origin + endpoint,headers,method,body)
	if err != OK:
		http.queue_free()
		return _error("无法发起请求：" + error_string(err))
	var response: Array = await http.request_completed
	http.queue_free()
	_ensure_context()
	if epoch != _context_epoch or origin != _bound_server or credential != _bound_token:
		var stale := _error("服务器或玩家身份已改变，已忽略旧响应。")
		stale["stale"] = true
		return stale
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		var connection_errors := {HTTPRequest.RESULT_CANT_RESOLVE:"服务器域名解析失败。", HTTPRequest.RESULT_CANT_CONNECT:"无法连接服务器，请稍后重试。", HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:"服务器证书校验失败，请使用最新版客户端。", HTTPRequest.RESULT_TIMEOUT:"服务器连接超时，请重试。", HTTPRequest.RESULT_CONNECTION_ERROR:"连接已中断，请重试。"}
		return _error(str(connection_errors.get(response[0], "网络请求失败（%d）。" % int(response[0]))))
	var statistical := endpoint.get_slice("?",0) in ["/v1/public/statistics", "/v1/me/statistics"]
	var parsed: Dictionary = Runtime.StrictJson.new().parse(response[3].get_string_from_utf8(),8388608,true) if statistical else Runtime.parse_json(response[3].get_string_from_utf8(),8388608)
	if not parsed.ok or not parsed.value is Dictionary: return _error("服务器响应格式无效。",int(response[1]))
	var data: Dictionary = parsed.value
	var success: bool = response[1] >= 200 and response[1] < 300
	var detail := ""
	if not success:
		var item: Variant = data.get("error",{})
		detail = str(item.get("message","请求失败")) if item is Dictionary else str(item)
	else:
		var candidate: Variant = data.get("result",data)
		if candidate is Dictionary and candidate.has("draft_id"): _draft_contexts[str(candidate.draft_id)] = {"server":origin,"owner_id":_bound_owner}
	return {"ok":success,"error":detail,"code":int(response[1]),"data":data}

func _error(text: String, code: int = 0) -> Dictionary:
	return {"ok":false,"error":text,"code":code,"data":{}}

func _keyword_id(definition: Dictionary) -> String:
	return str(definition.get("id","")) + "@" + str(int(definition.get("version",0)))

func _valid_keywords(values: Array) -> Array:
	var found: Dictionary = {}
	for value in values:
		if not value is Dictionary or not Runtime.validate_keyword(value).is_empty(): return []
		var identity := _keyword_id(value)
		if found.has(identity) and Runtime.sha(found[identity]) != Runtime.sha(value): return []
		found[identity] = value.duplicate(true)
	return found.values()

func _remember_keywords(values: Array, authored: bool, only_new: bool = false) -> void:
	for value in values:
		if not value is Dictionary or not Runtime.validate_keyword(value).is_empty(): continue
		var digest := Runtime.sha(value)
		var own: bool = authored and value.implementation.kind == "template"
		if _keyword_archive.has(digest):
			if own and not only_new: _keyword_archive[digest].authored = true
		else: _keyword_archive[digest] = {"definition":value.duplicate(true),"authored":own}

func _activate_keywords() -> void:
	var found: Dictionary = {}
	for value in _catalogs.get(_bound_server,Runtime.builtin_keywords()):
		if value is Dictionary and Runtime.validate_keyword(value).is_empty(): found[_keyword_id(value)] = value
	for entry in _keyword_archive.values():
		var value: Dictionary = entry.definition
		if not found.has(_keyword_id(value)): found[_keyword_id(value)] = value
	keyword_definitions = found.values().filter(func(value): return not content_status("keywords",str(value.id)).get("deleted",false)).duplicate(true)

func _catalog_from_entries(entries: Array) -> Array:
	var values: Array = []
	for entry in entries:
		if not entry is Dictionary or not entry.get("definition") is Dictionary or entry.get("definition_hash") != Runtime.sha(entry.definition): return []
		values.append(entry.definition)
	return _valid_keywords(values)

func record_keywords(record: Dictionary) -> Array:
	if record.get("frozen_keywords") is Array: return record.frozen_keywords.duplicate(true)
	if record.get("keyword_bindings") is Array:
		var frozen: Array = []
		for binding in record.keyword_bindings:
			if not binding is Dictionary: return []
			var digest := str(binding.get("definition_hash",""))
			if not _keyword_archive.has(digest): return keyword_definitions.duplicate(true)
			frozen.append(_keyword_archive[digest].definition)
		return frozen.duplicate(true)
	return keyword_definitions.duplicate(true)

func compile_record(record: Dictionary) -> Dictionary:
	if not record.get("definition") is Dictionary: return _error("卡牌定义缺失。")
	var compiled := Runtime.compile_card(record.definition,record_keywords(record))
	if compiled.ok and record.has("compiled_program_hash") and record.compiled_program_hash != compiled.compiled_program_hash: return _error("卡牌冻结词条与编译哈希不一致。")
	if compiled.ok:
		compiled["token_art_ids"] = CardArtCache.record_token_art_ids(record)
		var ref: Dictionary=record.get("cloud_refs",{}).get(_bound_server,record)
		if _uuid_string(str(ref.get("card_id",""))): compiled["telemetry_ref"]={"card_id":str(ref.card_id).to_lower(),"revision":int(ref.get("revision",1))}
	return compiled

func display_definition(record: Dictionary) -> Dictionary:
	# Presentation-only cache. Match compilation still validates frozen hashes.
	var key := _content_key(record)
	if not _display_cache.has(key):
		var compiled := compile_record(record)
		if not compiled.ok: return record.get("definition", {})
		_display_cache[key] = Runtime.display_definition(compiled)
	return _display_cache[key]

func _checked_record(raw: Dictionary, catalog: Array = []) -> Dictionary:
	if not _uuid_string(str(raw.get("card_id",""))) or not raw.get("definition") is Dictionary: return {}
	var revision: Variant = raw.get("revision",0)
	if not (revision is int or revision is float) or not is_finite(float(revision)) or float(revision) != floor(float(revision)) or revision < 1 or revision > 9007199254740991: return {}
	var keywords := catalog if not catalog.is_empty() else record_keywords(raw)
	var compiled := Runtime.compile_card(raw.definition,keywords)
	if not compiled.ok or raw.get("definition_hash") != compiled.definition_hash: return {}
	if raw.has("compiled_program_hash") and raw.compiled_program_hash != compiled.compiled_program_hash: return {}
	if raw.has("keyword_bindings") and Runtime.canonical(raw.keyword_bindings) != Runtime.canonical(compiled.keyword_bindings): return {}
	var frozen: Array = []
	for binding in compiled.keyword_bindings:
		var found := false
		for definition in keywords:
			if Runtime.sha(definition) == binding.definition_hash:
				frozen.append(definition.duplicate(true))
				found = true
				break
		if not found: return {}
	var checked := raw.duplicate(true)
	if checked.get("art", {}) == null: checked.erase("art")
	checked["definition"] = compiled.source
	checked["revision"] = int(revision)
	checked["series"] = preload("res://scripts/core/card_series.gd").number(raw)
	checked["compiled_program_hash"] = compiled.compiled_program_hash
	checked["keyword_bindings"] = compiled.keyword_bindings
	checked["frozen_keywords"] = frozen
	_remember_keywords(frozen,false)
	_display_cache[_content_key(checked)] = compiled.definition
	return checked

func _content_key(record: Dictionary) -> String:
	return str(record.get("definition_hash","")) + ":" + str(record.get("compiled_program_hash",""))

func _ingest_remote(raw: Dictionary, origin: String, catalog: Array, preferred_id: String = "") -> Dictionary:
	var incoming := _checked_record(raw,catalog)
	if incoming.is_empty(): return {}
	# Series is card-family metadata. Refresh cached historical revisions too.
	for record in cards:
		if record.get("cloud_refs",{}).get(origin,{}).get("card_id","")==incoming.card_id:
			record["series"]=incoming.series
	var ref := {"card_id":incoming.card_id,"revision":incoming.revision,"definition_hash":incoming.definition_hash,"compiled_program_hash":incoming.compiled_program_hash}
	for record in cards:
		if (not record.get("cloud_refs", {}).has(origin) or (record.cloud_refs[origin].get("card_id") == incoming.card_id and int(record.cloud_refs[origin].get("revision", 0)) == int(incoming.revision))) and _content_key(record) == _content_key(incoming) and (not record.get("author") is Dictionary or not incoming.get("author") is Dictionary or record.author.get("id") == incoming.author.get("id")):
			record.cloud_refs[origin] = ref
			record["revision"] = incoming.revision
			if str(record.get("server_origin", "")).is_empty(): record["server_origin"] = origin
			if incoming.get("author") is Dictionary: record["author"] = incoming.author.duplicate(true)
			if incoming.has("art"):
				if incoming.art is Dictionary: record["art"] = incoming.art.duplicate(true)
				else: record.erase("art")
			if incoming.has("token_art"): record["token_art"] = incoming.token_art.duplicate(true)
			for key in ["owned_by_me", "can_edit", "archived", "derived_from", "available_revisions", "series"]:
				if incoming.has(key): record[key] = incoming[key]
			record["local_authored"] = bool(record.get("local_authored",false)) or bool(raw.get("owned_by_me",false))
			return record
	var local_id := preferred_id if _uuid_string(preferred_id) else str(incoming.card_id)
	if not get_card(local_id).is_empty(): local_id = uuid()
	incoming["card_id"] = local_id
	incoming["server_origin"] = origin
	incoming["local_only"] = false
	incoming["local_authored"] = bool(raw.get("owned_by_me",false))
	incoming["cloud_refs"] = {origin:ref}
	cards.append(incoming)
	return incoming

func _deduplicate_cards() -> void:
	var found: Dictionary = {}
	var replacements: Dictionary = {}
	var retained: Array = []
	for record in cards:
		var identity := _content_key(record) + Runtime.canonical(record.get("cloud_refs", {}))
		if found.has(identity):
			var existing: Dictionary = found[identity]
			existing.cloud_refs.merge(record.get("cloud_refs",{}),false)
			existing.local_authored = bool(existing.get("local_authored",false)) or bool(record.get("local_authored",false))
			replacements[record.card_id] = existing.card_id
		else:
			found[identity] = record
			retained.append(record)
	cards = retained
	for index in deck_ids.size(): deck_ids[index] = replacements.get(deck_ids[index],deck_ids[index])
	headquarters_id = replacements.get(headquarters_id,headquarters_id)
	for deck in local_decks:
		deck["headquarters_id"] = replacements.get(deck.get("headquarters_id",""),deck.get("headquarters_id",""))
		for index in deck.cards.size(): deck.cards[index] = replacements.get(deck.cards[index], deck.cards[index])

func card_identity(record: Dictionary) -> String:
	var origin := _bound_server
	var refs: Dictionary = record.get("cloud_refs", {})
	if not refs.has(origin): origin = str(record.get("server_origin", ""))
	return origin + ":" + str(refs[origin].card_id) if refs.has(origin) else "local:" + str(record.get("card_id", ""))

func content_status(kind: String, id: String) -> Dictionary:
	return _content_catalogs.get(_bound_server,{}).get(kind,{}).get(id,{})

func card_status(record: Dictionary) -> Dictionary:
	var ref: Dictionary = record.get("cloud_refs",{}).get(_bound_server,{})
	var status := content_status("cards",str(ref.get("card_id",record.get("card_id",""))))
	if status.is_empty() and record.get("derived_from") is Dictionary:
		status=content_status("cards",str(record.derived_from.card_id))
		if status.is_empty() and record.get("archived",false): return {"archived":true}
	return status

func _sync_deleted(record: Dictionary) -> bool:
	if card_status(record).get("deleted",false): return true
	for entry in _content_catalogs.get(_bound_server,{}).get("cards",{}).values():
		if entry.get("deleted",false) and record.get("definition_hash","") in entry.get("hashes",[]): return true
	var refs: Array = record.get("definition",{}).get("keywords",[]).duplicate()
	for token in record.get("definition",{}).get("tokens",[]): refs.append_array(token.get("keywords",[]))
	for ref in refs:
		if content_status("keywords",str(ref.id)).get("deleted",false): return true
	return content_status("factions",str(record.get("definition",{}).get("faction_id",""))).get("deleted",false)

func _apply_content_lifecycle(snapshot: Variant) -> void:
	if not snapshot is Dictionary: return
	for kind in ["cards","keywords","factions"]:
		if not snapshot.get(kind) is Dictionary: return
		for entry in snapshot[kind].values():
			if not entry is Dictionary: return
	_content_catalogs[_bound_server] = snapshot.duplicate(true)
	var removed: Array = []
	for record in cards:
		if card_status(record).get("deleted",false): removed.append(record.card_id)
	if not removed.is_empty():
		# Keep another server's independent copy, but remove this server's deck references.
		cards=cards.filter(func(record): return not record.card_id in removed or record.get("cloud_refs",{}).size()>1)
		deck_ids=deck_ids.filter(func(id): return not id in removed)
		if headquarters_id in removed: headquarters_id=""
		for deck in local_decks:
			deck.cards=deck.cards.filter(func(id): return not id in removed)
			if deck.get("headquarters_id","") in removed: deck.headquarters_id=""
		deck_publish_pending={}
		message.emit("已移除服务器彻底删除的卡牌，请检查受影响的牌组。")
	if content_status("factions",main_faction_id).get("deleted",false): main_faction_id=""
	for deck in local_decks:
		if content_status("factions",str(deck.get("main_faction_id",""))).get("deleted",false): deck.main_faction_id=""
	for digest in _keyword_archive.keys():
		if content_status("keywords",str(_keyword_archive[digest].definition.id)).get("deleted",false):
			var retained := false
			for record in cards:
				if record.get("keyword_bindings",[]).any(func(binding): return binding.definition_hash==digest): retained=true
			if not retained: _keyword_archive.erase(digest)
	_activate_keywords()
	# An old retry payload must never republish deleted content.
	var stale := false
	for item in pending_sync.get("payload",{}).get("cards",[]):
		if _sync_deleted(item): stale=true
	for definition in pending_sync.get("payload",{}).get("keywords",[]):
		if content_status("keywords",str(definition.id)).get("deleted",false): stale=true
	if stale:
		pending_sync={}
		_outbox.erase(_scope())

func latest_cards(include_archived: bool = false) -> Array:
	var latest := {}
	for record in cards:
		var key := card_identity(record)
		if not latest.has(key) or int(record.get("revision", 1)) > int(latest[key].get("revision", 1)): latest[key] = record
	return latest.values().filter(func(record): return not card_status(record).get("deleted",false) and (include_archived or not card_status(record).get("archived",false)))

# Decks follow published identities; frozen historical records remain available for inspection.
func _follow_latest_decks() -> bool:
	var latest := {}
	for record in cards:
		if card_status(record).get("deleted",false): continue
		var key := card_identity(record)
		if not latest.has(key) or int(record.revision)>int(latest[key].revision): latest[key]=record
	var mapping := {}
	for record in cards:
		var newer: Dictionary = latest.get(card_identity(record),record)
		if newer.card_id!=record.card_id: mapping[record.card_id]=newer.card_id
	if mapping.is_empty(): return false
	var modified := false
	for i in deck_ids.size():
		if mapping.has(deck_ids[i]): deck_ids[i]=mapping[deck_ids[i]]; modified=true
	if mapping.has(headquarters_id): headquarters_id=mapping[headquarters_id]; modified=true
	for deck in local_decks:
		for i in deck.cards.size():
			if mapping.has(deck.cards[i]): deck.cards[i]=mapping[deck.cards[i]]; modified=true
		if mapping.has(deck.get("headquarters_id","")): deck.headquarters_id=mapping[deck.headquarters_id]; modified=true
	if modified: deck_publish_pending={}
	return modified

func _valid_deck_sins(primary: Variant, secondary: Variant) -> bool:
	return SinCatalog.valid(primary) and SinCatalog.valid(secondary) and (secondary==null or secondary=="" or primary!=secondary)

func load_card_version(record: Dictionary, revision: int) -> Dictionary:
	var identity := card_identity(record)
	for old in cards:
		if card_identity(old) == identity and int(old.get("revision", 1)) == revision: return {"ok":true,"card":old}
	var ref: Dictionary = record.get("cloud_refs", {}).get(_bound_server, {})
	if ref.is_empty(): return _error("此卡牌没有可读取的历史版本。")
	var result := await request("/v1/cards/%s?revision=%d" % [ref.card_id, revision])
	if not result.ok: return result
	var saved := _ingest_remote(result.data, _bound_server, keyword_definitions)
	if saved.is_empty(): return _error("历史版本校验失败。")
	save_profile()
	return {"ok":true,"card":saved}

func name_count(record: Dictionary) -> int:
	var key := DeckRules.name_key(record.definition)
	var count := 0
	for id in deck_ids:
		var entry := get_card(id)
		if not entry.is_empty() and (DeckRules.name_key(entry.definition) == key or card_identity(entry) == card_identity(record)): count += 1
	return count

func card_author(record: Dictionary) -> String:
	var author: Variant = record.get("author")
	return str(author.get("name", "未署名")) if author is Dictionary else (str(settings.player_name) if record.get("local_only", false) else "未署名")

func get_card(id: String) -> Dictionary:
	for record in cards:
		if str(record.card_id) == id: return record
	return {}

func deck_count(id: String) -> int:
	return deck_ids.count(id)

func add_to_deck(id: String) -> String:
	var record := get_card(id)
	if record.is_empty(): return "卡牌不存在。"
	if deck_ids.size() >= DeckRules.DECK_SIZE: return "牌组最多 40 张，总部不计入。"
	var proposed: Array = deck_ids.map(func(key): return get_card(key))
	proposed.append(record)
	var copy_error := DeckRules.check_copies(proposed)
	if not copy_error.is_empty(): return copy_error
	var composition := DeckRules.composition(proposed, factions, main_sin, ally_sin, false)
	if not composition.error.is_empty(): return composition.error
	var selection := DeckRules.factions(proposed, factions, main_faction_id, "", main_faction_id.is_empty())
	if not selection.error.is_empty(): return selection.error
	deck_ids.append(id)
	deck_edited.emit()
	return ""

func remove_from_deck(id: String) -> void:
	deck_ids.erase(id)
	deck_edited.emit()

func select_headquarters(id: String) -> String:
	if not id.is_empty():
		var record := get_card(id)
		if record.is_empty() or record.definition.kind!="hq": return "请选择总部卡。"
		var checked := compile_record(record)
		if not checked.ok: return checked.error
	headquarters_id=id
	deck_edited.emit()
	return ""

func compile_deck() -> Dictionary:
	if deck_ids.size() != DeckRules.DECK_SIZE: return _error("请组建恰好 40 张卡牌的牌组，总部不计入。")
	var selection := deck_factions()
	if not selection.error.is_empty(): return _error(selection.error)
	var compiled_deck: Array = []
	var copy_error := DeckRules.check_copies(deck_ids.map(func(id): return get_card(id)))
	if not copy_error.is_empty(): return _error(copy_error)
	var frozen: Dictionary = {}
	for id in deck_ids:
		var record := get_card(id)
		var compiled := compile_record(record)
		if not compiled.ok: return compiled
		if record.get("art") is Dictionary: compiled["art_id"] = str(record.art.get("id", ""))
		for keyword in record_keywords(record):
			var identity := _keyword_id(keyword)
			if frozen.has(identity) and Runtime.sha(frozen[identity]) != Runtime.sha(keyword): return _error("牌组使用了来自不同服务器且定义冲突的词条版本。")
			frozen[identity] = keyword
		compiled_deck.append(compiled)
	var headquarters := {}
	if not headquarters_id.is_empty():
		var record := get_card(headquarters_id)
		if record.is_empty() or record.definition.kind!="hq": return _error("总部版本缺失，请重新选择总部。")
		headquarters = compile_record(record)
		if not headquarters.ok: return headquarters
		if record.get("art") is Dictionary: headquarters["art_id"]=str(record.art.get("id",""))
		for keyword in record_keywords(record):
			var identity := _keyword_id(keyword)
			if frozen.has(identity) and Runtime.sha(frozen[identity]) != Runtime.sha(keyword): return _error("总部与牌组词条版本冲突。")
			frozen[identity]=keyword
	return {"ok":true,"error":"","deck":compiled_deck,"headquarters":headquarters,"keyword_definitions":frozen.values()}

func _has_cloud_ref(record: Dictionary, origin: String) -> bool:
	var ref: Variant = record.get("cloud_refs",{}).get(origin,{})
	return ref is Dictionary and _uuid_string(str(ref.get("card_id",""))) and int(ref.get("revision",0)) > 0 and ref.get("definition_hash") == record.definition_hash and ref.get("compiled_program_hash") == record.compiled_program_hash

func cloud_deck_refs() -> Dictionary:
	_ensure_context()
	if not central_mode or not authenticated: return _error("请先登录中心服务器。")
	var result := compile_deck()
	if not result.ok: return result
	var refs: Array = []
	for id in deck_ids:
		var record := get_card(id)
		if not _has_cloud_ref(record,_bound_server): return _error("牌组仍有尚未同步到当前服务器的卡牌，请刷新档案后重试。")
		var ref: Dictionary = record.cloud_refs[_bound_server]
		refs.append({"card_id":ref.card_id,"revision":ref.revision,"definition_hash":ref.definition_hash})
	var headquarters: Variant = null
	if not headquarters_id.is_empty():
		var record := get_card(headquarters_id)
		if not _has_cloud_ref(record,_bound_server): return _error("总部尚未同步到当前服务器，请刷新卡库。")
		var ref: Dictionary=record.cloud_refs[_bound_server]
		headquarters={"card_id":ref.card_id,"revision":ref.revision,"definition_hash":ref.definition_hash}
	return {"ok":true,"error":"","deck":refs,"headquarters":headquarters}

static func _uuid_string(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$")
	return pattern.search(value) != null

static func uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var value := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [value.substr(0,8),value.substr(8,4),value.substr(12,4),value.substr(16,4),value.substr(20,12)]

func local_deck(id: String) -> Dictionary:
	for entry in local_decks:
		if entry.id == id: return entry
	return {}

func save_local_deck(title: String, as_copy: bool = false) -> Dictionary:
	title = title.strip_edges()
	if title.is_empty() or title.length() > 40 or title.contains("\n") or title.contains("\r"): return _error("牌组名称需为 1 至 40 个字符。")
	var before := local_decks.duplicate(true)
	var old_id := active_deck_id
	var old_name := deck_name
	var entry := {} if as_copy else local_deck(active_deck_id)
	if entry.is_empty():
		entry = {"id":uuid()}
		local_decks.append(entry)
	entry.merge({"name":title,"cards":deck_ids.duplicate(),"headquarters_id":headquarters_id,"main_sin":main_sin,"ally_sin":ally_sin,"main_faction_id":main_faction_id,"ally_faction_id":ally_faction_id,"updated_at":Time.get_datetime_string_from_system(true)}, true)
	active_deck_id = entry.id
	deck_name = title
	if not save_profile():
		local_decks = before
		active_deck_id = old_id
		deck_name = old_name
		return _error("本地牌组保存失败。")
	return {"ok":true,"deck":entry}

func _stash_working_deck() -> void:
	if deck_ids.is_empty() and headquarters_id.is_empty(): return
	var saved := local_deck(active_deck_id)
	if not saved.is_empty() and saved.cards == deck_ids and saved.get("headquarters_id","")==headquarters_id and saved.name == deck_name and saved.get("main_sin", "") == main_sin and saved.get("ally_sin", "") == ally_sin and saved.get("main_faction_id", "") == main_faction_id and saved.get("ally_faction_id", "") == ally_faction_id: return
	# Loading another deck must never discard the currently edited draft.
	local_decks.append({"id":uuid(),"name":deck_name + " · 草稿","cards":deck_ids.duplicate(),"headquarters_id":headquarters_id,"main_sin":main_sin,"ally_sin":ally_sin,"main_faction_id":main_faction_id,"ally_faction_id":ally_faction_id,"updated_at":Time.get_datetime_string_from_system(true)})

func load_local_deck(id: String) -> Dictionary:
	var entry := local_deck(id)
	if entry.is_empty(): return _error("本地牌组不存在。")
	if entry.cards.any(func(key): return get_card(key).is_empty()): return _error("牌组缺少卡牌版本，当前牌组未更改。")
	return _switch_deck(entry.cards, entry.name, entry.id, str(entry.get("main_faction_id", "")), str(entry.get("ally_faction_id", "")), str(entry.get("headquarters_id", "")), str(entry.get("main_sin", "")), str(entry.get("ally_sin", "")))

func _switch_deck(ids: Array, title: String, id: String, main_id := "", ally_id := "", hq_id := "", sin_id := "", ally_sin_id := "") -> Dictionary:
	if not _valid_deck_sins(sin_id, ally_sin_id): return _error("罪孽选择无效。")
	var before := {"decks":local_decks.duplicate(true),"ids":deck_ids.duplicate(),"name":deck_name,"id":active_deck_id,"main":main_faction_id,"sin":main_sin,"ally_sin":ally_sin,"ally":ally_faction_id,"headquarters":headquarters_id,"pending":deck_publish_pending.duplicate(true)}
	if not hq_id.is_empty() and get_card(hq_id).get("definition",{}).get("kind")!="hq": return _error("总部版本缺失。")
	_stash_working_deck()
	main_sin=sin_id
	ally_sin=ally_sin_id
	headquarters_id=hq_id
	deck_ids = ids.duplicate()
	deck_name = title
	active_deck_id = id
	main_faction_id = main_id
	ally_faction_id = ""
	_follow_latest_decks()
	_infer_deck_factions()
	if not save_profile():
		local_decks = before.decks
		deck_ids = before.ids
		deck_name = before.name
		active_deck_id = before.id
		main_sin = before.sin
		ally_sin = before.ally_sin
		main_faction_id = before.main
		ally_faction_id = before.ally
		headquarters_id = before.headquarters
		deck_publish_pending = before.pending
		return _error("无法保存切换后的牌组。")
	changed.emit()
	return {"ok":true}

func new_local_deck(title := "新牌组", main_id := "", sin_id := "", ally_sin_id := "") -> Dictionary:
	if not main_id.is_empty() and not factions.has(main_id): return _error("请选择已登记的主国。")
	title = title.strip_edges()
	if title.is_empty() or title.length()>40 or title.contains("\n") or title.contains("\r"): return _error("牌组名称需为 1 至 40 个字符。")
	return _switch_deck([], title, uuid(), main_id, "", "", sin_id, ally_sin_id)

func rename_local_deck(id: String, title: String) -> Dictionary:
	title=title.strip_edges()
	if title.is_empty() or title.length()>40 or title.contains("\n") or title.contains("\r"): return _error("牌组名称需为 1 至 40 个字符。")
	var entry:=local_deck(id)
	if entry.is_empty(): return _error("本地牌组不存在。")
	var previous_name: String=entry.name
	var working_name:=deck_name
	entry.name=title
	if active_deck_id==id: deck_name=title
	if not save_profile(): entry.name=previous_name; deck_name=working_name; return _error("重命名未能保存。")
	deck_edited.emit()
	return {"ok":true}

func delete_local_deck(id: String) -> Dictionary:
	var before:=local_decks.duplicate(true)
	var old_id:=active_deck_id
	local_decks=local_decks.filter(func(d):return d.id!=id)
	if active_deck_id==id: active_deck_id=""
	if not save_profile(): local_decks=before; active_deck_id=old_id; return _error("删除未能保存。")
	return {"ok":true}

func import_deck_json(source: String) -> Dictionary:
	var parsed := Runtime.parse_json(source, 8388608)
	if not parsed.ok or not parsed.value is Dictionary: return _error("牌组 JSON 格式无效。")
	return accept_shared_deck(parsed.value)

func publish_deck() -> Dictionary:
	if _deck_publish_busy: return _error("牌组正在上传。")
	var prepared := cloud_deck_refs()
	if not prepared.ok: return prepared
	var saved := save_local_deck(deck_name)
	if not saved.ok: return saved
	var local_id := active_deck_id
	var scope := _scope()
	var body := {"name":deck_name,"cards":prepared.deck,"headquarters":prepared.headquarters,"main_sin":main_sin,"ally_sin":ally_sin,"main_faction_id":main_faction_id,"ally_faction_id":ally_faction_id}
	var shared: Dictionary = saved.deck.get("shared", {}).get(scope, {})
	if not shared.is_empty():
		body.deck_id = shared.deck_id
		body.expected_revision = shared.revision
	var digest := Runtime.sha(body)
	if deck_publish_pending.get("scope") != scope or deck_publish_pending.get("digest") != digest:
		deck_publish_pending = {"scope":scope,"digest":digest,"request_id":uuid()}
	body.request_id = deck_publish_pending.request_id
	if not save_profile(): return _error("无法保存上传请求，请重试。")
	_deck_publish_busy = true
	var result := await request("/v1/decks", HTTPClient.METHOD_POST, body)
	_deck_publish_busy = false
	if not result.ok: return result
	var entry := local_deck(local_id)
	if not entry.is_empty():
		if not entry.has("shared"): entry.shared = {}
		entry.shared[scope] = result.data
	deck_publish_pending = {}
	if not save_profile(): return _error("牌组已共享，但本地上传记录保存失败。")
	return result

func import_shared_deck(id: String) -> Dictionary:
	var result := await request(("/v1/decks/" if authenticated else "/v1/public/decks/") + id)
	if not result.ok: return result
	return accept_shared_deck(result.data, true)

func accept_shared_deck(bundle: Dictionary, allow_updated_draft := false) -> Dictionary:
	var deck: Variant = bundle.get("deck")
	if not deck is Dictionary or not deck.get("name") is String or not deck.get("cards") is Array or deck.cards.size() != DeckRules.DECK_SIZE or not bundle.get("cards") is Array or not bundle.get("keywords") is Array: return _error("共享牌组格式无效。")
	if not _valid_deck_sins(deck.get("main_sin", ""), deck.get("ally_sin", "")): return _error("共享牌组罪孽选择无效。")
	var catalog := _catalog_from_entries(bundle.keywords)
	if not bundle.keywords.is_empty() and catalog.is_empty(): return _error("共享牌组词条校验失败。")
	var checked := {}
	for raw in bundle.cards:
		if not raw is Dictionary: return _error("共享卡牌格式无效。")
		var record := _checked_record(raw, catalog)
		if record.is_empty(): return _error("共享卡牌版本校验失败。")
		checked[str(record.card_id)+"@"+str(int(record.revision))] = record
	var hq_key := ""
	if deck.get("headquarters") != null:
		var ref: Variant=deck.headquarters
		if not ref is Dictionary: return _error("总部引用无效。")
		hq_key=str(ref.get("card_id"))+"@"+str(int(ref.get("revision",0)))
		var hq: Dictionary=checked.get(hq_key,{})
		if hq.is_empty() or hq.definition.kind!="hq" or hq.definition_hash!=ref.get("definition_hash"): return _error("共享牌组缺少总部版本。")
	var selected: Array = []
	for ref in deck.cards:
		if not ref is Dictionary: return _error("共享卡牌引用无效。")
		var record: Dictionary = checked.get(str(ref.get("card_id"))+"@"+str(int(ref.get("revision",0))), {})
		if record.is_empty() or ref.get("definition_hash") != record.definition_hash: return _error("共享牌组缺少指定版本。")
		selected.append(record)
	var copy_error := DeckRules.check_copies(selected)
	if not copy_error.is_empty() and not allow_updated_draft: return _error(copy_error)
	var registry := factions.duplicate(true)
	registry.merge(FactionCatalog.parse(bundle.get("factions", [])), true)
	var selection := DeckRules.factions(selected, registry, str(deck.get("main_faction_id", "")), str(deck.get("ally_faction_id", "")), str(deck.get("main_faction_id", "")).is_empty())
	if not selection.error.is_empty(): return _error(selection.error)
	var old_factions := factions.duplicate(true)
	factions = registry
	FactionCatalog.entries = factions
	_faction_catalogs[_bound_server] = factions.values()
	var old_cards := cards.duplicate(true)
	var old_decks := local_decks.duplicate(true)
	var ids: Array = []
	var mapping := {}
	for raw in checked.values():
		var imported := _ingest_remote(raw, _bound_server, catalog)
		if imported.is_empty():
			cards = old_cards
			factions = old_factions
			FactionCatalog.entries = factions
			_faction_catalogs[_bound_server] = factions.values()
			return _error("共享牌组导入失败。")
		mapping[str(raw.card_id)+"@"+str(int(raw.revision))] = imported.card_id
	for raw in selected: ids.append(mapping[str(raw.card_id)+"@"+str(int(raw.revision))])
	var entry := {"id":uuid(),"name":str(deck.name).left(40),"cards":ids,"headquarters_id":mapping.get(hq_key,""),"main_sin":deck.get("main_sin", "") if deck.get("main_sin") is String else "","ally_sin":deck.get("ally_sin", "") if deck.get("ally_sin") is String else "","main_faction_id":selection.main_faction_id,"ally_faction_id":selection.ally_faction_id,"updated_at":Time.get_datetime_string_from_system(true)}
	if deck.get("owned_by_me", false): entry.shared = {_scope():deck.duplicate(true)}
	local_decks.append(entry)
	var switched := _switch_deck(ids, entry.name, entry.id, entry.main_faction_id, entry.ally_faction_id, entry.headquarters_id, entry.main_sin, entry.ally_sin)
	if not switched.ok:
		cards = old_cards
		local_decks = old_decks
		factions = old_factions
		FactionCatalog.entries = factions
		_faction_catalogs[_bound_server] = factions.values()
	if switched.ok:
		if not copy_error.is_empty(): message.emit("卡牌已更新，请调整牌组："+copy_error)
	return switched

func _context_current(serial: int, origin: String, token: String) -> bool:
	_ensure_context()
	return serial == _refresh_serial and origin == _bound_server and token == _bound_token

func _finish_refresh(serial: int) -> void:
	if serial != _refresh_serial: return
	_refresh_running = false
	save_profile()
	changed.emit()

func _catalog_manifest() -> Dictionary:
	var saved: Variant = _catalog_fingerprints.get(_scope(), {})
	if not saved is Dictionary or not saved.get("cards") is Dictionary: return {}
	var manifest: Dictionary = saved.duplicate(true)
	var present := {}
	for record in cards:
		var ref: Dictionary = record.get("cloud_refs", {}).get(_bound_server, {})
		if not ref.is_empty(): present[str(ref.card_id)] = true
	for id in manifest.cards.keys():
		if not present.has(id): manifest.cards.erase(id)
	if not _catalogs.has(_bound_server): manifest.erase("keywords")
	if not _faction_catalogs.has(_bound_server): manifest.erase("factions")
	if not _content_catalogs.has(_bound_server): manifest.erase("lifecycle")
	return manifest

func _valid_fingerprints(value: Variant) -> bool:
	if not value is Dictionary or not value.get("cards") is Dictionary: return false
	for section in ["keywords", "factions", "lifecycle"]:
		if not value.get(section) is String or not CardArtCache.valid_id(value[section]): return false
	for id in value.cards:
		if not _uuid_string(str(id)) or not value.cards[id] is String or not CardArtCache.valid_id(value.cards[id]): return false
	return true

## trusted skips per-card pre-checks for the catalog packaged with this build; installing still validates each card.
func _apply_catalog_delta(data: Dictionary, trusted := false) -> Dictionary:
	var series_info: Variant = data.get("health",{}).get("card_series")
	var series_next := series_catalog() if series_info == null else CardSeries.parse(series_info)
	if series_next.is_empty(): return _error("卡包资料无效，本地卡库已保留。")
	var fingerprints: Variant = data.get("fingerprints")
	if not _valid_fingerprints(fingerprints) or not data.get("cards") is Array or not data.get("removed") is Array: return _error("卡库增量格式无效，本地卡库已保留。")
	var entries: Array = []
	var catalog: Array = _catalogs.get(_bound_server, [])
	if data.get("keywords") != null:
		if not data.keywords is Array or Runtime.sha(data.keywords) != fingerprints.keywords: return _error("词条增量校验失败。")
		entries = data.keywords
		catalog = _catalog_from_entries(entries)
	if catalog.is_empty(): return _error("本地词条目录缺失，请重试同步。")
	if entries.is_empty():
		for definition in catalog: entries.append({"definition":definition,"definition_hash":Runtime.sha(definition)})
	var faction_entries: Variant = data.get("factions", null)
	if faction_entries != null and (not faction_entries is Array or FactionCatalog.parse(faction_entries).size() != faction_entries.size() or Runtime.sha(faction_entries) != fingerprints.factions): return _error("阵营增量校验失败。")
	var lifecycle: Variant = data.get("lifecycle", null)
	if lifecycle != null:
		if not lifecycle is Dictionary or Runtime.sha(lifecycle) != fingerprints.lifecycle: return _error("归档状态校验失败。")
		for kind in ["cards", "keywords", "factions"]:
			if not lifecycle.get(kind) is Dictionary or lifecycle[kind].values().any(func(v): return not v is Dictionary): return _error("归档状态无效。")
	var seen := {}
	for raw in data.cards:
		if not raw is Dictionary or not raw.get("card_id") is String: return _error("卡牌增量无效。")
		var id: String = raw.card_id
		if seen.has(id) or (not trusted and (fingerprints.cards.get(id) != Runtime.sha(raw) or _checked_record(raw, catalog).is_empty())): return _error("卡牌增量校验失败，本地卡库已保留。")
		seen[id] = true
	for id in data.removed:
		if not id is String or not _uuid_string(id) or fingerprints.cards.has(id): return _error("卡牌移除清单无效。")
	# A truncated response must not acknowledge a card that was never downloaded.
	var before := _catalog_manifest()
	for id in fingerprints.cards:
		if not seen.has(id) and before.get("cards", {}).get(id) != fingerprints.cards[id]: return _error("卡库增量不完整，请重试。")
	if data.cards.is_empty() and data.removed.is_empty() and data.get("keywords") == null and faction_entries == null and lifecycle == null and before == fingerprints and series_next == series_catalog():
		return {"ok":true,"error":"","entries":entries}
	var previous := {"series":_series_catalogs.duplicate(true),"cards":cards.duplicate(true),"deck_ids":deck_ids.duplicate(),"headquarters":headquarters_id,"local_decks":local_decks.duplicate(true),"catalogs":_catalogs.duplicate(true),"factions":_faction_catalogs.duplicate(true),"content":_content_catalogs.duplicate(true),"fingerprints":_catalog_fingerprints.duplicate(true),"main":main_faction_id,"pending":pending_sync.duplicate(true),"outbox":_outbox.duplicate(true),"keywords":_keyword_archive.duplicate(true),"deck_publish":deck_publish_pending.duplicate(true)}
	_series_catalogs[_bound_server] = series_next
	_catalogs[_bound_server] = catalog
	_remember_keywords(catalog, false)
	if faction_entries != null: _faction_catalogs[_bound_server] = faction_entries
	_activate_factions()
	_activate_keywords()
	var installed := 0
	for raw in data.cards:
		if _ingest_remote(raw, _bound_server, catalog).is_empty(): push_error("Card failed validation: " + str(raw.get("card_id")))
		installed += 1
		if installed % 6 == 0 and is_inside_tree(): await get_tree().process_frame
	var current_lifecycle: Dictionary = lifecycle.duplicate(true) if lifecycle != null else _content_catalogs.get(_bound_server, {"cards":{},"keywords":{},"factions":{}}).duplicate(true)
	for id in data.removed:
		if not current_lifecycle.cards.has(id): current_lifecycle.cards[id] = {"deleted":true}
	_apply_content_lifecycle(current_lifecycle)
	_follow_latest_decks()
	_infer_deck_factions()
	_catalog_fingerprints[_scope()] = fingerprints.duplicate(true)
	if not save_profile():
		cards = previous.cards; deck_ids = previous.deck_ids; headquarters_id = previous.headquarters; local_decks = previous.local_decks
		_series_catalogs = previous.series
		_catalogs = previous.catalogs; _faction_catalogs = previous.factions; _content_catalogs = previous.content
		_catalog_fingerprints = previous.fingerprints; main_faction_id = previous.main
		pending_sync = previous.pending; _outbox = previous.outbox; _keyword_archive = previous.keywords; deck_publish_pending = previous.deck_publish
		_activate_factions(); _activate_keywords()
		return _error("卡库更新未能保存，仍使用原有本地卡库。")
	return {"ok":true,"error":"","entries":entries}

func _parse_catalog(text: String) -> Dictionary:
	var parsed := Runtime.parse_json(text, 16777216)
	if not parsed.ok or not parsed.value is Dictionary: return _error("卡库无法读取。")
	var bundle: Dictionary = parsed.value
	var version: Variant = bundle.get("catalog_version")
	if not (version is int or version is float) or int(version) < 1 or not _valid_fingerprints(bundle.get("fingerprints")) or not bundle.get("cards") is Array: return _error("卡库格式无效。")
	return {"ok":true,"error":"","bundle":bundle,"version":int(version)}

## Mirrors the former service delta so unchanged cards are not recompiled.
func _catalog_delta(bundle: Dictionary) -> Dictionary:
	var fingerprints: Dictionary = bundle.fingerprints
	var known := _catalog_manifest()
	var known_cards: Dictionary = known.get("cards", {})
	return {
		"fingerprints":fingerprints,
		"health":bundle.get("health",{}),
		"cards":bundle.cards.filter(func(card): return not card is Dictionary or known_cards.get(card.get("card_id")) != fingerprints.cards.get(card.get("card_id"))),
		"removed":known_cards.keys().filter(func(id): return not fingerprints.cards.has(id)),
		"keywords":null if known.get("keywords") == fingerprints.keywords else bundle.get("keywords"),
		"factions":null if known.get("factions") == fingerprints.factions else bundle.get("factions"),
		"lifecycle":null if known.get("lifecycle") == fingerprints.lifecycle else bundle.get("lifecycle"),
	}

func _catalog_note() -> String:
	return "%s · %d 张" % ["GitHub 卡库" if catalog_version > _bundled_version else "内置卡库", latest_cards().size()]

func _install_bundled_catalog() -> Dictionary:
	if not FileAccess.file_exists(BUNDLED_CATALOG): return _error("游戏包缺少内置卡库。")
	var loaded := _parse_catalog(FileAccess.get_file_as_string(BUNDLED_CATALOG))
	if not loaded.ok: return loaded
	_bundled_version = loaded.version
	# A newer catalog already pulled from GitHub must survive restarts of an older installer.
	if catalog_version > _bundled_version and not _catalog_manifest().is_empty(): return {"ok":true,"error":""}
	var applied: Dictionary = await _apply_catalog_delta(_catalog_delta(loaded.bundle), true)
	if applied.ok:
		catalog_version = _bundled_version
		save_profile()
	return applied

func refresh() -> void:
	_ensure_context()
	if _refresh_running: return
	if not bundled_ready:
		_refresh_running = true
		_refresh_serial += 1
		# First launch validates every card; let the loading screen draw before that work starts.
		if is_inside_tree(): await get_tree().process_frame
		var applied: Dictionary = await _install_bundled_catalog()
		_refresh_running = false
		bundled_ready = applied.ok
		if applied.ok: connection_note = _catalog_note()
		else:
			connection_note = "内置卡库加载失败"
			message.emit(applied.error)
		changed.emit()
	if bundled_ready: _pull_github_catalog()

func _fetch_github_catalog() -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 30.0
	http.body_size_limit = 16777216
	http.max_redirects = 0
	add_child(http)
	var headers := PackedStringArray()
	if not catalog_etag.is_empty(): headers.append("If-None-Match: " + catalog_etag)
	if http.request(CardArtCache.remote_root + "data/catalog.json", headers) != OK:
		http.queue_free()
		return _error("无法发起请求。")
	var response: Array = await http.request_completed
	http.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or not int(response[1]) in [200, 304]: return _error("GitHub 卡库暂不可用。", int(response[1]))
	var etag := ""
	for header in response[2]:
		if str(header).to_lower().begins_with("etag:"): etag = str(header).substr(5).strip_edges()
	return {"ok":true,"error":"","code":int(response[1]),"text":response[3].get_string_from_utf8(),"etag":etag}

## Runs in the background; every failure simply leaves the installed catalog in place.
func _pull_github_catalog() -> void:
	if _pull_running or Time.get_ticks_msec() < _pull_after: return
	_pull_running = true
	_pull_after = Time.get_ticks_msec() + GITHUB_PULL_INTERVAL_MS
	var fetched := await _fetch_github_catalog()
	if fetched.ok and fetched.code == 200: await _apply_github_catalog(fetched)
	_pull_running = false

func _apply_github_catalog(fetched: Dictionary) -> void:
	var loaded := _parse_catalog(fetched.text)
	if not loaded.ok:
		connection_note = "GitHub 卡库无效，已保留当前卡库"
		changed.emit()
		return
	if loaded.version <= catalog_version:
		# Only an equal version proves this ETag's content is installed; a stale CDN copy must be fetched again.
		if loaded.version == catalog_version:
			catalog_etag = fetched.etag
			save_profile()
		return
	while _refresh_running: await get_tree().process_frame
	_refresh_running = true
	var applied: Dictionary = await _apply_catalog_delta(_catalog_delta(loaded.bundle))
	_refresh_running = false
	if applied.ok:
		catalog_version = loaded.version
		catalog_etag = fetched.etag
		save_profile()
		connection_note = _catalog_note()
	else: connection_note = "GitHub 卡库校验失败，已保留当前卡库"
	changed.emit()

func _refresh_legacy() -> void:
	_ensure_context()
	if _refresh_running: return
	_refresh_running = true
	_refresh_serial += 1
	var serial := _refresh_serial
	var origin := _bound_server
	var credential := _bound_token
	var health := await request("/health")
	if not _context_current(serial,origin,credential): return
	online = health.ok
	model_configured = bool(health.get("data",{}).get("configured",false)) if online else false
	if not online:
		connection_note = "离线"
		_finish_refresh(serial)
		return
	central_mode = health.data.get("mode","") == "central"
	var faction_response := await request("/v1/public/factions" if central_mode else "/v1/factions")
	if not _context_current(serial,origin,credential): return
	if not faction_response.ok or not faction_response.data.get("factions") is Array:
		connection_note = "阵营加载失败"
		_finish_refresh(serial)
		return
	var series_info := CardSeries.parse(health.data.get("card_series",{}))
	if not series_info.is_empty(): _series_catalogs[origin] = series_info
	_faction_catalogs[origin] = faction_response.data.factions
	_activate_factions()
	_infer_deck_factions()
	if central_mode:
		var me := await request("/v1/me")
		if not _context_current(serial,origin,credential): return
		authenticated = me.ok and _uuid_string(str(me.data.get("owner_id",""))) and me.data.get("display_name") is String
		if not authenticated:
			connection_note = "已连接 · 未登录"
			_finish_refresh(serial)
			return
		account_identity = me.data.duplicate(true)
		_stash_pending()
		_bound_owner = str(me.data.owner_id)
		settings.owner_id = _bound_owner
		settings.player_name = str(me.data.display_name)
		_credentials[origin] = {"api_token":credential,"owner_id":_bound_owner}
		pending_sync = _outbox.get(_scope(),{}).duplicate(true)
		if bool(account_identity.get("must_change_password", false)):
			connection_note = "请修改初始密码"
			_finish_refresh(serial)
			return
	else: authenticated = false
	var registry := await request("/v1/keywords")
	if not _context_current(serial,origin,credential): return
	var entries: Variant = registry.get("data",{}).get("definitions",[])
	var catalog := _catalog_from_entries(entries) if entries is Array else []
	if not registry.ok or catalog.is_empty():
		connection_note = "词条加载失败"
		_finish_refresh(serial)
		return
	_catalogs[origin] = catalog
	_remember_keywords(catalog,false)
	_activate_keywords()
	var library := await request("/v1/cards")
	if not _context_current(serial,origin,credential): return
	var remote_cards: Variant = library.get("data",{}).get("cards",[])
	if not library.ok or not remote_cards is Array:
		connection_note = "卡库加载失败"
		_finish_refresh(serial)
		return
	_apply_content_lifecycle(library.data.get("lifecycle"))
	for record in remote_cards:
		if record is Dictionary: _ingest_remote(record,origin,catalog)
	_follow_latest_decks()
	if central_mode:
		await _sync_confirmed_content(remote_cards,entries)
		if not _context_current(serial,origin,credential): return
		connection_note = "已同步" if pending_sync.is_empty() and not _has_unsynced() else "待同步"
		if not _sync_warning.is_empty(): connection_note = _sync_warning
	else: connection_note = "已连接" if model_configured else "已连接 · 模型未配置"
	_finish_refresh(serial)

func sign_in(invite_code: String, display_name: String) -> Dictionary:
	return await _account_request("/v1/sessions", {"invite_code":invite_code,"display_name":display_name})

func account_login(username: String, password: String) -> Dictionary:
	return await _account_request("/v1/accounts/login", {"username":username,"password":password})

func account_register(username: String, password: String, link_existing: bool = false) -> Dictionary:
	return await _account_request("/v1/account/link" if link_existing else "/v1/accounts/register", {"username":username,"password":password})

func change_password(current_password: String, new_password: String) -> Dictionary:
	return await _account_request("/v1/account/password", {"current_password":current_password,"new_password":new_password})

func _account_request(path: String, body: Dictionary) -> Dictionary:
	if _account_busy: return _error("正在登录，请稍后。")
	_ensure_context()
	var origin := _bound_server
	var context := _context_epoch
	_account_busy = true
	var result := await request(path, HTTPClient.METHOD_POST, body)
	_ensure_context()
	if _bound_server != origin or _context_epoch != context:
		_account_busy = false
		return _error("连接已改变，请重新登录。")
	var adopted := await _adopt_account(result)
	_account_busy = false
	return adopted

func account_logout() -> Dictionary:
	if _account_busy: return _error("请等待当前账号操作完成。")
	_ensure_context()
	var origin := _bound_server
	var credential := _bound_token
	var result := await request("/v1/logout", HTTPClient.METHOD_POST, {})
	if not result.ok: return result
	_ensure_context()
	if origin != _bound_server or credential != _bound_token: return result
	settings.api_token = ""
	settings.owner_id = ""
	_ensure_context()
	_credentials[origin] = {"api_token":"","owner_id":""}
	account_identity = {}
	connection_note = "已连接 · 未登录"
	save_profile()
	changed.emit()
	return result

func _adopt_account(result: Dictionary) -> Dictionary:
	if not result.ok: return result
	var data: Dictionary = result.data
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_-]{43}$")
	if not _uuid_string(str(data.get("owner_id",""))) or pattern.search(str(data.get("access_token",""))) == null: return _error("服务器返回了无效玩家身份。")
	_stash_pending()
	_bound_token = str(data.access_token)
	_bound_owner = str(data.owner_id)
	settings.api_token = _bound_token
	settings.owner_id = _bound_owner
	settings.player_name = str(data.get("display_name","指挥官"))
	_credentials[_bound_server] = {"api_token":_bound_token,"owner_id":_bound_owner}
	_context_epoch += 1
	_refresh_serial += 1
	_refresh_running = false
	pending_sync = _outbox.get(_scope(),{}).duplicate(true)
	central_mode = true
	authenticated = true
	account_identity = data.duplicate(true)
	account_identity.erase("access_token")
	if not save_profile(): return _error("身份已创建但无法保存本机档案，请检查目录权限。")
	await refresh()
	return result

func create_draft(definition: Dictionary) -> Dictionary:
	var compiled := Runtime.compile_card(definition,keyword_definitions)
	if not compiled.ok: return compiled
	if online and (not central_mode or authenticated):
		var result := await request("/v1/card-drafts",HTTPClient.METHOD_POST,{"request_id":uuid(),"definition":compiled.source})
		if not result.ok: return result
		return {"ok":true,"error":"","draft":result.data.get("result",{})}
	return {"ok":true,"error":"","draft":{"draft_id":uuid(),"draft_hash":compiled.definition_hash,"definition":compiled.source,"compiled_program_hash":compiled.compiled_program_hash,"keyword_bindings":compiled.keyword_bindings,"frozen_keywords":keyword_definitions.duplicate(true),"local_only":true,"rules_text":Runtime.rules_text(compiled.definition)}}

func confirm_draft(draft: Dictionary) -> Dictionary:
	if bool(draft.get("local_only",false)):
		var candidate := {"card_id":str(draft.get("draft_id",uuid())),"revision":1,"definition":draft.get("definition",{}),"definition_hash":draft.get("draft_hash",""),"compiled_program_hash":draft.get("compiled_program_hash",""),"keyword_bindings":draft.get("keyword_bindings",[]),"frozen_keywords":draft.get("frozen_keywords",keyword_definitions),"series":int(series_catalog().get("current",CardSeries.CURRENT)),"local_only":true,"local_authored":true,"cloud_refs":{}}
		var checked := _checked_record(candidate)
		if checked.is_empty(): return _error("本地草稿已变化，请重新预览。")
		for record in cards:
			if _content_key(record) == _content_key(checked): return {"ok":true,"error":"","card":record,"data":record}
		cards.append(checked)
		_remember_keywords(checked.frozen_keywords,true)
		if not save_profile():
			cards.erase(checked)
			return _error("无法保存卡牌，请检查本地档案目录。")
		changed.emit()
		return {"ok":true,"error":"","card":checked,"data":checked}
	_ensure_context()
	var context: Dictionary = _draft_contexts.get(str(draft.get("draft_id","")),{})
	if context.get("server") != _bound_server or context.get("owner_id") != _bound_owner: return _error("该草稿属于另一服务器或玩家，请重新预览。")
	var result := await request("/v1/cards",HTTPClient.METHOD_POST,{"request_id":uuid(),"draft_id":draft.get("draft_id",""),"draft_hash":draft.get("draft_hash","")})
	if not result.ok: return result
	var saved := _ingest_remote(result.data,_bound_server,keyword_definitions)
	if saved.is_empty(): return _error("服务器卡牌校验失败。")
	saved.local_authored = true
	save_profile()
	changed.emit()
	await refresh()
	return {"ok":true,"error":"","card":saved,"data":saved}

func _has_unsynced() -> bool:
	for card in cards:
		if not _sync_deleted(card) and bool(card.get("local_authored",false)) and not _has_cloud_ref(card,_bound_server): return true
	var known: Dictionary = {}
	for keyword in _catalogs.get(_bound_server,[]): known[Runtime.sha(keyword)] = true
	for digest in _keyword_archive:
		if not content_status("keywords",str(_keyword_archive[digest].definition.id)).get("deleted",false) and _keyword_archive[digest].authored and not known.has(digest): return true
	return false

func _build_sync_job(remote_keywords: Array) -> Dictionary:
	var known: Dictionary = {}
	for definition in remote_keywords: known[_keyword_id(definition)] = Runtime.sha(definition)
	var added: Dictionary = {}
	var dependencies: Dictionary = {}
	var payload := {"request_id":uuid(),"cards":[],"keywords":[]}
	for card in cards:
		if _sync_deleted(card) or not bool(card.get("local_authored",false)) or _has_cloud_ref(card,_bound_server): continue
		var missing: Array = []
		var conflict := false
		for keyword in record_keywords(card):
			var identity := _keyword_id(keyword)
			var digest := Runtime.sha(keyword)
			if (known.has(identity) and known[identity] != digest) or (added.has(identity) and Runtime.sha(added[identity]) != digest):
				conflict = true
				break
			if not known.has(identity) and not added.has(identity): missing.append(keyword)
		if conflict:
			_sync_warning = "部分创作的词条版本与当前服务器冲突，原卡已保留在本机"
			continue
		var next := payload.duplicate(true)
		next.keywords.append_array(missing)
		next.cards.append({"local_card_id":card.card_id,"definition":card.definition,"definition_hash":card.definition_hash})
		if next.cards.size() > 100 or next.keywords.size() > 256 or JSON.stringify(next).to_utf8_buffer().size() > SYNC_BYTES: break
		payload = next
		for keyword in missing: added[_keyword_id(keyword)] = keyword
		for keyword in record_keywords(card): dependencies[_keyword_id(keyword)] = keyword
	for entry in _keyword_archive.values():
		if not entry.authored or content_status("keywords",str(entry.definition.id)).get("deleted",false): continue
		var keyword: Dictionary = entry.definition
		var identity := _keyword_id(keyword)
		if known.has(identity) or added.has(identity): continue
		var next := payload.duplicate(true)
		next.keywords.append(keyword)
		if next.keywords.size() > 256 or JSON.stringify(next).to_utf8_buffer().size() > SYNC_BYTES: break
		payload = next
		added[identity] = keyword
	if payload.cards.is_empty() and payload.keywords.is_empty(): return {}
	return {"server":_bound_server,"owner_id":_bound_owner,"payload":payload,"dependencies":dependencies.values(),"retry_at":0}

func _validate_sync_response(job: Dictionary, data: Dictionary) -> Array:
	if not data.get("cards") is Array or not data.get("mappings") is Array or not data.get("keyword_registry_hash") is String: return []
	if data.mappings.size() != job.payload.cards.size(): return []
	var requested: Dictionary = {}
	for item in job.payload.cards: requested[item.local_card_id] = item
	var matched: Array = []
	for mapping in data.mappings:
		if not mapping is Dictionary or not requested.has(mapping.get("local_card_id")): return []
		var source: Dictionary = requested[mapping.local_card_id]
		var compiled := Runtime.compile_card(source.definition,job.dependencies)
		if not compiled.ok: return []
		var found: Dictionary = {}
		for raw in data.cards:
			if raw is Dictionary and raw.get("card_id") == mapping.get("card_id") and raw.get("definition_hash") == source.definition_hash:
				var checked := _checked_record(raw,job.dependencies)
				if not checked.is_empty() and checked.compiled_program_hash == compiled.compiled_program_hash: found = checked
		if found.is_empty(): return []
		matched.append({"local_card_id":mapping.local_card_id,"record":found})
		requested.erase(mapping.local_card_id)
	return matched

func _sync_confirmed_content(_remote_cards: Array, remote_entries: Array) -> void:
	_sync_warning = ""
	if not central_mode or not authenticated: return
	var origin := _bound_server
	var owner := _bound_owner
	var scope := _scope()
	var now := int(Time.get_unix_time_from_system())
	if now < int(_sync_after.get(scope,0)): return
	if pending_sync.is_empty(): pending_sync = _build_sync_job(_catalog_from_entries(remote_entries))
	if pending_sync.is_empty(): return
	if pending_sync.get("server") != origin or pending_sync.get("owner_id") != owner: return
	if bool(pending_sync.get("blocked",false)):
		_sync_warning = "同步存在校验冲突，原卡与待同步内容已保留在本机"
		return
	if now < int(pending_sync.get("retry_at",0)): return
	if not save_profile():
		_sync_warning = "本机档案无法保存，已暂停同步"
		return
	var submitted := pending_sync.duplicate(true)
	var result := await request("/v1/card-sync",HTTPClient.METHOD_POST,submitted.payload)
	if origin != _bound_server or owner != _bound_owner or result.get("stale",false): return
	_sync_after[scope] = now + 7
	if not result.ok:
		pending_sync["last_error"] = result.error
		pending_sync["retry_at"] = now + (60 if result.code == 429 else 15)
		pending_sync["blocked"] = result.code in [400,409,410,413,422]
		save_profile()
		return
	var mapped := _validate_sync_response(submitted,result.data)
	if mapped.size() != submitted.payload.cards.size() or (submitted.payload.cards.is_empty() and not result.data.get("mappings") is Array):
		pending_sync["retry_at"] = now + 30
		_sync_warning = "同步响应校验失败，原卡与待同步内容已保留"
		save_profile()
		return
	var original_cards := cards.duplicate(true)
	var original_deck := deck_ids.duplicate()
	for item in mapped: _ingest_remote(item.record,origin,submitted.dependencies,str(item.local_card_id))
	var catalog: Array = _catalogs.get(origin,Runtime.builtin_keywords()).duplicate(true)
	var identities: Dictionary = {}
	for keyword in catalog: identities[_keyword_id(keyword)] = true
	for keyword in submitted.payload.keywords:
		if not identities.has(_keyword_id(keyword)):
			catalog.append(keyword)
			identities[_keyword_id(keyword)] = true
	_catalogs[origin] = catalog
	_remember_keywords(catalog,false)
	_activate_keywords()
	pending_sync = {}
	_outbox.erase(scope)
	_deduplicate_cards()
	if not save_profile():
		cards = original_cards
		deck_ids = original_deck
		pending_sync = submitted
		_outbox[scope] = submitted.duplicate(true)

func reset_sync_queue() -> bool:
	_ensure_context()
	if _refresh_running: return false
	if pending_sync.is_empty(): return true
	var previous := pending_sync.duplicate(true)
	var previous_outbox := _outbox.duplicate(true)
	var scope := _scope()
	# Keep the exact old transaction for recovery/audit; rebuild only from retained cards.
	_outbox[scope + "|archived:" + str(previous.get("payload",{}).get("request_id",uuid()))] = previous
	_outbox.erase(scope)
	pending_sync = {}
	_sync_after.erase(scope)
	_sync_warning = ""
	if not save_profile():
		pending_sync = previous
		_outbox = previous_outbox
		return false
	changed.emit()
	return true
