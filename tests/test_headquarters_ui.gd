extends "res://tests/test_ui.gd"
func _run() -> void:
	root.size=Vector2i(1440,900)
	app=load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.store.settings.backend_url="http://127.0.0.1:1"
	app.store._ensure_context()
	await process_frame
	var store:AppStore=app.store
	var fid:="11111111-1111-4111-8111-111111111111"
	store._faction_catalogs[store._bound_server]=[{"faction_id":fid,"name":"测试国","role":"major","color":"#315e88","icon_id":null}]
	store._activate_factions();store.main_faction_id=fid
	var definition:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures835.json")).cards[0].definition
	definition["faction_id"]=fid
	var draft:Dictionary=await store.create_draft(definition)
	check(draft.ok,"HQ draft")
	if not draft.ok:quit(1);return
	var created:Dictionary=await store.confirm_draft(draft.draft)
	check(created.ok,"HQ registration")
	var hq_id:String=store.cards[0].card_id
	check(store.select_headquarters(hq_id).is_empty(),"HQ selection")
	check(store.deck_ids.is_empty(),"selection does not occupy deck")
	var saved:=store.save_local_deck("总部牌组")
	check(saved.ok and saved.deck.headquarters_id==hq_id,"local save")
	check(store.new_local_deck("默认",fid).ok and store.headquarters_id.is_empty(),"new deck default")
	check(store.load_local_deck(saved.deck.id).ok and store.headquarters_id==hq_id,"restore HQ")
	app._navigate("library");await process_frame;await process_frame
	check(app.library_headquarters.text.contains("后勤总部"),"deck HQ button label")
	app._headquarters_dialog();await process_frame
	check(app.overlay.find_children("*","Button",true,false).any(func(c):return c.text=="后勤总部"),"selection dialog lists HQ")
	await snap("hq-picker-835");app._close_modal()
	app._card_details(store.get_card(hq_id));await snap("hq-card-835");app._close_modal()
	var reloaded:=AppStore.new();root.add_child(reloaded)
	check(reloaded.headquarters_id==hq_id,"restart remembers HQ")
	reloaded.queue_free()
	var refs:=[]
	for i in 10:
		var unit:Dictionary=CardRuntime.parse_json(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json")).value
		unit["faction_id"]=fid;unit.name="总部测试兵"+str(i);unit.keywords=[]
		var d:Dictionary=await store.create_draft(unit);await store.confirm_draft(d.draft)
		var r:Dictionary=store.cards.back()
		for j in 4:refs.append({"card_id":r.card_id,"revision":r.revision,"definition_hash":r.definition_hash})
	var h:Dictionary=store.get_card(hq_id)
	var bundle:={"deck":{"name":"共享总部","cards":refs,"headquarters":{"card_id":h.card_id,"revision":h.revision,"definition_hash":h.definition_hash}},"cards":store.cards.duplicate(true),"keywords":[]}
	check(store.accept_shared_deck(bundle).ok,"shared HQ import")
	var compiled:=store.compile_deck()
	check(compiled.ok and compiled.deck.size()==40 and compiled.headquarters.definition.health==35,"40 plus separate compiled HQ")
	app._start_solo();await process_frame;await process_frame
	check(app.match_controller.state.players[0].max_hp==35,"practice uses selected HQ")
	await snap("hq-battle-835")
	app.queue_free();await process_frame
	print("HQ UI: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
