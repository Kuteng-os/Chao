extends SceneTree
## Run: PACK_EXPORT_OUT=<folder> godot --headless --path . --script tests/test_pack_export.gd
## Builds a pack with the real workshop code, writes it for tools/library/submission.mjs to check, and re-imports it.
var failures := 0
var checks := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func _initialize() -> void:
	OS.set_environment("FRONTLINE_PROFILE_PATH", "user://pack-export-test/profile.json")
	DirAccess.remove_absolute("user://pack-export-test/profile.json")
	CardArtCache.remote_roots = ["http://127.0.0.1:9/"]
	_run.call_deferred()

func _local_card(app: Control, card_name: String, attack: int) -> Dictionary:
	var faction: String = app.store.factions.keys()[0]
	var definition := {"schema_version":"1.0.0","ruleset_version":"frontline-1","name":card_name,"flavor_text":"","kind":"unit","unit_class":"infantry","cost":2,"operation_cost":1,"attack":attack,"health":3,"keywords":[],"play_target":null,"abilities":[],"tokens":[],"appearance":{"emblem":"infantry"},"rarity":"standard","faction_id":faction,"sin":"pride"}
	var made: Dictionary = await app.store.create_draft(definition)
	var saved: Dictionary = await app.store.confirm_draft(made.draft)
	check(saved.get("ok", false), "local card saved: " + str(saved.get("error", "")))
	return saved.get("card", {})

func _run() -> void:
	var app: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.store.online = false
	# The main scene starts loading the bundled catalog itself; wait for it instead of starting a second load.
	for frame in 3000:
		if app.store.bundled_ready: break
		await process_frame
	check(app.store.bundled_ready, "catalog installed")
	app.store.settings.player_name = "测试作者"
	var records := [await _local_card(app, "卡包测试甲", 2), await _local_card(app, "卡包测试乙", 4)]

	var built: Dictionary = app._build_pack(records, "测试卡包", "两张测试卡")
	check(not built.has("error"), "pack builds: " + str(built.get("error", "")))
	check(str(built.get("file", "")).begins_with("pack-") and str(built.file).ends_with(".pack.json"), "pack file name")
	check(app._build_pack(records, "", "").has("error"), "a name is required")
	check(app._build_pack([records[0], records[0]], "重复", "").has("error"), "duplicate names are refused")
	var out := OS.get_environment("PACK_EXPORT_OUT")
	if not out.is_empty() and not built.has("error"):
		var file := FileAccess.open(out.path_join(built.file), FileAccess.WRITE)
		file.store_string(built.text)
		file.close()

	# Importing the pack into a fresh library makes the same cards available for a test deck.
	var path := ProjectSettings.globalize_path("user://pack-export-test/" + str(built.file))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(built.text)
	file.close()
	for record in records: app.store.cards.erase(record)
	var before: int = app.store.cards.size()
	await app._import_pack(path)
	check(app.store.cards.size() == before + 2, "import adds both cards")
	check(app.store.cards.any(func(r): return r.definition.name == "卡包测试乙" and bool(r.get("local_only", false))), "imported cards are local cards")
	app.queue_free()
	print("pack export checks: ", checks, " failures: ", failures)
	quit(1 if failures > 0 else 0)
