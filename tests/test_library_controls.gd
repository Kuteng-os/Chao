extends "res://tests/test_ui.gd"
const Title = preload("res://scripts/ui/card_title.gd")
const IDS = ["11111111-1111-4111-8111-111111111111","22222222-2222-4222-8222-222222222222"]
func _run() -> void:
	app=load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.store.settings.backend_url="http://127.0.0.1:1"
	app.store._ensure_context()
	await process_frame
	app.store._faction_catalogs[app.store._bound_server]=[{"faction_id":IDS[0],"name":"晨曦","role":"major","color":"#876440","icon_id":null},{"faction_id":IDS[1],"name":"极夜","role":"major","color":"#496359","icon_id":null}]
	app.store._activate_factions()
	var base: Dictionary=CardRuntime.parse_json(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json")).value
	base.keywords=[]
	for i in 6:
		var spec: Dictionary=base.duplicate(true)
		spec.name="候选"+str(i)
		spec["faction_id"]=IDS[1] if i==1 else IDS[0]
		spec["rarity"]="elite" if i==2 else "standard"
		spec.unit_class="infantry" if i==3 else "tank"
		spec.appearance.emblem=spec.unit_class
		spec.cost=4 if i==4 else 3
		var draft: Dictionary=await app.store.create_draft(spec)
		check(draft.ok,"Filter fixture: " + str(draft.get("error","")))
		if not draft.ok: quit(1);return
		await app.store.confirm_draft(draft.draft)
	app._navigate("library")
	await process_frame
	var search=app.content.find_child("LibrarySearch",true,false)
	search.text="候选"
	search.text_changed.emit(search.text)
	check(app.library_count.text=="6 张卡牌","Search matches names")
	app.content.find_child("LibraryTypeFilter",true,false).item_selected.emit(2)
	check(app.library_count.text=="5 张卡牌","Type combines with text")
	app.library_faction=IDS[0]
	app._populate_library()
	check(app.library_count.text=="4 张卡牌","Faction combines with text and type")
	app.content.find_child("LibraryRarityFilter",true,false).item_selected.emit(1)
	check(app.library_count.text=="3 张卡牌","Rarity combines")
	app.content.find_child("LibraryCostFilter",true,false).item_selected.emit(3)
	check(app.library_count.text=="2 张卡牌","Cost combines all five filters")
	search.text_changed.emit("候选0")
	check(app.library_count.text=="1 张卡牌","All five return only exact matching card")
	for button in app.content.find_children("*","Button",true,false):
		check(not button.text in ["进入对战","编辑最新版","导出定义"],"Removed redundant deck controls")
	check(app.content.find_child("MainFaction",true,false)==null,"No editing main-nation selector")
	app._new_deck_dialog()
	await process_frame
	var picker=app.overlay.find_child("NewDeckMainSin",true,false)
	picker.select(1)
	picker.item_selected.emit(1)
	for button in app.overlay.find_children("*","Button",true,false):
		if button.text=="开始选牌": button.pressed.emit();break
	await process_frame
	check(app.store.main_sin=="wrath" and app.store.deck_ids.is_empty(),"Chosen nominal sin saved at creation")
	check(app.store.add_to_deck(app.store.cards[0].card_id).is_empty(),"Nation choice does not restrict composition")
	app._card_details(app.store.cards[0])
	for button in app.overlay.find_children("*","Button",true,false):
		check(not button.text in ["导出定义","编辑最新版"],"Card detail has no definition/editor shortcuts")
	app._close_modal()
	base.name="远征装甲步兵支队"
	base.appearance["name_break"]=4
	check(CardRuntime.compile_card(base,[]).ok,"Visual split compiles in Godot")
	check(Title.lines(base)==PackedStringArray(["远征装甲","步兵支队"]),"Canonical name has no newline")
	base.appearance["name_break"]=base.name.length()
	check(not CardRuntime.compile_card(base,[]).ok,"Trailing empty title line rejected")
	base.appearance["name_break"]=4
	var canvas=HBoxContainer.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_theme_constant_override("separation",35)
	for child in app.content.get_children(): child.queue_free()
	await process_frame
	app.content.add_child(canvas)
	for kind in ["unit","order","counter"]:
		var face=CardFace.new()
		face.spec=base.duplicate(true)
		face.spec.faction_id=IDS[1]
		face.spec.kind=kind
		if kind!="unit":
			face.spec.unit_class=null;face.spec.attack=0;face.spec.health=0;face.spec.operation_cost=0
			face.spec.abilities=[{"trigger":"on_reveal" if kind=="counter" else "on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]
			if kind=="counter": face.spec.counter_trigger="enemy_order_played"
		face.custom_minimum_size=Vector2(252,354)
		face.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		canvas.add_child(face)
	var unit=CardFace.new()
	unit.spec=base.duplicate(true)
	unit.spec.faction_id=IDS[1]
	unit.spec.abilities=[{"trigger":"on_death","effects":[{"op":"draw","player":"owner","amount":1}]}]
	unit.compact=true;unit.current_armor=2
	unit.field_effects=[{"id":"stats","mark":"+","label":"属性修正"}]
	unit.custom_minimum_size=CardFace.FIELD_SIZE*1.5
	unit.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	canvas.add_child(unit)
	await process_frame
	check(unit.effect_badges().size()==3,"Current armor, stat and death effects have separate hanging badges")
	var fit=Title.layout(base,unit.get_theme_default_font(),67,27,13,9)
	check(not fit.overflow and fit.font_size>=9,"Two-line field title fits without dropping below minimum")
	await snap("card-layout089")
	app.queue_free()
	await process_frame
	print("LIBRARY_CONTROLS_RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
