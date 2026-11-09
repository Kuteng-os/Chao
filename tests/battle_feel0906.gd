extends Node
var checks:=0
var failures:=0
var view:Control

func check(ok:bool, label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)

func _ready()->void:_run.call_deferred()

func frames(count:=2)->void:
	for i in count:await get_tree().process_frame
	await RenderingServer.frame_post_draw

func settle()->void:
	var limit:=Time.get_ticks_msec()+4000
	while view.input_locked and Time.get_ticks_msec()<limit:await get_tree().process_frame
	check(not view.input_locked,"Resolution completes without waiting on cosmetics")

func _run()->void:
	get_viewport().warp_mouse(Vector2(4,4))
	var spec:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	spec.name="城市守卫";spec.keywords=[];spec.abilities=[];spec.cost=1;spec.operation_cost=0;spec.attack=3;spec.health=6
	var unit_spec:=spec.duplicate(true)
	var unit:=CardRuntime.compile_card(spec,[])
	var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/visual090_assets/catalog.json"))
	unit.art_id=fixtures[0].art_id
	CardArtCache.textures[unit.art_id]=load("res://tests/visual090_assets/"+unit.art_id+".png")
	spec=spec.duplicate(true)
	spec.name="集中火力";spec.kind="order";spec.unit_class=null;spec.attack=0;spec.health=0;spec.appearance.emblem="order"
	spec.abilities=[{"trigger":"on_play","effects":[{"op":"damage","target":"enemy_hq","amount":1}]}]
	var order:=CardRuntime.compile_card(spec,[])
	check(order.ok and unit.ok,"Fixtures compile")
	var deck:Array=[]
	for i in 10:
		var definition:=unit_spec.duplicate(true);definition.name+=str(i)
		var card:=CardRuntime.compile_card(definition,[]);card.art_id=unit.art_id
		for copy in 4:deck.append(card)
	var game:=BattleEngine.new();var error:=game.setup(deck,deck,56)
	check(error.is_empty(),"Battle starts: "+error)
	if not error.is_empty():get_tree().quit(1);return
	game.state.active_player=0;game.state.players[0].credits=10;game.state.players[0].max_credits=10
	var attacker:Dictionary=game._new_unit(0,unit);attacker.row="front";attacker.born_turn=-1
	game._new_unit(1,unit)
	view=load("res://scripts/ui/battle_view.gd").new();view.theme=ChaoUI.make_theme(false)
	view.state=game.view_for(0);view.connected=true;view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(view)
	await get_tree().create_timer(0.5).timeout
	# Native GPU checks use direct interaction state, independent of OS cursor movement.
	view.set_process(false)
	var source:CardFace=view.visual_faces["h:"+str(view.state.players[0].hand[-1].instance_id)]
	var base_count:int=view.backdrop.cards.size()
	var capture:Dictionary=view.backdrop.cards[source.get_instance_id()]
	var stable_size:Vector2i=capture.viewport.size
	source.highlighted=true
	await frames(3)
	var selected_pixels:PackedByteArray=capture.viewport.get_texture().get_image().get_data()
	check(selected_pixels.count(0)<selected_pixels.size()*0.7,"Selected card still contains its printed face")
	for i in 8:
		await frames(3)
		check(capture.viewport.get_texture().get_image().get_data()==selected_pixels,"Held selection does not flash or repaint itself")
	view._hover_hand(source,true)
	var hover_tween:Tween=source.get_meta("hover_tween")
	view._hover_hand(source,true)
	check(hover_tween==source.get_meta("hover_tween"),"Repeated hover notifications do not restart the lift")
	await get_tree().create_timer(0.17).timeout
	check(capture.viewport.size==stable_size,"Hover scale preserves the capture buffer")
	view._hover_hand(source,false)
	source.highlighted=false
	await get_tree().create_timer(0.17).timeout
	for attempt in 3:
		view._start_hand_drag(source)
		for point in [Vector2(560,430),Vector2(750,300),Vector2(650,490)]:
			view.hand_drag_face.position=point
			await frames()
			var stage:Control=view.backdrop
			check(view.hand_drag_face.position.is_equal_approx(point) and not stage.cards.has(view.hand_drag_face.get_instance_id()),"Dragged canvas face follows its position without a duplicate GPU capture")
			check(not stage.cards[source.get_instance_id()].quad.visible and view.hand_drag_face.self_modulate.a==1,"One extracted face, no original ghost")
		view.aim.region=Rect2(210,110,1020,649);view.aim.size=view.layout_size;view.aim.valid=true
		view.aim.origin=view.hand_drag_face.card_top_in_parent();view.aim.hint="松开部署";view.aim.queue_redraw()
		await frames()
		if attempt==0:get_viewport().get_texture().get_image().save_png("res://../../battle-feel-drag.png")
		view._finish_hand_drag()
		var return_deadline:=Time.get_ticks_msec()+230
		var duplicate_seen:=false
		while Time.get_ticks_msec()<return_deadline:
			await frames(1)
			duplicate_seen=duplicate_seen or source.self_modulate.a>0
		check(not duplicate_seen,"Return tween never flashes the 2D input surface over its projection")
		await frames()
		check(view.backdrop.cards[source.get_instance_id()].quad.visible and source.self_modulate.a==0,"Canceled drag restores only the 3D original")
		check(view.backdrop.cards.size()==base_count,"Repeated drag and return release temporary render resources")
	view.set_process(true)
	# Resolve successive orders while the previous side display is still on screen.
	for i in 3:
		var owner:int=0 if i<2 else 1
		game.state.active_player=owner;game.state.players[owner].credits=10
		var id:="feel-order-%d"%i
		game.state.players[owner].hand.append({"instance_id":id,"card":order})
		check(game.apply_action(owner,{"type":"play","hand_id":id}).is_empty(),"Order resolves authoritatively")
		view.present_snapshot(game.view_for(0),true,"",-1)
		check(view.presentation.duration<=0.51,"Single order's effects gate input for at most 510 ms")
		await get_tree().create_timer(0.22).timeout
		var visible:Array=view.presentation.reveal_jobs.filter(func(j):return j.age>=0)
		check(visible.size()<=2,"At most one visible side display per player")
		check(visible.filter(func(j):return j.friendly==(owner==0)).size()==1,"New same-side reveal replaces previous display")
		await settle()
		check(not view.presentation.reveals.is_empty(),"Readable reveal persists after input is released")
		check(view.visual_faces["hq:%d"%(1-owner)].value==game.state.players[1-owner].hp,"Displayed HP already equals resolved HP when input resumes")
		if i==0:
			await frames()
			get_viewport().get_texture().get_image().save_png("res://../../battle-feel-order.png")
	await get_tree().create_timer(0.8).timeout
	check(view.presentation.reveals.is_empty() and view.presentation.reveal_jobs.is_empty(),"Side displays eventually release their controls")
	var final_hash:=CardRuntime.canonical(game.state).sha256_text()
	view.present_snapshot(game.view_for(0),true,"",-1)
	check(not view.input_locked and final_hash==CardRuntime.canonical(game.state).sha256_text(),"Duplicate snapshots do not replay or change the battle")
	print("BATTLE_FEEL0906: %d checks, %d failures"%[checks,failures])
	view.queue_free();await frames()
	get_tree().quit(1 if failures else 0)
