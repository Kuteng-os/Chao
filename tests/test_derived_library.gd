extends "res://tests/test_ui.gd"

func _run() -> void:
	root.size=Vector2i(1440,900)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.store.settings.backend_url="http://127.0.0.1:1";app.store._ensure_context()
	await process_frame
	var store:AppStore=app.store
	var bundle:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("FRONTLINE_DERIVED_FIXTURE")))
	var keywords:Array=bundle.keywords.map(func(e):return e.definition)
	store.cards=[];store.deck_ids=[];store.local_decks=[]
	store._catalogs[store._bound_server]=keywords;store._activate_keywords()
	store._faction_catalogs[store._bound_server]=bundle.factions;store._activate_factions();store.main_faction_id=bundle.factions[0].faction_id
	var child:Dictionary={};var parent:Dictionary={}
	for raw in bundle.cards:
		var record:Dictionary=store._ingest_remote(raw,store._bound_server,keywords)
		check(not record.is_empty(),"server derived record passes Godot frozen program hashes")
		if record.has("derived_from"):child=record
		else:parent=record
	check(child.definition.deck_building=="allowed","explicit author permission arrives in client")
	var raw:=child.duplicate(true);raw.definition.name="仅生成";raw.definition.deck_building="generated_only"
	var compiled:=CardRuntime.compile_card(raw.definition,keywords)
	check(compiled.ok,"generated-only standalone definition compiles for play")
	raw.card_id=AppStore.uuid();raw.definition_hash=compiled.definition_hash;raw.compiled_program_hash=compiled.compiled_program_hash;raw.keyword_bindings=compiled.keyword_bindings
	var blocked:=store._ingest_remote(raw,store._bound_server,keywords)
	check(store.add_to_deck(blocked.card_id).contains("尚未获准") and store.deck_ids.is_empty(),"direct add rejects unapproved token")
	check(store.add_to_deck(child.card_id).is_empty() and store.deck_ids.size()==1,"approved token adds one at a time")
	app._navigate("library");await process_frame;await process_frame
	var blocked_face:Control=app.library_card_nodes[blocked.card_id].get_child(0)
	check(blocked_face.drag_payload.is_empty(),"unapproved token cannot begin deck drag")
	var allowed_face:Control=app.library_card_nodes[child.card_id].get_child(0)
	check(allowed_face.drag_payload.get("type")=="deck_add","approved token uses normal drag")
	check(store.latest_cards().size()==3,"derived cards included in local library")
	app._card_details(blocked);await process_frame
	check(app.get_tree().root.find_children("*","Label",true,false).any(func(n):return "不可主动加入牌组" in n.text),"detail explains unavailable deck use")
	app._close_modal()
	var definition:Dictionary=parent.definition.duplicate(true);definition.tokens[0].media={"sounds":{"play":"a".repeat(64)}}
	compiled=CardRuntime.compile_card(definition,keywords)
	var engine:=BattleEngine.new();var generated:Dictionary=engine._generated_card(compiled,definition.tokens[0].token_id,41)
	check(generated.definition.media.sounds.play=="a".repeat(64),"generated card retains its own sound override")
	check(generated.creator_uid==41,"catalog inclusion does not change creator binding")
	check(not parent.definition.has("media"),"token audio does not overwrite source audio")
	check(store.save_profile(),"local catalog and deck persist")
	print("DERIVED_LIBRARY_RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
