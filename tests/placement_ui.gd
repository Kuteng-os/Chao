extends Node
var checks := 0
var failures := 0
var actions: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	source.keywords = []
	source.cost = 1
	var deck: Array = []
	for i in 10:
		source.name = "阵线测试"+str(i)
		var card := CardRuntime.compile_card(source,[])
		for copy in 4: deck.append(card)
	var engine := BattleEngine.new()
	check(engine.setup(deck,deck,56).is_empty(),"UI battle initializes")
	engine.state.active_player = 0
	engine.state.players[0].credits = 12
	var first: Dictionary = engine._new_unit(0,deck[0],"",false,0)
	var second: Dictionary = engine._new_unit(0,deck[1],"",false,2)
	var target: Dictionary = engine._new_unit(1,deck[0])
	source.play_target = {"side":"enemy","row":"any"}
	source.abilities = [{"trigger":"on_play","effects":[{"op":"damage","target":"chosen","amount":1}]}]
	var targeted := CardRuntime.compile_card(source,[])
	check(targeted.ok,"Targeted deployment fixture compiles")
	engine.state.players[0].hand.append({"instance_id":"targeted","card":targeted})
	var view: Control = load("res://scripts/ui/battle_view.gd").new()
	view.state = engine.view_for(0)
	view.connected = true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	view.action_requested.connect(func(action): actions.append(action))
	view.hand_clicked.connect(func(entry): view.present_snapshot(engine.view_for(0),true,str(entry.instance_id),-1))
	await get_tree().process_frame
	var support: Array = [view.visual_faces["u:%d"%first.uid],view.visual_faces["hq:0"],view.visual_faces["u:%d"%second.uid]]
	check(support[0].position.x+support[0].size.x < support[1].position.x,"HQ never overlaps left adjacent card")
	check(support[1].position.x+support[1].size.x < support[2].position.x,"HQ never overlaps right adjacent card")
	var original := CardRuntime.canonical(engine.state)
	for slot in 4:
		var marker: Rect2 = view._placement_marker("support",slot)
		var point: Vector2 = marker.get_center()*view.board.scale+view.board.position
		var regular: Dictionary = view._drop_action(point,{"type":"play","hand_id":engine.state.players[0].hand[0].instance_id})
		check(regular.get("position")==slot and regular.get("type")=="play","Dropping in every gap maps to its exact slot")
		var prepare: Dictionary = view._drop_action(point,{"type":"play","hand_id":"targeted"})
		check(prepare.get("type")=="prepare_play" and prepare.get("position")==slot,"Targeted deployment first chooses insertion slot")
		view._emit_action(prepare)
		check(actions.size()==slot,"Placement preview does not submit an incomplete action")
		check(CardRuntime.canonical(engine.state)==original,"Preview never spends resources or changes authority")
		view._face_pressed(view.visual_faces["u:%d"%target.uid])
		check(actions.size()==slot+1,"Choosing target submits exactly once")
		check(actions.back()=={"type":"play","hand_id":"targeted","target_uid":target.uid,"position":slot},"Target selection retains chosen insertion slot")
		check(view.pending_deployment.is_empty(),"Submitted deployment clears pending selection")
	var marker: Rect2 = view._placement_marker("support",0)
	view._emit_action(view._drop_action(marker.get_center()*view.board.scale+view.board.position,{"type":"play","hand_id":"targeted"}))
	view.present_snapshot(engine.view_for(0),true,"",-1)
	check(view.pending_deployment.is_empty() and actions.size()==4,"Cancel clears preview without playing a card")
	# The public projection is sufficient to reconstruct the same legality and layout.
	check(view.rules.line_order(0,"support")==engine.line_order(0,"support"),"Rendered order equals authority order")
	# All three rows retain a real gutter, also at phone and tablet ratios.
	var front_unit: Dictionary=engine._new_unit(0,deck[0]); front_unit.row="front"
	engine.state.state_seq+=1; view.present_snapshot(engine.view_for(0),true,"",-1); view.presentation.finish()
	for dimensions in [Vector2i(1440,900),Vector2i(2560,1440),Vector2i(1400,630),Vector2i(1200,900)]:
		get_window().min_size=Vector2i(640,360); get_window().size=dimensions
		await get_tree().process_frame; await get_tree().process_frame
		var rear: Control=view.visual_faces["hq:0"]
		var opposing: Control=view.visual_faces["hq:1"]
		var front: CardFace=view.visual_faces["u:%d"%front_unit.uid]
		var front_body: Rect2=front.get_transform()*front.card_body_rect()
		check(front_body.position.y-opposing.get_rect().end.y>=32,"Enemy support has a visible gap before the frontline")
		check(rear.position.y-front_body.end.y>=32,"Frontline has a visible gap before own support")
		for key in view.visual_faces:
			if not key.begins_with("h:"): continue
			var face: CardFace=view.visual_faces[key]
			check((face.get_transform()*face.card_body_rect()).position.y-rear.get_rect().end.y>=16,"Resting hand never covers support cards")
		check(view._combat_rect(view.FRONT).encloses(front_body),"Frontline drop region matches its visible row")
		check(view._combat_rect(view.SUPPORT).encloses(rear.get_rect()),"Support drop region matches its visible row")
		check(front_body.size.is_equal_approx(rear.size),"Headquarters and units retain the same row height")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://placement.png")
	view.queue_free()
	await get_tree().process_frame
	print("PLACEMENT UI: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
