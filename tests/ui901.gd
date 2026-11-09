extends "res://tests/draw_showcase0909.gd"
const Related=preload("res://scripts/ui/related_cards.gd")

func _run() -> void:
	Engine.max_fps=60
	get_viewport().warp_mouse(Vector2(2,2))
	var spec:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	spec.name="衍生制造者";spec.keywords=[];spec.cost=2
	spec.tokens=[{"token_id":"child","name":"支援单位","unit_class":"infantry","attack":2,"health":3,"keywords":[]},{"token_id":"order","name":"火球术","kind":"order","cost":1,"operation_cost":0,"unit_class":null,"attack":0,"health":0,"keywords":[],"abilities":[{"trigger":"on_play","effects":[{"op":"damage","target":"enemy_hq","amount":2}]}]},{"token_id":"counter","name":"紧急反制","kind":"counter","cost":1,"operation_cost":0,"unit_class":null,"attack":0,"health":0,"keywords":[],"counter_trigger":"enemy_order_played","abilities":[{"trigger":"on_reveal","effects":[{"op":"draw","player":"owner","amount":1}]}]}]
	spec.abilities=[{"trigger":"on_play","effects":[{"op":"create_card","token_id":"child","player":"owner","amount":1}]}]
	var card:=CardRuntime.compile_card(spec,[])
	check(card.ok,"Three derived types compile: "+str(card.get("error","")))
	if not card.ok:get_tree().quit(1);return
	var art:=Image.create(32,32,false,Image.FORMAT_RGBA8);art.fill(Color("74b8db"));var aid:="c".repeat(64);CardArtCache.textures[aid]=ImageTexture.create_from_image(art)
	card.token_art_ids={"child":aid,"order":aid,"counter":aid}
	var before:=CardRuntime.sha(card);var children:=Related.entries(card)
	check(children[0].derived_deck_building=="generated_only","Unspecified derived deck permission remains generated-only")
	check(children.size()==3,"Unit, order and counter all listed")
	check(children[0].definition.cost==1 and children[0].definition.kind=="unit","Legacy token defaults match engine")
	check(children[1].definition.kind=="order" and children[2].definition.kind=="counter","Correct types retained")
	check(children[0].art_id==aid and children[2].art_id==aid,"Independent token artwork retained")
	check(Related.entries(children[0]).size()==2,"Derived chain excludes only its current form")
	check(CardRuntime.sha(card)==before,"Browsing does not mutate frozen card")
	for i in 10:
		var unique:=spec.duplicate(true);unique.name+=str(i)
		var c:=CardRuntime.compile_card(unique,[]);c.token_art_ids=card.token_art_ids.duplicate(true)
		for copy in 4:deck.append(c)
	game=BattleEngine.new();var setup_error:=game.setup(deck,deck,56);check(setup_error.is_empty(),"Setup: "+setup_error)
	if not setup_error.is_empty():get_tree().quit(1);return
	game.state.active_player=0;game.state.players[0].credits=2
	view=load("res://scripts/ui/battle_view.gd").new();view.state=game.view_for(0);view.connected=true;view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(view);await frames(12)
	var id:String=game.state.players[0].hand[0].instance_id;var face:CardFace=view.visual_faces["h:"+id]
	check(face.can_act,"Exact cost marks legal card")
	game.state.players[0].credits=1;view.present_snapshot(game.view_for(0),true,"",-1);await frames()
	check(not face.can_act,"Insufficient cost removes marker")
	game.state.players[0].credits=2
	for i in 4:game._new_unit(0,card)
	view.present_snapshot(game.view_for(0),true,"",-1);await frames();check(not face.can_act,"Full support line is not marked despite enough cost")
	game.state.units.clear();view.present_snapshot(game.view_for(0),true,"",-1);await frames()
	for i in 4:
		view.presentation.finish();await frames()
	face=view.visual_faces["h:"+id]
	await view._inspect(face);check(not view.inspector_pinned,"Hover remains transient")
	face.mouse_exited.emit();check(not is_instance_valid(view.inspector),"Leaving hand closes hover immediately")
	var top_face:CardFace=view.visual_faces["h:"+str(game.state.players[0].hand[-1].instance_id)]
	var point:=top_face.get_global_transform()*Vector2(100,26)
	var motion:=InputEventMouseMotion.new();motion.position=point;get_viewport().push_input(motion,true)
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_RIGHT;press.position=point;press.pressed=true;get_viewport().push_input(press,true);await frames(10)
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_RIGHT;release.position=point;release.pressed=false;get_viewport().push_input(release,true);await frames(10)
	check(is_instance_valid(view.inspector) and view.inspector_pinned,"Right mouse press and release keep derived details open")
	view._hide_inspector()
	await view._inspect(face,true);face.mouse_exited.emit();check(is_instance_valid(view.inspector) and view.inspector_pinned,"Explicit details stay open to access derived button")
	view._show_related_cards(card);await frames(10)
	check(is_instance_valid(view.related_panel) and view.related_panel.get_meta("screen_space",false),"Battle derived panel remains above 3D stage")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../../ui901-derived.png")
	view._hide_inspector();await frames()
	check(not is_instance_valid(view.related_panel),"Close cleans up related panel")
	view.present_snapshot(game.view_for(0),false,"",-1);await frames();check(not view.visual_faces["h:"+id].can_act,"Disconnected state removes playable mark")
	view.present_snapshot(game.view_for(0),true,"",-1);await frames(12)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../../ui901-playable.png")
	view.queue_free();await frames();print("UI901: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
