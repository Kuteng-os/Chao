extends "res://tests/test_ui.gd"

func _run() -> void:
	var fixture: Dictionary = CardRuntime.parse_json(FileAccess.get_file_as_string("res://.runtime/deck-art-test-env.json")).value
	var profile := FileAccess.open(OS.get_environment("FRONTLINE_PROFILE_PATH"),FileAccess.WRITE)
	profile.store_string(JSON.stringify({"settings":{"backend_url":fixture.base,"api_token":fixture.token,"owner_id":fixture.owner_id}}))
	profile.close()
	root.size = Vector2i(1440,900)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	while app.store._refresh_running: await process_frame
	var store: AppStore = app.store
	check(store.authenticated and store.factions.size()==2,"Web-created faction syncs to authenticated client")
	var created := {}
	for record in store.cards:
		if record.definition.name == "曙光步兵": created=record
	check(not created.is_empty(),"Web-created faction card syncs")
	if created.is_empty(): quit(1); return
	var new_id: String = created.definition.faction_id
	store.select_factions("11111111-1111-4111-8111-111111111111",new_id)
	for record in store.cards:
		if record == created: continue
		for n in 4: check(store.add_to_deck(record.card_id).is_empty(),"Main-faction card can be dragged into deck")
	store.remove_from_deck(store.deck_ids[0])
	check(store.add_to_deck(created.card_id).is_empty(),"Allied card adds exactly one")
	check(store.deck_factions().ally_count==1 and store.compile_deck().ok,"Mixed 39 + 1 deck compiles")
	check(store.save_local_deck("阵营联调").ok,"Mixed-faction deck saves locally")
	var shared: Dictionary = await store.publish_deck()
	check(shared.ok and shared.data.main_faction_id==store.main_faction_id and shared.data.ally_faction_id.is_empty(),"Server stores nominal main only")
	if not shared.ok: quit(1); return
	store.new_local_deck()
	check(store.main_faction_id.is_empty() and store.ally_faction_id.is_empty(),"New deck resets factions")
	check((await store.import_shared_deck(shared.data.deck_id)).ok,"Shared deck downloads with faction registry")
	check(store.main_faction_id==shared.data.main_faction_id and store.ally_faction_id.is_empty() and store.compile_deck().ok,"Shared import restores nominal main")
	var face := CardFace.new()
	face.spec = store.compile_record(created).definition
	root.add_child(face)
	var icon: Texture2D = await CardArtCache.load_art(str(store.factions[new_id].icon_id),self)
	check(icon!=null,"Faction icon downloads and passes PNG/hash validation")
	await process_frame
	check(face.faction_icon!=null,"Card renderer uses uploaded faction icon")
	face.queue_free()
	app._navigate("library")
	await snap("faction-library")
	app._start_solo()
	app.match_controller.set_process(false)
	check(app.match_controller.mode=="solo","Mixed-faction deck starts battle")
	app.match_controller.leave_game()
	app.queue_free()
	await process_frame
	print("FACTION_SYNC_TEST_RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
