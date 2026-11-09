extends "res://tests/test_ui.gd"

const IDS := ["11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222", "33333333-3333-4333-8333-333333333333", "44444444-4444-4444-8444-444444444444"]

func _run() -> void:
	root.size = Vector2i(1440,900)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	var store: AppStore = app.store
	store.settings.backend_url = "http://127.0.0.1:1"
	store._ensure_context()
	await process_frame
	var catalog: Array = []
	for i in IDS.size(): catalog.append({"faction_id":IDS[i],"name":"阵营 %d" % i,"role":"ally" if i==3 else "major","color":"#496359","icon_id":null})
	store._faction_catalogs[store._bound_server] = catalog
	store._activate_factions()
	var spec: Dictionary = CardRuntime.parse_json(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json")).value
	spec.keywords = []
	spec["rarity"] = "standard"
	for i in 10:
		spec.name = "混编 %d" % i
		spec["faction_id"] = IDS[i%3]
		var draft: Dictionary = await store.create_draft(spec)
		check(draft.ok,"Card draft for faction %d" % (i%3))
		if not draft.ok: quit(1); return
		await store.confirm_draft(draft.draft)
	store.select_factions(IDS[3],IDS[1])
	for record in store.cards:
		for n in 4: check(store.add_to_deck(record.card_id).is_empty(),"Cards from all factions can be added")
	check(store.main_faction_id==IDS[3] and store.ally_faction_id.is_empty(),"Composition does not override nominal main")
	check(store.compile_deck().ok,"Mixed 40 card deck compiles with no cards of nominal main")
	check(not store.add_to_deck(store.cards[0].card_id).is_empty(),"40 card cap preserved")
	store.remove_from_deck(store.cards[1].card_id)
	check(not store.add_to_deck(store.cards[0].card_id).is_empty(),"Same-name copy cap preserved below 40")
	check(store.add_to_deck(store.cards[1].card_id).is_empty(),"Restore deck")
	var saved := store.save_local_deck("自由混编")
	check(saved.ok,"Save with nominal main")
	check(store.new_local_deck().ok and store.main_faction_id.is_empty(),"New deck does not inherit main")
	check(store.load_local_deck(saved.deck.id).ok and store.main_faction_id==IDS[3],"Loading retains unrelated nominal main")
	var reloaded := AppStore.new()
	root.add_child(reloaded)
	check(reloaded.main_faction_id==IDS[3] and reloaded.compile_deck().ok,"Restart retains free composition and main")
	reloaded.queue_free()
	var refs: Array = []
	for record in store.cards:
		for n in 4: refs.append({"card_id":record.card_id,"revision":record.revision,"definition_hash":record.definition_hash})
	var bundle := {"deck":{"name":"共享混编","cards":refs,"main_faction_id":IDS[3],"ally_faction_id":IDS[1]},"cards":store.cards.duplicate(true),"keywords":[],"factions":catalog}
	check(store.accept_shared_deck(bundle).ok,"Shared mixed deck imports")
	check(store.main_faction_id==IDS[3] and store.ally_faction_id.is_empty() and store.compile_deck().ok,"Import keeps main and discards obsolete ally constraint")
	app._navigate("library")
	await process_frame
	check(app.content.find_child("MainFaction",true,false)==null,"No nation selector in deck editing")
	app._new_deck_dialog()
	var picker := app.overlay.find_child("NewDeckMainFaction",true,false) as OptionButton
	check(picker!=null and picker.item_count==4,"Creation includes every faction, including legacy ally role")
	app._close_modal()
	var ally_found := false
	for label in app.content.find_children("*","Label",true,false):
		if label.text in ["盟军","副国"]: ally_found=true
	check(not ally_found,"No obsolete ally picker")
	await snap("free-factions")
	app._start_solo()
	app.match_controller.set_process(false)
	check(app.match_controller.mode=="solo","Mixed deck starts a real local battle")
	app.match_controller.leave_game()
	app.queue_free()
	await process_frame
	print("FREE_FACTIONS_TEST_RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
