extends "res://tests/draw_showcase0909.gd"

func _run() -> void:
	Engine.max_fps=60
	get_viewport().warp_mouse(Vector2(3,3))
	audio=Audio.new();add_child(audio);audio.preferences.animations=true;audio.preferences.muted=true
	var spec:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	spec.keywords=[];spec.abilities=[];spec.cost=1;spec.operation_cost=0
	var art:=Image.create(64,64,false,Image.FORMAT_RGBA8);art.fill(Color.WHITE)
	var art_id:="d".repeat(64);CardArtCache.textures[art_id]=ImageTexture.create_from_image(art)
	for i in 10:
		var definition:=spec.duplicate(true);definition.name="流畅度"+str(i)
		var card:=CardRuntime.compile_card(definition,[]);card.art_id=art_id
		for copy in 4:deck.append(card)
	game=BattleEngine.new();game.setup(deck,deck,56)
	game.state.active_player=0;game.state.players[0].credits=10;game.state.players[0].max_credits=10
	view=load("res://scripts/ui/battle_view.gd").new();view.theme=ChaoUI.make_theme(false)
	view.state=game.view_for(0);view.connected=true;view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(view)
	await frames(10)
	var old:CardFace=view.visual_faces["h:"+str(game.state.players[0].hand[0].instance_id)]
	view._hover_hand(old,true);await get_tree().create_timer(0.15).timeout
	var held:=old.get_transform();var held_position:=old.position;var capture_id:int=view.backdrop.cards[old.get_instance_id()].viewport.get_instance_id()
	var original_count:int=game.state.players[0].hand.size()
	receive(3)
	check(old.get_transform().is_equal_approx(held),"Snapshot starts at the entire current hand pose without a one-frame rotation/scale snap")
	var jobs:Array=view.presentation.draw_jobs.duplicate()
	var first:Dictionary=jobs[0]
	await at(first.at+view.presentation.DRAW_LIFT+first.hold-0.059)
	check(old.position.distance_to(held_position)<0.01,"Fan begins gently rather than starting at full velocity")
	await at(first.at+first.length-0.035)
	var before_landing:Vector2=old.position
	await at(first.at+first.length+0.001)
	check(old.position.distance_to(before_landing)>0.15,"Fan continues moving until the incoming card lands")
	var first_arrival:CardFace=first.node
	var expected_first_x:float=596.0-(original_count/2.0)*minf(154.0,820.0/original_count)+(view.layout_size.x-1440)/2
	check(absf(old.position.x-expected_first_x)<0.05,"First arrival reserves space for one new card, not the whole batch")
	check(not old.position.is_equal_approx(old.get_meta("rest_position")),"Further slots are not opened prematurely")
	var landed_pose:=first_arrival.get_transform()
	await at(jobs[1].at+jobs[1].length+0.001)
	check(not first_arrival.get_transform().is_equal_approx(landed_pose),"Previously landed card moves with the next arrival")
	for fps in [30]:
		# Advance the final landing at fixed delta to check bounds and continuity.
		# Fresh native rendering of the same transforms is checked each frame.
		var last:Dictionary=jobs[-1]
		await at(last.at+view.presentation.DRAW_LIFT+last.hold-0.06)
		var prior:Vector2=old.position
		for frame in 12:
			await at(last.at+view.presentation.DRAW_LIFT+last.hold-0.06+(frame+1)/float(fps))
			check(old.position.distance_to(prior)<12,"Hand movement has no large single-frame jump")
			prior=old.position
			var capture:Dictionary=view.backdrop.cards[old.get_instance_id()]
			var projected:Vector2=view.backdrop.camera.unproject_position(capture.quad.global_position)*view.backdrop.size/Vector2(view.backdrop.viewport.size)
			var expected:Vector2=old.get_global_transform()*(old.size*0.5)
			check(projected.distance_to(expected)<1,"GPU follows the same frame's fan pose")
	view.presentation.finish()
	check(old.position.is_equal_approx(old.get_meta("rest_position")) and old.scale.is_equal_approx(Vector2.ONE),"All cards finish at the authoritative resting fan")
	check(view.backdrop.cards[old.get_instance_id()].viewport.get_instance_id()==capture_id,"Fan movement reuses the original capture buffer")
	# Removing a card uses the same soft start and finishes smoothly.
	var played:Dictionary=game.state.players[0].hand[-1]
	var start_pose:=old.get_transform();var start_position:=old.position
	check(game.apply_action(0,{"type":"play","hand_id":played.instance_id,"position":0}).is_empty(),"Unit play succeeds")
	view.present_snapshot(game.view_for(0),true,"",-1);view.presentation.set_process(false)
	check(old.get_transform().is_equal_approx(start_pose),"Playing a card preserves other hand poses at the snapshot boundary")
	await at(0.002)
	check(old.position.distance_to(start_position)<0.02,"Hand closes with a gentle start after play")
	await at(0.27)
	check(old.position.distance_to(old.get_meta("rest_position"))>0.1,"Hand closure does not stop early")
	view.presentation.finish()
	check(old.position.is_equal_approx(old.get_meta("rest_position")),"Play closure reaches the final fan without overshoot")
	# The dragged order is composed above the shade, with no fake clear hole.
	var order_spec:=spec.duplicate(true);order_spec.kind="order";order_spec.unit_class=null;order_spec.attack=0;order_spec.health=0
	order_spec.play_target={"side":"enemy","row":"any"};order_spec.abilities=[{"trigger":"on_play","effects":[{"op":"damage","target":"chosen","amount":1}]}]
	old.spec=CardRuntime.display_definition(CardRuntime.compile_card(order_spec,[]))
	view.set_process(false);view._start_hand_drag(old)
	view.hand_drag_tween.kill();view.hand_drag_face.position=Vector2(610,270);view.hand_drag_face.rotation=0;view.hand_drag_face.scale=Vector2.ONE
	await frames(3)
	var front:CardFace=view.hand_drag_face
	var point:Vector2=front.get_global_transform_with_canvas()*Vector2(front.size.x*0.5,front.size.y*0.3)
	var before:Color=get_viewport().get_texture().get_image().get_pixelv(Vector2i(point))
	view.choice_overlay.size=view.layout_size;view.choice_overlay.configure("选择目标",[],false)
	await frames(3)
	var after:Color=get_viewport().get_texture().get_image().get_pixelv(Vector2i(point))
	check(before.get_luminance()>0.85 and after.get_luminance()>before.get_luminance()*0.95,"Native pixels of the dragged card stay bright above a fully covering shade")
	check(front.z_index>view.choice_overlay.z_index and front.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Dragged card remains above shade without blocking target input")
	check(not view.backdrop.cards.has(front.get_instance_id()) and not view.backdrop.cards[old.get_instance_id()].quad.visible,"Drag uses exactly one visible surface, no duplicated capture")
	view.choice_overlay.configure("",[],false);view._finish_hand_drag();await get_tree().create_timer(0.25).timeout;await frames()
	check(view.returning_hand_faces.is_empty() and not old.get_meta("drag_hidden",false) and view.backdrop.cards[old.get_instance_id()].quad.visible,"Cancel restores the original hand cleanly")
	print("HAND_FLOW0910: %d checks, %d failures"%[checks,failures])
	view.queue_free();audio.queue_free();await frames();get_tree().quit(1 if failures else 0)
