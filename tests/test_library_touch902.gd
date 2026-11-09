extends "res://tests/test_ui.gd"
var remote_records: Array = []
func record(spec: Dictionary, id: String, revision: int) -> Dictionary:
	var c:=CardRuntime.compile_card(CardRuntime.parse_json(JSON.stringify(spec)).value,[])
	check(c.ok,"Card fixture compiles: " + str(c.get("error", c.get("errors", ""))))
	if not c.ok: return {}
	return {"card_id":id,"revision":revision,"definition":c.source,"definition_hash":c.definition_hash,"compiled_program_hash":c.compiled_program_hash,"keyword_bindings":c.keyword_bindings}
func click_button(button: Control) -> void:
	await move_mouse(button.get_global_rect().get_center())
	await press_mouse(button.get_global_rect().get_center(),true)
	await press_mouse(button.get_global_rect().get_center(),false)
	await process_frame
func _run() -> void:
	root.size=Vector2i(1440,900)
	app=load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app._startup_enter()
	var store: AppStore=app.store
	store.settings.backend_url="http://127.0.0.1:1"
	store._ensure_context()
	await process_frame
	var base: Dictionary=CardRuntime.parse_json(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json")).value
	base.keywords=[]
	base.abilities=[]
	for i in 32:
		var spec:=base.duplicate(true)
		spec.name="构筑%02d"%i
		spec.sin="lust" if i%2==0 else "envy"
		var raw:=record(spec,AppStore.uuid(),1)
		remote_records.append(raw)
		store._ingest_remote(raw,store._bound_server,[])
	app._navigate("library")
	await process_frame
	check(app.content.find_child("SavedDecksButton",true,false)!=null,"Dedicated saved deck entry")
	app._new_deck_dialog()
	await process_frame
	var primary: OptionButton=app.overlay.find_child("NewDeckMainSin",true,false)
	var secondary: OptionButton=app.overlay.find_child("NewDeckAllySin",true,false)
	var create: Button=app.overlay.find_child("StartDeckBuilding",true,false)
	check(create.disabled,"Initial sin must be selected in creation flow")
	primary.select(1);primary.item_selected.emit(1)
	check(secondary.is_item_disabled(1),"Cannot select initial sin twice")
	secondary.select(5)
	app.overlay.find_child("NewDeckName",true,false).text="双罪孽牌组"
	create.pressed.emit()
	for i in 6: await process_frame
	check(store.main_sin=="wrath" and store.ally_sin=="gloom","Both choices saved in working deck")
	check(store.deck_ids.is_empty(),"New deck starts empty")
	var face: Control=app.library_grid.get_child(0).get_child(0)
	var id: String=face.drag_payload.card_id
	await click_button(face)
	check(store.deck_ids==[id],"Actual left click adds exactly one card")
	check(store.get_card(id).definition.sin=="lust","Card outside both selected sins allowed")
	await click_button(face)
	check(store.deck_count(id)==2,"Repeated click adds one copy at a time")
	await click_button(app.library_deck_nodes[id])
	check(store.deck_count(id)==1,"Actual deck row click removes one copy")
	check(not is_instance_valid(app.overlay),"Adding/removing does not open details")
	await press_mouse(face.get_global_rect().get_center(),true,MOUSE_BUTTON_RIGHT)
	await press_mouse(face.get_global_rect().get_center(),false,MOUSE_BUTTON_RIGHT)
	check(is_instance_valid(app.overlay) and store.deck_count(id)==1,"Right click opens library details without adding")
	app._close_modal()
	await process_frame
	var strip: Control=app.library_deck_nodes[id]
	await press_mouse(strip.get_global_rect().get_center(),true,MOUSE_BUTTON_RIGHT)
	await press_mouse(strip.get_global_rect().get_center(),false,MOUSE_BUTTON_RIGHT)
	check(is_instance_valid(app.overlay) and store.deck_count(id)==1,"Right click opens deck details without removing")
	app._close_modal()
	await process_frame
	for mobile_card in [face,strip]:
		mobile_card.touch_gate.touch_mode=true
		await press_mouse(mobile_card.get_global_rect().get_center(),true)
		await create_timer(0.55).timeout
		check(is_instance_valid(app.overlay),"Long press opens mobile library/deck details")
		check(not root.gui_is_dragging(),"Stationary hold does not start deck dragging")
		await press_mouse(mobile_card.get_global_rect().get_center(),false)
		check(store.deck_count(id)==1,"Release after inspection neither adds nor removes a card")
		app._close_modal();await create_timer(0.3).timeout
		mobile_card.touch_gate.touch_mode=false
	var scroll: ScrollContainer=app.library_scroll
	scroll.scroll_vertical=520
	for i in 4: await process_frame
	var before:=scroll.scroll_vertical
	check(before>0,"Scrolled fixture")
	app._library_add_card(str(store.cards[-1].card_id))
	for i in 6:
		await process_frame
		check(app.library_scroll==scroll and scroll.scroll_vertical==before,"Click changes keep scroll stable")
	app._save_deck_dialog()
	app.overlay.find_child("SaveDeckName",true,false).text="已保存构筑"
	app.overlay.find_child("ConfirmDeckSave",true,false).pressed.emit()
	await process_frame
	var saved_id:=store.active_deck_id
	check(store.local_deck(saved_id).ally_sin=="gloom" and store.local_deck(saved_id).cards.size()==2,"Save persists cards and both sins")
	app._saved_decks_dialog()
	await process_frame
	check(app.overlay.find_child("EditDeck_"+saved_id,true,false)!=null,"Saved deck manager exposes editing")
	await snap("decks865-saved")
	app._close_modal()
	check(store.new_local_deck("另一套","","pride","envy").ok,"Create second deck")
	check(store.load_local_deck(saved_id).ok and store.main_sin=="wrath" and store.ally_sin=="gloom","Switch restores both sins")
	var old: Dictionary=store.get_card(id).duplicate(true)
	var spec: Dictionary=old.definition.duplicate(true)
	spec.name="已更新构筑"
	spec.attack=7
	spec.cost=4
	var revised:=record(spec,remote_records[0].card_id,2)
	var incoming:=store._ingest_remote(revised,store._bound_server,[])
	check(store._follow_latest_decks(),"Published revision updates deck references")
	check(store.deck_ids.size()==2 and store.deck_ids[0]==incoming.card_id,"Working deck updates without changing quantity")
	check(store.local_deck(saved_id).cards[0]==incoming.card_id,"Saved inactive/active deck references update")
	check(store.get_card(id).definition_hash==old.definition_hash,"Historical record stays immutable")
	check(not store._follow_latest_decks(),"Repeated refresh is idempotent")
	var hq_spec:=base.duplicate(true)
	hq_spec.merge({"name":"构筑总部","kind":"hq","unit_class":null,"cost":0,"attack":0,"operation_cost":0,"health":20,"draw_rule":{"base":1},"appearance":{"emblem":"hq"}},true)
	var hq_id:=AppStore.uuid()
	var old_hq:=store._ingest_remote(record(hq_spec,hq_id,1),store._bound_server,[])
	check(store.select_headquarters(old_hq.card_id).is_empty(),"Choose headquarters outside forty cards")
	store.save_local_deck(store.deck_name)
	var second:=store.save_local_deck("另存副本",true)
	hq_spec.health=30
	var new_hq:=store._ingest_remote(record(hq_spec,hq_id,2),store._bound_server,[])
	check(store._follow_latest_decks() and store.headquarters_id==new_hq.card_id,"Working headquarters follows latest revision")
	check(store.local_deck(saved_id).headquarters_id==new_hq.card_id and store.local_deck(second.deck.id).headquarters_id==new_hq.card_id,"Inactive and active saved headquarters both update")
	check(store.get_card(old_hq.card_id).definition.health==20,"Old headquarters definition stays immutable")
	store.changed.emit()
	await process_frame
	check(app.library_deck_nodes.has(incoming.card_id) and app.library_deck_nodes[incoming.card_id].record.definition.attack==7,"Deck column renders latest values")
	store.save_profile()
	var reloaded:=AppStore.new()
	root.add_child(reloaded)
	check(reloaded.ally_sin=="gloom" and reloaded.deck_ids==store.deck_ids,"Restart retains secondary sin and latest deck")
	check(reloaded.rename_local_deck(saved_id,"重命名").ok and reloaded.local_deck(saved_id).name=="重命名","Local manager rename persists")
	check(reloaded.delete_local_deck(saved_id).ok and reloaded.local_deck(saved_id).is_empty(),"Local manager deletion")
	reloaded.queue_free()
	app._new_deck_dialog()
	await snap("decks865-create")
	app._close_modal()
	await snap("decks865-editor")
	app.queue_free()
	await process_frame
	print("LIBRARY_TOUCH902_RESULT checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
