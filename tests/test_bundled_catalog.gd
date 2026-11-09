extends SceneTree
## Launches the real store against the packaged catalog with an empty profile and no service.

var failures := 0

func _check(value: bool, label: String) -> void:
	if value: return
	failures += 1
	printerr("FAIL: ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var profile := "user://bundled-test/profile.json"
	DirAccess.remove_absolute(profile)
	OS.set_environment("FRONTLINE_PROFILE_PATH", profile)
	CardArtCache.remote_roots = ["http://127.0.0.1:9/"]
	var store := AppStore.new()
	root.add_child(store)
	var network := await store.request("/v1/cards")
	_check(not network.ok and network.code == 503, "requests stop before the network")

	var started := Time.get_ticks_msec()
	await store.refresh()
	print("first load ms: ", Time.get_ticks_msec() - started, " cards: ", store.cards.size())
	_check(store.bundled_ready, "bundled catalog applies: " + store.connection_note)
	_check(store.cards.size() >= 250, "cards are installed on a fresh profile")
	_check(store.factions.size() == 14, "factions are installed")
	_check(not store.keyword_definitions.is_empty(), "keywords are installed")
	_check(store.latest_cards().all(func(card): return not bool(card.get("local_authored", false))), "catalog cards are not treated as player work")

	var art_total := 0
	for card in store.cards:
		var art: Variant = card.get("art")
		if art is Dictionary:
			art_total += 1
			_check(await CardArtCache.load_art(art.id, self) != null, "art loads for " + str(card.definition.name))
	_check(art_total > 0, "catalog contains art")
	for id in store.factions:
		var icon: Variant = store.factions[id].get("icon_id")
		if icon is String: _check(await CardArtCache.load_art(icon, self) != null, "faction icon loads")

	store.bundled_ready = false
	started = Time.get_ticks_msec()
	await store.refresh()
	print("repeat load ms: ", Time.get_ticks_msec() - started)
	_check(store.bundled_ready, "repeat load keeps the catalog")

	var definition := {"schema_version":"1.0.0","ruleset_version":"frontline-1","name":"提交测试单位","flavor_text":"","kind":"unit","unit_class":"infantry","cost":2,"operation_cost":1,"attack":2,"health":2,"keywords":[],"play_target":null,"abilities":[],"tokens":[],"appearance":{"emblem":"infantry"},"rarity":"standard"}
	var made := await store.create_draft(definition)
	_check(made.ok and bool(made.draft.get("local_only", false)), "drafts validate locally")
	var saved := await store.confirm_draft(made.draft)
	_check(saved.ok and bool(saved.card.get("local_only", false)), "drafts save locally")
	var output := OS.get_environment("BUNDLED_TEST_OUTPUT")
	if not output.is_empty() and saved.ok:
		var compiled := store.compile_record(saved.card)
		var text := JSON.stringify({"format":"chao-card-submission-v1","game_version":"test","author":"测试玩家","definition":saved.card.definition,"definition_hash":compiled.definition_hash})
		var file := FileAccess.open(output.path_join("card-%s.card.json" % str(compiled.definition_hash).left(12)), FileAccess.WRITE)
		file.store_string(text)
		file.close()

	store.queue_free()
	print("bundled catalog test: ", "FAILED %d" % failures if failures > 0 else "OK")
	quit(1 if failures > 0 else 0)
