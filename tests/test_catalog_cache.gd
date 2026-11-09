extends SceneTree
var checks := 0
var failures := 0
class CountingStore extends "res://scripts/app_store.gd":
	var compilations := 0
	var saves := 0
	func _checked_record(raw: Dictionary, catalog: Array = []) -> Dictionary:
		compilations += 1
		return super._checked_record(raw, catalog)
	func save_profile() -> bool:
		saves += 1
		return super.save_profile()
func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(note)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var store := CountingStore.new()
	root.add_child(store)
	store.settings.backend_url = OS.get_environment("CACHE_TEST_URL")
	store.settings.api_token = OS.get_environment("CACHE_TEST_TOKEN")
	store._ensure_context()
	await store.refresh()
	check(store.cards.size() == 32 and store.authenticated, "first sync stores complete local catalog")
	if store.cards.size() != 32: print(store.connection_note); quit(1); return
	var before := FileAccess.get_file_as_string(store.profile_path)
	store.compilations = 0; store.saves = 0
	await store.refresh()
	check(store.compilations == 0, "unchanged sync never recompiles any card")
	check(store.saves == 0 and FileAccess.get_file_as_string(store.profile_path) == before, "unchanged sync does not rewrite local catalog")
	check(not store.is_processing(), "no periodic thirty-second full catalog polling")
	var statistics: Dictionary = (await store.request("/test/stats")).data
	check(statistics.requests == 2 and statistics.changed == [32,0], "each entry uses one update request and only initial request downloads all")
	store.queue_free(); await process_frame
	store = CountingStore.new(); root.add_child(store)
	check(store.cards.size() == 32 and not store.online, "restart reads local cards before any network response")
	store.compilations = 0; store.saves = 0
	await store.refresh()
	check(store.compilations == 0 and store.cards.size() == 32, "restart reuses persistent update fingerprints")
	var changes: Dictionary = (await store.request("/test/change", HTTPClient.METHOD_POST, {})).data
	var historical: Dictionary = store.latest_cards().filter(func(c): return c.cloud_refs[store._bound_server].card_id == changes.first)[0]
	var frozen_hash: String = historical.definition_hash
	store.deck_ids = [historical.card_id]
	store.compilations = 0
	await store.refresh()
	check(store.compilations == 6, "only changed/new/archived cards are checked, not all unchanged cards")
	check(store.cards.size() == 34 and store.latest_cards().size() == 32, "new revision preserved, archived hidden, new card added")
	check(store.get_card(historical.card_id).definition_hash == frozen_hash and store.deck_ids != [historical.card_id] and store.get_card(store.deck_ids[0]).revision==2, "deck follows latest revision while old record remains immutable")
	check(store.factions.values()[0].name == "已更新阵营", "faction edit synchronizes")
	statistics = (await store.request("/test/stats")).data
	check(statistics.changed[-1] == 3 and statistics.keywords[-1] == 0 and statistics.factions[-1] == 1, "delta downloads three changed cards and changed faction section only")
	var removed: Dictionary = store.cards.filter(func(c): return c.cloud_refs[store._bound_server].card_id == changes.removed)[0]
	store.deck_ids.append(removed.card_id)
	await store.request("/test/delete", HTTPClient.METHOD_POST, {})
	await store.refresh()
	check(store.get_card(removed.card_id).is_empty() and not removed.card_id in store.deck_ids, "remote deletion removes local card and invalid deck reference")
	check(store.latest_cards().size() == 32, "archive restore synchronizes while deleted card stays absent")
	var manifest := store._catalog_manifest().duplicate(true)
	var broken := {"cards":[],"removed":[],"keywords":null,"factions":null,"lifecycle":null,"fingerprints":manifest.duplicate(true)}
	broken.fingerprints.cards[changes.first] = "a".repeat(64)
	check(not store._apply_catalog_delta(broken).ok and store._catalog_manifest() == manifest, "truncated delta cannot advance persistent fingerprints")
	var original_path := store.profile_path
	store.profile_path = "res://project.godot/cannot-write.json"
	broken = {"cards":[],"removed":[],"keywords":null,"factions":null,"lifecycle":null,"fingerprints":manifest.duplicate(true)}
	broken.factions = store._faction_catalogs[store._bound_server].duplicate(true)
	broken.factions[0].name = "不应提交"
	broken.fingerprints.factions = CardRuntime.sha(broken.factions)
	check(not store._apply_catalog_delta(broken).ok and store.factions.values()[0].name == "已更新阵营" and store._catalog_manifest() == manifest, "failed disk write rolls back delta and its cursor")
	store.profile_path = original_path
	store.compilations = 0; store.saves = 0
	await store.request("/test/series", HTTPClient.METHOD_POST, {})
	await store.refresh()
	check(store.series_catalog().current == 3 and store.series_catalog().entries[1].name == "都市纪事", "metadata-only HTTP update synchronizes names and new-card default")
	check(store.compilations == 0 and store.saves == 1, "series rename saves metadata once without compiling cards")
	statistics = (await store.request("/test/stats")).data
	check(statistics.changed[-1] == 0, "metadata-only update does not download unchanged cards")
	await store.refresh()
	check(store.saves == 1 and store.compilations == 0, "unchanged series sync does not rewrite cache")
	store.queue_free(); await process_frame
	store = CountingStore.new(); root.add_child(store)
	check(store.series_catalog().entries[2].name == "新篇章" and not store.online, "custom series names remain available offline after restart")
	await store.request("/test/delay", HTTPClient.METHOD_POST, {})
	store.refresh()
	await process_frame
	store.settings.backend_url = "http://127.0.0.1:1"
	store._ensure_context()
	await create_timer(0.6).timeout
	check(not store.online and store._bound_server == "http://127.0.0.1:1" and store._catalog_manifest().is_empty(), "late response cannot cross server contexts")
	check(store.cards.size() == 33, "server change and offline mode preserve local versions")
	await store.refresh()
	check(store.cards.size() == 33 and "本地卡库" in store.connection_note, "network failure leaves local catalog usable")
	store.queue_free(); await process_frame
	print("CATALOG CACHE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
