extends SceneTree
## Real AppStore -> Node HTTP integration. Run through run_service_bridge.ps1.
const StoreClass = preload("res://scripts/app_store.gd")
const Runtime = preload("res://scripts/core/card_runtime.gd")

var store: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		push_error("SERVICE_BRIDGE_FAIL: " + description)
	return condition

func _run() -> void:
	var url := OS.get_environment("FRONTLINE_BRIDGE_URL")
	var profile := OS.get_environment("FRONTLINE_PROFILE_PATH").replace("\\", "/")
	if not check(url == "http://127.0.0.1:18787", "Bridge test must use isolated port 18787"):
		finish()
		return
	if not check(profile.contains("/.runtime/test-bridge-") and not FileAccess.file_exists(profile), "Bridge test requires a fresh isolated profile"):
		finish()
		return
	store = StoreClass.new()
	root.add_child(store)
	store.settings.backend_url = url
	store.settings.api_token = ""
	check(store.cards.is_empty(), "Fresh Godot profile has no predefined cards")
	var health: Dictionary = await store.request("/health")
	if not check(health.ok and health.data.get("ok", false), "Godot HTTPRequest reaches actual Node HTTP listener"):
		finish()
		return
	check(not health.data.configured, "Isolated backend has no model key")
	check(int(health.data.card_count) == 0, "Isolated persistent server starts with no cards")
	await store.refresh()
	check(store.online and not store.model_configured, "AppStore recognizes connected backend without configured model")
	check(store.keyword_definitions.size() == 2, "AppStore loads exactly the two builtin keywords")
	check(store.cards.is_empty(), "Refresh does not manufacture starter cards")
	var definition := card_definition("桥接测试 Café")
	var preview: Dictionary = await store.create_draft(definition)
	if not check(preview.get("ok", false), "Actual manual draft API returns a usable Godot preview"):
		finish()
		return
	check(not str(preview.draft.draft_id).begins_with("local-"), "Connected preview is server-owned, not offline fallback")
	check(store.cards.is_empty(), "Preview alone leaves AppStore library empty")
	var compiled: Dictionary = Runtime.compile_card(definition, store.keyword_definitions)
	check(compiled.ok and compiled.definition_hash == preview.draft.draft_hash, "Godot and Node source definition hashes agree")
	check(compiled.compiled_program_hash == preview.draft.compiled_program_hash, "Godot and Node compiled hashes agree over real HTTP")
	var imported: Dictionary = await store.confirm_draft(preview.draft)
	if not check(imported.ok, "AppStore confirms server draft and refreshes library"):
		finish()
		return
	check(store.cards.size() == 1, "Confirmed card appears once in AppStore")
	check(store.cards[0].definition_hash == preview.draft.draft_hash, "Refresh accepts checked server record with matching hash")
	var transaction := {"request_id":StoreClass.uuid(), "draft_id":preview.draft.draft_id, "draft_hash":preview.draft.draft_hash}
	var once: Dictionary = await store.request("/v1/cards", HTTPClient.METHOD_POST, transaction)
	var twice: Dictionary = await store.request("/v1/cards", HTTPClient.METHOD_POST, transaction)
	check(once.ok and twice.ok and once.data.card_id == twice.data.card_id and once.data.card_id == store.cards[0].card_id, "Same confirmation ID and repeated draft confirmation preserve card identity")
	var conflict := transaction.duplicate(true)
	conflict.draft_hash = "0".repeat(64)
	var conflicting: Dictionary = await store.request("/v1/cards", HTTPClient.METHOD_POST, conflict)
	check(not conflicting.ok and int(conflicting.code) == 409 and conflicting.data.error.code == "IDEMPOTENCY_CONFLICT", "Changed body with same request ID reports conflict through AppStore")
	var invalid := definition.duplicate(true)
	invalid.script = "not executable"
	var rejected: Dictionary = await store.request("/v1/card-drafts", HTTPClient.METHOD_POST, {"request_id":StoreClass.uuid(), "definition":invalid})
	check(not rejected.ok and int(rejected.code) == 422 and not str(rejected.error).is_empty(), "Server rejects extra CardSpec fields and AppStore exposes readable error")
	await store.refresh()
	check(store.cards.size() == 1, "Rejected and repeated requests never add extra cards")
	var keyword := {"schema_version":"1.0.0", "ruleset_version":"frontline-1", "id":"custom.bridge_supply", "version":1, "name":"桥接补给", "aliases":[], "description":"登场时抽取参数指定数量的牌。", "parameters":{"amount":{"type":"integer", "minimum":1, "maximum":3}}, "implementation":{"kind":"template", "abilities":[{"trigger":"on_play", "effects":[{"op":"draw", "player":"owner", "amount":{"param":"amount"}}]}]}}
	var proposal: Dictionary = await store.request("/v1/keyword-imports", HTTPClient.METHOD_POST, {"request_id":StoreClass.uuid(), "definition":keyword})
	if check(proposal.ok and proposal.data.get("status", "") == "ready_to_register", "Keyword JSON creates separate registration preview"):
		await store.refresh()
		check(store.keyword_definitions.size() == 2, "Unconfirmed keyword is absent from approved catalog")
		var approved: Dictionary = await store.request("/v1/keyword-proposals/" + str(proposal.data.proposal_id) + "/confirm", HTTPClient.METHOD_POST, {"request_id":StoreClass.uuid(), "expected_revision":int(proposal.data.revision), "candidate_hash":proposal.data.candidate_hash})
		check(approved.ok and approved.data.get("registry_status", "") == "approved", "Keyword confirmation automatically validates and registers")
		await store.refresh()
		check(store.keyword_definitions.size() == 3, "AppStore accepts registered template in refreshed catalog")
		var templated := card_definition("桥接模板单位")
		templated.keywords = [{"id":"custom.bridge_supply", "version":1, "params":{"amount":2}}]
		var template_preview: Dictionary = await store.create_draft(templated)
		if check(template_preview.ok, "AppStore and server accept exact newly registered keyword reference"):
			var expansion: Dictionary = Runtime.compile_card(templated, store.keyword_definitions)
			check(expansion.compiled_program_hash == template_preview.draft.compiled_program_hash, "Cross-runtime template expansion hash agrees")
			var saved: Dictionary = await store.confirm_draft(template_preview.draft)
			check(saved.ok and store.cards.size() == 2, "Template card confirms and refreshes as a second valid card")
	var job: Dictionary = await store.request("/v1/card-generations", HTTPClient.METHOD_POST, {"request_id":StoreClass.uuid(), "editor_revision":1, "source_text":"2费步兵，2攻3血，行动费1，无能力。", "clarification_answers":[], "schema_version":"1.0.0", "ruleset_version":"frontline-1"})
	if check(job.ok and int(job.code) == 202, "Missing-key generation still exposes a real asynchronous task"):
		var terminal: Dictionary = {}
		for attempt in range(30):
			var status: Dictionary = await store.request("/v1/card-generations/" + str(job.data.generation_id))
			if status.ok and not str(status.data.status) in ["queued", "running"]:
				terminal = status.data
				break
			await create_timer(0.1).timeout
		check(terminal.get("status", "") == "failed", "No-key task fails instead of returning fabricated card")
		check(terminal.get("error", {}).get("code", "") == "PROVIDER_NOT_CONFIGURED", "No-key failure is explicit and machine-readable")
	await store.refresh()
	check(store.cards.size() == 2, "Failed model generation preserves existing card library")
	check(FileAccess.file_exists(profile), "AppStore saves only isolated test profile")
	var restored := StoreClass.new()
	root.add_child(restored)
	check(restored.cards.size() == 2 and restored.keyword_definitions.size() == 3, "Fresh AppStore reloads both checked cards and registered keyword from isolated profile")
	restored.queue_free()
	finish()

func card_definition(name: String) -> Dictionary:
	return {"schema_version":"1.0.0", "ruleset_version":"frontline-1", "name":name, "flavor_text":"仅限隔离 HTTP 集成测试", "kind":"unit", "unit_class":"infantry", "cost":2, "operation_cost":1, "attack":2, "health":3, "keywords":[], "play_target":null, "abilities":[], "tokens":[], "appearance":{"emblem":"infantry"}}

func finish() -> void:
	print("SERVICE_BRIDGE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
