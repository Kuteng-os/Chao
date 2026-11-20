extends "res://tests/test_ui.gd"

func _run() -> void:
	root.size = Vector2i(1440, 900)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app._startup_enter()
	app.store.settings.backend_url = "http://127.0.0.1:1"
	app.store._ensure_context()
	await process_frame
	var store: AppStore = app.store
	var definition: Dictionary = CardRuntime.parse_json(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json")).value
	definition["faction_id"] = "11111111-1111-4111-8111-111111111111"
	store._faction_catalogs[store._bound_server] = [{"faction_id":definition.faction_id,"name":"测试主阵营","role":"major","color":"#496359","icon_id":null}]
	store._activate_factions()
	store.main_faction_id = definition.faction_id
	definition["rarity"] = "standard"
	definition.keywords = []
	for i in 10:
		definition.name = "组牌测试 %d" % i
		var draft: Dictionary = await store.create_draft(definition)
		check(draft.ok, "fixture draft: " + str(draft.get("error", "")))
		if not draft.ok: quit(1); return
		await store.confirm_draft(draft.draft)
	check(store.new_local_deck("拖动构筑", "", "wrath").ok,"Create deck before dragging")
	app._navigate("library")
	await process_frame
	await process_frame
	var face: Control = app.library_grid.get_child(0).get_child(0)
	var first_id := str(face.drag_payload.card_id)
	await drag(face.get_global_rect().get_center(), app.deck_drop.get_global_rect().get_center())
	check(store.deck_ids == [first_id], "Real mouse drag from library adds exactly one card")
	face = app.library_grid.get_child(0).get_child(0)
	var strips: Array = app.deck_drop.find_children("*", "Button", true, false).filter(func(c): return c.get_script()==preload("res://scripts/ui/deck_strip.gd"))
	check(strips.size() == 1, "Compact deck strip is rendered")
	if not strips.is_empty():
		await drag(face.get_global_rect().get_center(), strips[0].get_global_rect().get_center())
		check(store.deck_ids.size() == 2, "Dragging onto a nested deck strip also adds one")
		strips = app.deck_drop.find_children("*", "Button", true, false).filter(func(c): return c.get_script()==preload("res://scripts/ui/deck_strip.gd"))
		face = app.library_grid.get_child(0).get_child(0)
		await drag(strips[0].get_global_rect().get_center(), face.get_global_rect().get_center())
		check(store.deck_ids.size() == 1, "Dragging a strip onto a library card removes exactly one")
	for button in app.content.find_children("*", "Button", true, false):
		check(not button.text in ["−", "＋", "+ 加入"], "No quantity buttons remain")
	var saved := store.save_local_deck("本地甲")
	check(saved.ok, "Save partial deck")
	var a_id := str(saved.deck.id)
	store.add_to_deck(first_id)
	check(store.new_local_deck().ok, "New deck")
	check(store.local_decks.size() == 2, "Unsaved edits retained as separate draft")
	check(store.deck_ids.is_empty(), "New deck starts empty")
	check(store.load_local_deck(a_id).ok and store.deck_ids.size() == 1, "Named deck retains its saved copy count")
	var reloaded := AppStore.new()
	root.add_child(reloaded)
	check(reloaded.local_decks.size() == 2 and reloaded.deck_ids == store.deck_ids and reloaded.deck_name == "本地甲", "Restart restores names, decks and working selection")
	reloaded.queue_free()
	var old_ids := store.deck_ids.duplicate()
	check(not store.accept_shared_deck({"deck":{}}).ok and store.deck_ids == old_ids, "Bad shared bundle cannot change current deck")
	# The store also holds the bundled catalog; the shared deck uses only this test's ten cards.
	var fixtures: Array = store.cards.filter(func(record): return str(record.definition.name).begins_with("组牌测试"))
	var refs: Array = []
	for record in fixtures:
		for n in 4: refs.append({"card_id":record.card_id,"revision":record.revision,"definition_hash":record.definition_hash})
	var bundle := {"deck":{"name":"玩家共享","cards":refs,"main_faction_id":"11111111-1111-4111-8111-111111111111","main_sin":"wrath","ally_sin":"gloom"},"cards":fixtures.duplicate(true),"keywords":[],"factions":[{"faction_id":"11111111-1111-4111-8111-111111111111","name":"测试主阵营","role":"major","color":"#496359","icon_id":null}]}
	var shared_result := store.accept_shared_deck(bundle)
	check(shared_result.ok, "Complete valid shared bundle imports: " + str(shared_result.get("error", "")))
	check(store.deck_ids.size()==40 and store.deck_name=="玩家共享", "Shared deck becomes independent named local deck")
	check(store.compile_deck().ok, "Imported shared deck compiles for battle: " + str(store.compile_deck().get("error", "")))
	check(store.import_deck_json(JSON.stringify(bundle)).ok and store.compile_deck().ok, "JSON import validates and loads a playable bundle")
	var json_before := store.deck_ids.duplicate()
	check(not store.import_deck_json("{bad").ok and store.deck_ids==json_before,"Invalid JSON preserves the working deck")
	var exported := store.export_current_deck()
	check(exported.ok, "Current deck exports: " + str(exported.get("error", "")))
	if exported.ok:
		var parsed: Dictionary = JSON.parse_string(exported.text)
		check(parsed.format == "chao-deck-1" and parsed.deck.cards.size() == 40 and parsed.deck.name == store.deck_name, "Export carries 40 card references and the deck name")
		check(not parsed.cards.is_empty() and parsed.factions.size() >= 1, "Export carries card versions and their faction")
		var decks_before := store.local_decks.size()
		var reimported := store.import_deck_json(exported.text)
		check(reimported.ok and store.local_decks.size() == decks_before + 1, "Exported JSON imports back: " + str(reimported.get("error", "")))
		check(store.deck_ids.size() == 40 and store.deck_name == str(parsed.deck.name), "The re-imported deck has the same 40 cards and name")
		app._export_deck_dialog(exported, store.deck_name)
		await process_frame
		check(app.find_child("DeckExportJSON", true, false) != null, "Export dialog shows the JSON")
		app._close_modal()
	check(not store.export_local_deck("no-such-deck").ok, "Unknown saved deck cannot be exported")
	check(app._deck_file_name("a/b:c") == "a_b_c.deck.json", "File name drops characters Windows forbids")
	var before := store.deck_ids.duplicate()
	check(not store.add_to_deck(first_id).is_empty() and store.deck_ids==before, "Capacity overflow is rejected without mutation")
	app._deck_browser(false)
	await snap("local-decks")
	app._close_modal()
	app._card_details(store.cards[0])
	await snap("deck-card-detail")
	app._close_modal()
	await snap("deck-editor")
	root.size = Vector2i(1120, 720)
	await snap("deck-editor-small")
	check(app.deck_drop.get_global_rect().end.x <= root.get_visible_rect().size.x, "Small window keeps deck panel inside viewport")
	check(app.deck_drop.get_global_rect().end.y <= root.get_visible_rect().size.y, "Small window keeps deck actions inside viewport")
	app.queue_free()
	await process_frame
	print("DECK_EDITOR_TEST_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func drag(start: Vector2, end: Vector2) -> void:
	await move_mouse(start)
	await press_mouse(start, true)
	await move_mouse(start+Vector2(24, 0), MOUSE_BUTTON_MASK_LEFT)
	await move_mouse(start.lerp(end, 0.5), MOUSE_BUTTON_MASK_LEFT)
	await move_mouse(end, MOUSE_BUTTON_MASK_LEFT)
	await press_mouse(end, false)
	await process_frame
	await process_frame
