extends "res://tests/test_ui.gd"
## Run: godot --headless --path . --script tests/test_characters.gd   (add `-- --capture` in a window for screenshots)
## Commander characters: catalog, portrait fallback without Live2D, the home page, the HQ slot, reactions and the result stage.
## TEST_CHARACTER_DIR + TEST_CHARACTER_ID run the same checks with a real character kept outside the repository (e.g. a Live2D model).

func _local_character_dir() -> String:
	var root := ProjectSettings.globalize_path("res://.runtime/characters-test-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(root.path_join("tester"))
	# TEST_CHARACTER_PORTRAIT lets a screenshot run use a real portrait kept outside the repository.
	var source := OS.get_environment("TEST_CHARACTER_PORTRAIT")
	var image := Image.load_from_file(source) if not source.is_empty() else null
	if image == null:
		image = Image.create(64, 96, false, Image.FORMAT_RGBA8)
		image.fill(Color("4a6fa5"))
	image.save_png(root.path_join("tester/portrait.png"))
	var file := FileAccess.open(root.path_join("tester/character.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"name":"测试角色","portrait":"portrait.png","actions":{"hit":{"expression":"sweat"}}}))
	file.close()
	# Folders that are not valid ids are skipped.
	DirAccess.make_dir_recursive_absolute(root.path_join("Bad Name"))
	return root

func _restore_choice(original_choice: Variant, original_hq: Variant = null) -> void:
	OS.set_environment("CHAO_CHARACTER_DIR", "")
	var restored := ConfigFile.new()
	restored.load("user://visuals.cfg")
	if original_hq == null:
		if restored.has_section_key("character", "hq"): restored.erase_section_key("character", "hq")
	else: restored.set_value("character", "hq", original_hq)
	if original_choice == null:
		if restored.has_section_key("character", "id"): restored.erase_section_key("character", "id")
	else: restored.set_value("character", "id", original_choice)
	restored.save("user://visuals.cfg")
	CharacterCatalog._selected = ""
	CharacterCatalog.reload()

func _run() -> void:
	root.size = Vector2i(1440, 900)
	# visuals.cfg is the player's real file; remember the choice and put it back afterwards.
	var original := ConfigFile.new()
	original.load("user://visuals.cfg")
	var original_choice: Variant = original.get_value("character", "id") if original.has_section_key("character", "id") else null
	var original_hq: Variant = original.get_value("character", "hq") if original.has_section_key("character", "hq") else null
	CharacterCatalog.set_hq_enabled(true)
	var real_dir := OS.get_environment("TEST_CHARACTER_DIR")
	var chosen := OS.get_environment("TEST_CHARACTER_ID") if not real_dir.is_empty() else "tester"
	OS.set_environment("CHAO_CHARACTER_DIR", real_dir if not real_dir.is_empty() else _local_character_dir())
	CharacterCatalog.reload()
	check(CharacterCatalog.has(CharacterCatalog.DEFAULT_ID), "default commander always exists")
	var bundled := CharacterCatalog.info(CharacterCatalog.DEFAULT_CHOICE)
	check(bundled.id == CharacterCatalog.DEFAULT_CHOICE and not bundled.local, "the default choice ships with the game")
	check(not CharacterCatalog.file(bundled, "model").is_empty() and not CharacterCatalog.file(bundled, "portrait").is_empty() and not CharacterCatalog.file(bundled, "vtube").is_empty(), "bundled model, portrait and VTube settings resolve inside res://")
	check(str(bundled.get("credits", "")).contains("神宫凉子") and str(bundled.credits).contains("霓虹猫_NeonNeko"), "bundled character credits its authors")
	check(load(CharacterCatalog.file(bundled, "portrait")) is Texture2D, "bundled portrait is an imported texture")
	check(CharacterCatalog.has(chosen) and CharacterCatalog.info(chosen).local, "local test character is read in debug builds")
	check(not CharacterCatalog.entries().any(func(e): return e.id == "Bad Name"), "invalid folder ids are skipped")
	check(CharacterCatalog.info("nobody").id == CharacterCatalog.DEFAULT_ID, "unknown ids fall back to the default")
	check(CharacterCatalog.valid_id("tester") and not CharacterCatalog.valid_id("../x") and not CharacterCatalog.valid_id(""), "id pattern")
	# motion3 curves: linear, stepped, inverse stepped and bezier segments.
	var curve := [0.0, 0.0, 0, 1.0, 1.0, 2, 2.0, 3.0, 3, 3.0, 5.0, 1, 3.5, 5.0, 3.5, 6.0, 4.0, 6.0]
	check(is_equal_approx(Live2DGesture.evaluate(curve, 0.5), 0.5), "linear segment")
	check(is_equal_approx(Live2DGesture.evaluate(curve, 1.5), 1.0), "stepped segment holds the start value")
	check(is_equal_approx(Live2DGesture.evaluate(curve, 2.5), 5.0), "inverse stepped segment jumps to the end value")
	var mid := Live2DGesture.evaluate(curve, 3.5)
	check(mid > 5.0 and mid < 6.0, "bezier segment eases between its ends")
	check(is_equal_approx(Live2DGesture.evaluate(curve, 9.0), 6.0), "after the last point the curve keeps its end value")
	CharacterCatalog.choose(CharacterCatalog.DEFAULT_ID)
	CharacterCatalog.choose("nobody")
	check(CharacterCatalog.selected() == CharacterCatalog.DEFAULT_ID, "unknown choices are ignored")
	CharacterCatalog.choose(chosen)
	check(CharacterCatalog.selected() == chosen, "choice is kept")

	var figure := CommanderFigure.new()
	figure.size = Vector2(200, 300)
	root.add_child(figure)
	figure.configure(chosen, "hq")
	check(figure.portrait != null and not figure.uses_live2d() or CharacterCatalog.live2d_available(), "portrait is used without the Live2D extension")
	if not CharacterCatalog.file(CharacterCatalog.info(chosen), "model").is_empty():
		check(figure.uses_live2d() == CharacterCatalog.live2d_available(), "a model is drawn with Live2D when the extension is present")
	figure.act("hit")
	check(figure._kick == "hit", "reaction starts")
	figure.act("dance")
	check(figure._kick == "hit", "unknown reactions are ignored")
	figure.queue_free()

	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.store.settings.backend_url = "http://127.0.0.1:1"
	app.store._ensure_context()
	app._boot_loading = false
	await process_frame
	if is_instance_valid(app.startup): app.startup.queue_free()
	app._navigate("home")
	await process_frame
	var stage: Control = app.content.find_child("HomeCharacter", true, false)
	check(stage is CommanderFigure and stage.character_id == chosen, "home shows the chosen character")
	for tile in ["Home_battle", "Home_library", "Home_workshop", "Home_keywords", "Home_decks", "Home_settings"]:
		check(app.content.find_child(tile, true, false) != null, "home tile " + tile)
	check(not app.sidebar.visible, "home uses its own menu instead of the sidebar")
	check(stage.interactive() and stage.mouse_filter == Control.MOUSE_FILTER_STOP, "home character takes clicks")
	if stage.uses_live2d() and stage._rig != null:
		check(stage._life == null and not stage._rig.mappings.is_empty(), "a character with a VTube Studio setup moves the way its author mapped it")
	elif stage.uses_live2d(): check(stage._life != null and stage._life.layer_count() == 4, "home model has its eye, head, body and sway layers")
	if stage.uses_live2d() and CharacterCatalog.action(stage.entry, "play").has("gesture"):
		stage.act("play")
		check(not stage._gesture.is_empty() and stage._gesture.phase == "out", "gestures layer over the idle motion")
		for i in 20: await process_frame
		check(not stage.model.call("get_cubism_motion_queue_entries").is_empty(), "the idle motion keeps playing under a gesture")
		stage._gesture = {}
		for parameter in stage._params.values(): parameter.call("set_hold", false)
	stage.perform_home("touch_head")
	check(stage._kick == "play", "clicking the character plays a touch reaction")
	stage._kick = ""
	stage._idle_left = 0.0
	await process_frame
	check(stage._kick == "turn", "an idle action plays after a quiet spell")
	check(stage._idle_left > 10.0, "the idle timer restarts")
	check(not CharacterCatalog.home_actions(CharacterCatalog.info(CharacterCatalog.DEFAULT_ID), "touch_body").is_empty(), "home actions fall back to match actions")
	await snap("character-home")
	app._character_dialog()
	await process_frame
	check(app.overlay.find_children("*", "Button", true, false).any(func(b): return b.text == "使用中"), "character dialog marks the current choice")
	await snap("character-dialog")
	app._close_modal()

	# A practice match: the HQ slot carries the character, reacts to events and steps forward at the end.
	var store: AppStore = app.store
	var fid := "11111111-1111-4111-8111-111111111111"
	store._faction_catalogs[store._bound_server] = [{"faction_id":fid,"name":"测试国","role":"major","color":"#315e88","icon_id":null}]
	store._activate_factions()
	store.main_faction_id = fid
	var refs := []
	for i in 10:
		var unit: Dictionary = CardRuntime.parse_json(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json")).value
		unit["faction_id"] = fid
		unit.name = "角色测试兵" + str(i)
		unit.keywords = []
		var draft: Dictionary = await store.create_draft(unit)
		await store.confirm_draft(draft.draft)
		var record: Dictionary = store.cards.back()
		for j in 4: refs.append({"card_id":record.card_id,"revision":record.revision,"definition_hash":record.definition_hash})
	check(store.accept_shared_deck({"deck":{"name":"角色测试","cards":refs},"cards":store.cards.duplicate(true),"keywords":[]}).ok, "test deck")
	store.main_sin = "wrath"
	store.ally_sin = "gloom"
	app._start_solo()
	for i in 6: await process_frame
	var view: Control = app.battle_view
	check(is_instance_valid(view), "battle opened")
	if not is_instance_valid(view):
		print("practice did not start: ", app.info_text, " page=", app.page)
		_restore_choice(original_choice, original_hq)
		quit(1)
		return
	check(app.match_controller.state.players[0].get("character_id", "") == chosen, "own character travels with the match")
	view._emit_action({"type":"mulligan","hand_ids":[]})
	for i in 30: await process_frame
	var own: Control = view.visual_faces.get("hq:%d" % view.me)
	var rival: Control = view.visual_faces.get("hq:%d" % (1 - view.me))
	check(own != null and own.figure != null and own.figure.character_id == chosen, "own HQ shows the chosen character")
	check(rival != null and rival.figure != null and rival.figure.character_id == CharacterCatalog.DEFAULT_ID, "AI uses the default commander")
	check(own.tooltip_text.contains(CharacterCatalog.info(chosen).name), "HQ tooltip names the character")
	CharacterCatalog.set_hq_enabled(false)
	view.refresh_characters()
	check(own.figure == null and rival.figure == null, "HQ characters can be switched off")
	await snap("character-battle-off")
	CharacterCatalog.set_hq_enabled(true)
	view.refresh_characters()
	check(own.figure != null and own.figure.character_id == chosen, "and back on")
	await process_frame
	check(not view.state.has("mulligan"), "opening hand kept")
	await snap("character-battle")
	view._character_reactions([{"kind":"turn_start","owner":view.me}, {"kind":"damage","owner":1 - view.me,"target_owner":view.me,"target_uid":-101 - view.me,"amount":3}, {"kind":"attack","owner":1 - view.me}])
	check(own.figure._kick == "hit", "the strongest reaction wins for each side")
	check(rival.figure._kick == "attack", "attacker reacts")
	view.state.winner = view.me
	view._result()
	var result_figure: Control = view.board.find_child("ResultCharacter", false, false)
	check(result_figure is CommanderFigure and result_figure._kick == "win", "winner steps into the middle")
	await create_timer(0.6).timeout
	await snap("character-result")

	OS.set_environment("CHAO_CHARACTER_DIR", "")
	_restore_choice(original_choice, original_hq)
	app.queue_free()
	await process_frame
	print("character checks: %d failures: %d" % [checks, failures])
	quit(1 if failures else 0)
