extends SceneTree
const Store = preload("res://scripts/app_store.gd")
const Runtime = preload("res://scripts/core/card_runtime.gd")
var checks := 0
var failures := 0
var store: AppStore

func _initialize() -> void:
	if OS.get_environment("FRONTLINE_PROFILE_PATH").is_empty() or OS.get_environment("FRONTLINE_TEST_SERVER_URL").is_empty():
		push_error("Run with tests/run_cloud_store_test.mjs; isolated profile required")
		quit(1)
		return
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func unit(name_value: String) -> Dictionary:
	return {"schema_version":"1.0.0","ruleset_version":"frontline-1","name":name_value,"faction_id":"11111111-1111-4111-8111-111111111111","flavor_text":"","kind":"unit","unit_class":"infantry","cost":2,"operation_cost":1,"attack":2,"health":3,"keywords":[],"play_target":null,"abilities":[],"tokens":[],"appearance":{"emblem":"infantry"}}

func keyword(index: int, amount: int = 1) -> Dictionary:
	return {"schema_version":"1.0.0","ruleset_version":"frontline-1","id":"example.test_%d" % index,"version":1,"name":"补给 %d" % index,"aliases":[],"description":"部署时抽牌。","parameters":{},"implementation":{"kind":"template","abilities":[{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":amount}]}]}}

func fresh_store() -> void:
	store = Store.new()
	root.add_child(store)
	store.set_process(false)

func _run() -> void:
	fresh_store()
	store.settings.backend_url = OS.get_environment("FRONTLINE_TEST_SERVER_URL")
	store.save_profile()
	check(store._server("http://example.org:80").is_empty(),"Public HTTP must never carry credentials")
	check(store._server("https://example.org/path").is_empty(),"Origin cannot include redirect/path suffix")
	check(store._server("https://EXAMPLE.org:443/") == "https://example.org","Origin normalized for credential scoping")
	store._faction_catalogs[store._bound_server] = [{"faction_id":"11111111-1111-4111-8111-111111111111","name":"测试主阵营","role":"major","color":"#496359","icon_id":null}]
	store._activate_factions()
	store.main_faction_id = "11111111-1111-4111-8111-111111111111"
	var original_ids: Array = []
	for index in 10:
		var draft := await store.create_draft(unit("历史单位" if index == 0 else "离线单位 %d" % index))
		check(draft.ok,"Offline draft compiles")
		var saved := await store.confirm_draft(draft.draft)
		check(saved.ok,"Offline card saves")
		original_ids.append(saved.card.card_id)
		for copy in 4: store.add_to_deck(saved.card.card_id)
	check(store.compile_deck().ok,"Original deck is valid")
	var login := await store.sign_in(OS.get_environment("FRONTLINE_TEST_INVITE"),"测试玩家")
	check(login.ok and store.authenticated,"Real central API session authenticates")
	check(not store.pending_sync.is_empty(),"Lost acknowledgement preserves pending sync")
	if store.pending_sync.is_empty():
		print("CLOUD STORE TESTS: early failure; ",store.connection_note)
		quit(1)
		return
	var request_id: String = store.pending_sync.payload.request_id
	var original_deck := store.deck_ids.duplicate()
	check(original_deck.size() == 40,"Refresh does not destroy offline deck")
	var token_a := str(store.settings.api_token)
	var owner_a := str(store.settings.owner_id)
	store.queue_free()
	await process_frame
	fresh_store()
	check(store.pending_sync.payload.request_id == request_id,"Outbox survives app restart with same idempotency ID")
	store.pending_sync.retry_at = 0
	store._outbox[store._scope()] = store.pending_sync.duplicate(true)
	store._sync_after.clear()
	await store.refresh()
	check(store.pending_sync.is_empty(),"Retry applies acknowledged transaction")
	check(store.deck_ids == original_deck,"Cloud synchronization preserves local card IDs in deck")
	check(store.cards.size() == 11,"Shared latest revision plus original ten cards deduplicated")
	var refs := store.cloud_deck_refs()
	check(refs.ok,"Synchronized deck has exact server references")
	var stats := await store.request("/test-stats")
	check(stats.data.sync_ids.size() == 2 and stats.data.sync_ids[0] == stats.data.sync_ids[1],"Lost acknowledgement retry sends identical request ID")
	check(refs.deck[0].revision == 1 and refs.deck[0].card_id == stats.data.old_id,"Same source hash maps to historical server revision 1")
	check(store.get_card(original_ids[0]).definition.attack == 2,"Shared revision 2 never overwrites frozen original card")
	await store.refresh()
	check(store.cards.size() == 11,"Repeated refresh does not duplicate shared cards")
	check(store.latest_cards().size() == 10,"Default collection shows ten card identities, only latest revisions")
	var newest: Dictionary = store.latest_cards().filter(func(c): return c.definition.name == "历史单位")[0]
	check(newest.revision == 2 and newest.definition.attack == 4,"Latest card is revision two")
	var historical := await store.load_card_version(newest, 1)
	check(historical.ok and historical.card.definition.attack == 2,"Explicitly select historical version")
	check(store.deck_ids == original_deck and store.cloud_deck_refs().deck[0].revision == 1,"Viewing history never upgrades existing deck")
	# Identical scripts in a new revision still have separate, immutable references.
	var identical: Dictionary = newest.duplicate(true)
	identical.card_id = stats.data.old_id
	identical.revision = 3
	var saved_new := store._ingest_remote(identical,store._bound_server,store.keyword_definitions)
	check(saved_new.card_id != newest.card_id and newest.cloud_refs[store._bound_server].revision == 2,"Identical new revision never retargets old version")
	check(store.latest_cards().size() == 10,"New identical revision replaces only default display")
	check(store.card_author(saved_new) == "Fixture publisher","Author retained in game record")
	var tampered: Dictionary = store.cards[0].duplicate(true)
	tampered.compiled_program_hash = "0".repeat(64)
	check(store._checked_record(tampered).is_empty(),"Reject server compiled hash mismatch")
	# Pending jobs are isolated by both origin and owner, including across restarts.
	store.pending_sync = {"server":store._bound_server,"owner_id":owner_a,"payload":{"request_id":Store.uuid(),"cards":[],"keywords":[keyword(900)]},"dependencies":[],"retry_at":int(Time.get_unix_time_from_system())+3600}
	var queued_id: String = store.pending_sync.payload.request_id
	store.save_profile()
	store.settings.backend_url = OS.get_environment("FRONTLINE_TEST_OTHER_URL")
	store.save_profile()
	check(store.settings.api_token == "" and store.pending_sync.is_empty(),"Changing center never forwards old access token or pending job")
	await store.request("/health")
	var other_stats := await store.request("/test-stats")
	check(other_stats.data.second_auth.all(func(value): return value == ""),"Other center observed no previous bearer credential")
	var other_login := await store.sign_in(OS.get_environment("FRONTLINE_TEST_INVITE"),"另一服务器玩家")
	check(other_login.ok and store.settings.owner_id != owner_a,"Each center has independent identity")
	store.settings.backend_url = OS.get_environment("FRONTLINE_TEST_SERVER_URL")
	store.save_profile()
	check(store.settings.api_token == token_a and store.settings.owner_id == owner_a,"Returning center restores only its own cached identity")
	check(store.pending_sync.payload.request_id == queued_id,"Returning center restores original owner outbox")
	var retained_cards := store.cards.duplicate(true)
	var retained_deck := store.deck_ids.duplicate()
	check(store.reset_sync_queue() and store.pending_sync.is_empty() and store._outbox.has(store._scope()+"|archived:"+queued_id) and store.cards == retained_cards and store.deck_ids == retained_deck,"Queue rebuild archives exact batch and preserves all cards/deck")
	# Requeue the original transaction to exercise account isolation independently.
	store.pending_sync = store._outbox[store._scope()+"|archived:"+queued_id].duplicate(true)
	store.save_profile()
	await store.sign_in(OS.get_environment("FRONTLINE_TEST_INVITE"),"同服第二玩家")
	check(store.settings.owner_id != owner_a and store.pending_sync.is_empty(),"Changing account never replays another account outbox")
	check(store._outbox.has(OS.get_environment("FRONTLINE_TEST_SERVER_URL")+"|"+owner_a),"Other owner's original outbox retained")
	_test_batches_and_freezing()
	store.queue_free()
	await process_frame
	print("CLOUD STORE TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _test_batches_and_freezing() -> void:
	# Unit-test batching against an isolated in-memory collection, never the real profile.
	store.cards = []
	store.deck_ids = []
	store._keyword_archive = {}
	var definitions: Array = Runtime.builtin_keywords()
	for index in 260: definitions.append(keyword(index))
	store._remember_keywords(definitions,true)
	var source := unit("依赖优先")
	source.keywords = [{"id":"example.test_259","version":1,"params":{}}]
	var compiled := Runtime.compile_card(source,definitions)
	check(compiled.ok,"Dependent card fixture compiles")
	var record := store._checked_record({"card_id":Store.uuid(),"revision":1,"definition":source,"definition_hash":compiled.definition_hash,"compiled_program_hash":compiled.compiled_program_hash},definitions)
	record["local_authored"] = true
	record["cloud_refs"] = {}
	store.cards.append(record)
	var batch := store._build_sync_job(Runtime.builtin_keywords())
	check(batch.payload.cards.size() == 1 and batch.payload.keywords.size() == 256,"Batch reserves dependency first while obeying keyword cap")
	check(batch.payload.keywords[0].id == "example.test_259","Referenced keyword never stranded behind 256 unrelated definitions")
	check(JSON.stringify(batch.payload).to_utf8_buffer().size() <= 256*1024,"Batch respects byte cap")
	check(Runtime.compile_card(source,batch.dependencies).ok,"Persisted sync dependencies independently recompile card")
	var replacement := keyword(259,2)
	store._catalogs[store._bound_server] = Runtime.builtin_keywords()+[replacement]
	store._remember_keywords([replacement],false)
	store._activate_keywords()
	check(store.compile_record(record).compiled_program_hash == compiled.compiled_program_hash,"Other center's same id/version cannot alter frozen card meaning")
	var blocked := store._build_sync_job(Runtime.builtin_keywords()+[replacement])
	check(blocked.is_empty() or blocked.payload.cards.is_empty(),"Conflicting immutable keyword does not upload card against wrong definition")
	store._keyword_archive = {}
	store.cards = []
	for index in 101:
		var item := unit("批次卡牌 %d" % index)
		var result := Runtime.compile_card(item,[])
		store.cards.append(store._checked_record({"card_id":Store.uuid(),"revision":1,"definition":item,"definition_hash":result.definition_hash,"local_authored":true,"cloud_refs":{},"frozen_keywords":[]}))
	batch = store._build_sync_job(Runtime.builtin_keywords())
	check(batch.payload.cards.size() == 100,"Card sync never exceeds 100 cards per batch")
