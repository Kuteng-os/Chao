extends Node
var checks:=0
var failures:=0
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(message)
func _ready() -> void:
	if OS.has_feature("mobile"): preload("res://scripts/ui/screen_layout.gd").configure(get_window(),true)
	_run.call_deferred()
func _run() -> void:
	var definition: Dictionary={"schema_version":"1.0.0","ruleset_version":"frontline-1","name":"测试部队","flavor_text":"","kind":"unit","unit_class":"infantry","cost":1,"operation_cost":0,"attack":2,"health":3,"keywords":[],"play_target":null,"abilities":[],"tokens":[],"appearance":{"emblem":"infantry"}}
	var deck: Array=[]
	for i in 10:
		var source:=definition.duplicate(true);source.name+=str(i)
		var compiled:=CardRuntime.compile_card(source,[])
		for n in 4: deck.append(compiled)
	var engine:=BattleEngine.new()
	check(engine.setup(deck,deck,56).is_empty(),"battle fixture initializes")
	for owner in [0,1]:
		engine.state.active_player=owner;engine.state.players[owner].credits=12
		for n in 3:
			engine.apply_action(owner,{"type":"play","hand_id":engine.state.players[owner].hand[0].instance_id})
	var view: Control=load("res://scripts/ui/battle_view.gd").new()
	view.state=engine.view_for(0);view.solo=true;view.connected=true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(view)
	await get_tree().process_frame
	var order:=definition.duplicate(true)
	order.merge({"name":"火力支援","kind":"order","unit_class":null,"attack":0,"health":0,"operation_cost":0,"appearance":{"emblem":"order"},"abilities":[{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":2}]}]},true)
	var presentation: Control=view.presentation
	presentation.set_process(false)
	for extent in [Vector2(1440,900),Vector2(1600,900),Vector2(1800,900),Vector2(1950,900),Vector2(1440,1080)]:
		for seat in [0,1]:
			presentation.size=extent
			var events: Array=[]
			for owner in [0,1]: events.append({"kind":"play","owner":owner,"name":"火力支援","card_kind":"order","display_card":{"definition":order}})
			presentation.play(events,{}, {},[],seat)
			presentation._process(0.6)
			check(presentation.reveals.size()==2,"both public played cards shown")
			for owner in [0,1]:
				var face: Control=presentation.reveals[owner]
				var rect:=face.get_rect()
				check((rect.get_center().x<extent.x*0.5)==(owner==seat),"own left, opponent right for either seat")
				check(Rect2(Vector2.ZERO,extent).encloses(rect),"display stays within screen")
				var unit_zone:=Rect2(244+(extent.x-1440)/2,112+(extent.y-900)/2,948,644)
				check(not rect.intersects(unit_zone),"display avoids all five unit columns including effect rails")
				check(rect.end.y<566+(extent.y-900)/2,"display avoids lower controls")
			presentation.finish()
			check(presentation.reveals.is_empty(),"presentation cleans up")
	presentation.size=view.layout_size
	presentation.play([{"kind":"play","owner":0,"card_kind":"order","display_card":{"definition":order}},{"kind":"play","owner":1,"card_kind":"order","display_card":{"definition":order}}],{}, {},[],0)
	presentation._process(0.6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://side-reveals-0820.png")
	presentation.finish();view.queue_free()
	var store:=AppStore.new();store.profile_path="user://lifecycle-ui-test.json";add_child(store);store.set_process(false)
	var id:=AppStore.uuid();var compiled:=CardRuntime.compile_card(definition,[])
	var record: Dictionary={"card_id":id,"revision":1,"definition":definition,"definition_hash":compiled.definition_hash,"compiled_program_hash":compiled.compiled_program_hash,"keyword_bindings":[],"frozen_keywords":[],"cloud_refs":{store.DEFAULT_SERVER:{"card_id":id,"revision":1}},"local_authored":true}
	store.cards=[record];store.deck_ids=[id,id];store.local_decks=[{"id":"deck","name":"保留牌组","cards":[id]}]
	var snapshot: Dictionary={"cards":{id:{"archived":true,"revision":1}},"keywords":{},"factions":{}}
	store._apply_content_lifecycle(snapshot)
	check(store.latest_cards().is_empty(),"archived cards hidden by default")
	check(store.latest_cards(true).size()==1,"archive remains retrievable")
	check(store.deck_ids.size()==2 and store.compile_record(store.get_card(id)).ok,"archive keeps existing deck and rules usable")
	snapshot.cards[id].archived=false;store._apply_content_lifecycle(snapshot)
	check(store.latest_cards().size()==1,"restore returns card to default list")
	store.pending_sync={"payload":{"cards":[{"local_card_id":id,"definition":definition,"definition_hash":compiled.definition_hash}],"keywords":[]}}
	snapshot.cards[id]={"deleted":true,"hashes":[compiled.definition_hash],"revision":3}
	store._apply_content_lifecycle(snapshot)
	check(store.cards.is_empty() and store.deck_ids.is_empty(),"hard delete removes local card and active deck copies")
	check(store.local_decks[0].cards.is_empty() and store.local_decks[0].name=="保留牌组","saved deck preserved with removed copies")
	check(store.pending_sync.is_empty(),"stale sync retry cannot resurrect deleted card")
	check(store._build_sync_job(store.keyword_definitions).is_empty(),"deleted content not uploaded")
	store.queue_free()
	print("CONTENT_UI_0820 ",checks," checks, ",failures," failures; userdata=",OS.get_user_data_dir())
	get_tree().quit(1 if failures else 0)
