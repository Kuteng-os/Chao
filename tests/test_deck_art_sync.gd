extends "res://tests/test_ui.gd"

func _run() -> void:
	var fixture: Dictionary = CardRuntime.parse_json(FileAccess.get_file_as_string("res://.runtime/deck-art-test-env.json")).value
	var profile := FileAccess.open(OS.get_environment("FRONTLINE_PROFILE_PATH"), FileAccess.WRITE)
	profile.store_string(JSON.stringify({"settings":{"backend_url":fixture.base,"api_token":fixture.token,"owner_id":fixture.owner_id}}))
	profile.close()
	root.size = Vector2i(1440, 900)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	while app.store._refresh_running: await process_frame
	var store: AppStore = app.store
	check(store.authenticated and store.cards.size()==10, "Real server catalog sync")
	var painted := {}
	for record in store.cards:
		if record.get("art") is Dictionary: painted=record
		for n in 4: store.add_to_deck(record.card_id)
	check(not painted.is_empty(), "Website-uploaded art metadata reaches game")
	if painted.is_empty(): quit(1); return
	var frozen: Dictionary = await store.load_card_version(painted, 1)
	check(frozen.ok and not frozen.card.has("art") and store.latest_cards().size()==10, "Art-only revision retains art-free history without duplicate latest cards")
	check(store.save_local_deck("联调共享牌组").ok, "Local save")
	var published: Dictionary = await store.publish_deck()
	check(published.ok, "Game uploads frozen references to central API")
	if not published.ok: push_error(published.error); quit(1); return
	var deck_id := str(published.data.deck_id)
	var republished: Dictionary = await store.publish_deck()
	check(republished.ok and republished.data.deck_id==deck_id and republished.data.revision==2, "Repeated upload updates own deck instead of duplicating it")
	var selected: Dictionary = await store.import_shared_deck(deck_id)
	check(selected.ok and store.deck_ids.size()==40, "Download own shared deck")
	var deck: Dictionary = store.compile_deck()
	check(deck.ok and deck.deck.any(func(card): return card.get("art_id")==painted.art.id), "Compiled deck retains presentation reference")
	app._navigate("library")
	var texture: Texture2D = await CardArtCache.load_art(str(painted.art.id), self)
	check(texture != null, "Download and hash-check card art")
	await snap("deck-art-library")
	app._deck_browser(true)
	await create_timer(0.2).timeout
	await snap("shared-decks")
	app._close_modal()
	app._start_solo()
	app.match_controller.set_process(false)
	check(app.match_controller.state.players[0].hand.all(func(c): return c.card.has("definition")), "Normal solo match starts with artwork")
	var prepared: Dictionary = app.match_controller._prepare_deck(deck.deck, deck.keyword_definitions)
	check(prepared.ok and prepared.cards.any(func(card): return card.get("art_id")==painted.art.id), "LAN and solo preparation preserve card art")
	# Place the already compiled test card in a visible hand to verify renderer reuse.
	var card: Dictionary = deck.deck.filter(func(c): return c.get("art_id")==painted.art.id)[0]
	var engine: BattleEngine = app.match_controller._engine
	engine.state.players[0].hand[0].card = card
	engine.state.active_player = 0
	engine.state.players[0].credits = 10
	app.match_controller._refresh_views()
	await snap("deck-art-hand")
	app._act({"type":"play","hand_id":engine.state.players[0].hand[0].instance_id})
	await snap("deck-art-battle")
	check(engine.state.units.any(func(unit): return unit.card.get("art_id")==painted.art.id), "Deployed unit retains version-specific artwork")
	app.match_controller.leave_game()
	app.queue_free()
	await process_frame
	print("DECK_ART_SYNC_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
