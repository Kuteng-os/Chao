extends "res://tests/test_touch_drag.gd"
var actions: Array = []

func _run() -> void:
	root.size = Vector2i(1440,900)
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	spec.kind="order";spec.unit_class=null;spec.cost=1;spec.operation_cost=0;spec.attack=0;spec.health=0;spec.keywords=[]
	spec.appearance.emblem="order"
	spec.abilities=[{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]
	spec.play_target=null
	var compiled:=CardRuntime.compile_card(spec,[])
	check(compiled.ok,"order fixture compiles")
	if not compiled.ok: print(JSON.stringify(compiled));quit(1);return
	var deck: Array=[]
	for i in 10:
		var definition:=spec.duplicate(true)
		definition.name="拖出指令"+str(i)
		var card:=CardRuntime.compile_card(definition,[])
		for n in 4: deck.append(card)
	var engine:=BattleEngine.new()
	var error:=engine.setup(deck,deck,56)
	check(error.is_empty(),"battle starts")
	if not error.is_empty(): print(error);quit(1);return
	engine.state.active_player=0;engine.state.players[0].credits=12
	var view: Control=load("res://scripts/ui/battle_view.gd").new()
	view.state=engine.view_for(0);view.connected=true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(view)
	view.action_requested.connect(func(action):actions.append(action))
	await frames(3)
	for mobile in [true,false]:
		view.touch_mode=mobile
		var face: CardFace=view.visual_faces["h:"+str(view.state.players[0].hand[-1].instance_id)]
		face.touch_gate.touch_mode=mobile
		check(not face.touch_gate.hold_required,"battle card never requires a hold")
		var from: Vector2=face.get_global_transform()*Vector2(110,42)
		await motion(from)
		await press(true)
		await motion(from+Vector2(0,-55))
		check(root.gui_is_dragging(),"immediate battle drag begins before hold threshold")
		check(is_instance_valid(view.hand_drag_face),"hand card is extracted into one moving face")
		check(face.self_modulate.a==0.0,"original face hidden while extracted")
		if view.backdrop._rendering:
			await RenderingServer.frame_post_draw
			check(not view.backdrop.cards[face.get_instance_id()].quad.visible,"extraction hides original 3D surface")
			check(view.hand_drag_face.get_meta("screen_space",false) and view.hand_drag_face.self_modulate.a==1 and not view.backdrop.cards.has(view.hand_drag_face.get_instance_id()),"only extracted canvas surface is visible")
		if is_instance_valid(view.hand_drag_face):
			check(view.hand_drag_face.size==face.size,"extracted card retains hand dimensions")
			check(view.hand_drag_face.pivot_offset==face.pivot_offset,"extracted card retains pivot")
		check(view._drop_action(view.get_local_mouse_position(),view.drag_data).is_empty(),"short pull cannot play even inside the battlefield")
		await press(false);await create_timer(0.25).timeout
		check(actions.is_empty() and not face.get_meta("drag_hidden",false),"short pull returns card without playing")
		from=face.get_global_transform()*Vector2(110,42)
		await motion(from);await press(true);await motion(from+Vector2(0,-55))
		await motion(view.board.get_global_transform()*Vector2(740,340))
		view._process(0)
		check(not view.aim.active,"untargeted order extracts without an arrow")
		check(view.hand_drag_face.position.is_equal_approx(view.board.get_local_mouse_position()-view.hand_drag_offset-Vector2(0,view.hand_drag_lift)),"card follows pointer without a duplicate preview")
		await motion(from+Vector2(0,-45))
		check(view._drop_action(view.get_local_mouse_position(),view.drag_data).is_empty(),"pulling back below the threshold cancels readiness")
		# Invalid release returns the visual and submits no action.
		await motion(view.board.get_global_transform()*Vector2(90,330))
		await press(false)
		await create_timer(0.25).timeout
		check(actions.is_empty(),"invalid drop does not play")
		check(not face.get_meta("drag_hidden",false) and view.returning_hand_faces.is_empty(),"invalid drop restores original card")
		if view.backdrop._rendering:
			check(view.backdrop.cards[face.get_instance_id()].quad.visible and face.self_modulate.a==0,"return restores one 3D face without duplicate 2D face")
		from=face.get_global_transform()*Vector2(110,42)
		await motion(from);await press(true);await motion(from+Vector2(0,-55))
		await motion(view.board.get_global_transform()*Vector2(740,340))
		await press(false);await create_timer(0.15).timeout
		check(actions.size()==1 and actions[0].type=="play","valid drag plays exactly once")
		check(face.ignore_touch_click(),"drag release cannot open card details")
		actions.clear()
	# Targeted orders keep the extracted card; arrow originates at its top.
	var target_spec:=spec.duplicate(true)
	target_spec.play_target={"side":"enemy","row":"any"}
	target_spec.abilities=[{"trigger":"on_play","effects":[{"op":"damage","target":"chosen","amount":1}]}]
	var target_card:=CardRuntime.compile_card(target_spec,[])
	check(target_card.ok,"targeted order compiles")
	if not target_card.ok: print(JSON.stringify(target_card));quit(1);return
	var unit_spec:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	unit_spec.keywords=[]
	var unit_card:=CardRuntime.compile_card(unit_spec,[])
	var enemy:Dictionary=engine._new_unit(1,unit_card)
	engine.state.players[0].hand[-1].card=target_card
	view.present_snapshot(engine.view_for(0),true,"",-1)
	await create_timer(0.8).timeout
	var face:CardFace=view.visual_faces["h:"+str(view.state.players[0].hand[-1].instance_id)]
	face.touch_gate.touch_mode=true;view.touch_mode=true
	var from:Vector2=face.get_global_transform()*Vector2(110,42)
	await motion(from);await press(true);await motion(from+Vector2(0,-55))
	await motion(view.board.get_global_transform()*view.target_rects[enemy.uid].get_center())
	view._process(0)
	check(view.aim.active,"targeted order displays arrow")
	check(view.aim.origin.is_equal_approx(view.hand_drag_face.card_top_in_parent()),"targeted arrow starts on extracted card top")
	await press(false);await frames()
	check(actions.size()==1 and actions[0].target_uid==enemy.uid,"targeted drop submits chosen enemy")
	check(engine.apply_action(0,actions[0]).is_empty(),"targeted action accepted by authority")
	view.present_snapshot(engine.view_for(0),true,"",-1)
	await create_timer(0.8).timeout
	check(not is_instance_valid(view.hand_drag_face) and view.returning_hand_faces.is_empty(),"snapshot cleans drag visuals")
	# Both headquarters are valid effect targets; friendly HQ is not a no-target sentinel.
	actions.clear()
	target_spec.play_target={"side":"any","row":"any","include_hq":true}
	target_card=CardRuntime.compile_card(target_spec,[])
	engine.state.players[0].hand[-1].card=target_card
	var hqid: String=engine.state.players[0].hand[-1].instance_id
	view.present_snapshot(engine.view_for(0),true,"",-1)
	await create_timer(0.8).timeout
	view.present_snapshot(engine.view_for(0),true,"",-1)
	await frames()
	for seat in [0,1]:
		var headquarters: Control=view.visual_faces["hq:%d"%seat]
		check(view.target_rects.has(-101-seat),"each headquarters has persistent effect-target geometry")
		var p: Vector2=view.board.position+headquarters.get_rect().get_center()*view.board.scale
		var drop: Dictionary=view._drop_action(p,{"type":"play","hand_id":hqid})
		check(drop.get("target_uid")==-101-seat,"drag resolves exact headquarters effect target")
	view.visual_faces["hq:0"].pressed.emit()
	check(actions.is_empty(),"clicking HQ never plays a previously clicked hand card")
	face=view.visual_faces["h:"+hqid]
	from=face.get_global_transform()*Vector2(110,42)
	await motion(from);await press(true);await motion(from+Vector2(0,-55))
	for seat in [0,1]:
		check(not view.choice_overlay._has_point(view.target_rects[-101-seat].get_center()),"held order's shade leaves valid HQ targets exposed")
	await motion(view.visual_faces["hq:0"].get_global_rect().get_center())
	check(view.aim.active and view.aim.valid,"HQ order aims only during the held drag")
	await press(false);await frames()
	check(actions.size()==1 and actions[0].target_uid==-101,"dragging to friendly HQ emits one effect choice")
	if not actions.is_empty():check(engine.apply_action(0,actions[0]).is_empty() and engine.state.players[0].hp==19,"HQ choice is accepted and damages the intended side")
	view.queue_free();await frames()
	print("BATTLE DRAG: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)


func motion(point: Vector2) -> void:
	# Keep native polling and injected GUI events at the same pointer position.
	root.warp_mouse(point)
	await frames(1)
	await super.motion(point)
