extends Node
var checks:=0
var failures:=0
var actions: Array=[]
var view: Control

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(message)

func _ready() -> void:
	if OS.has_feature("mobile"): preload("res://scripts/ui/screen_layout.gd").configure(get_window(),true)
	_run.call_deferred()

func settle() -> void:
	var deadline:=Time.get_ticks_msec()+6000
	while view.input_locked and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	await get_tree().process_frame
	check(not view.input_locked,"bounded playback finishes")

func snap(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://choice-"+name+".png")

func _run() -> void:
	get_viewport().warp_mouse(Vector2(4,4))
	var spec: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	spec.keywords=[];spec.abilities=[];spec.cost=1;spec.health=10
	var deck: Array=[]
	for i in 10:
		spec.name="测试单位"+str(i)
		var card:=CardRuntime.compile_card(spec,[])
		for n in 4: deck.append(card)
	var game:=BattleEngine.new()
	check(game.setup(deck,deck,56).is_empty(),"battle fixture initializes")
	game.state.active_player=0;game.state.players[0].credits=12
	var target: Dictionary=game._new_unit(1,deck[0])
	var ally: Dictionary=game._new_unit(0,deck[0])
	ally.born_turn=-1
	spec.name="玉兽"
	spec.abilities=[{"trigger":"on_death","target":{"side":"enemy","row":"any"},"effects":[{"op":"damage","target":"chosen","amount":{"stat":"source_base_health"}}]}]
	var source:=CardRuntime.compile_card(spec,[])
	check(source.ok,"bound target card compiles")
	game.state.players[0].hand.append({"instance_id":"binding","card":source})
	view=load("res://scripts/ui/battle_view.gd").new()
	view.state=game.view_for(0);view.connected=true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	view.action_requested.connect(func(action): actions.append(action))
	await get_tree().process_frame
	view.present_snapshot(game.view_for(0),true,"",ally.uid)
	await get_tree().process_frame
	check(not view.choice_overlay.visible,"ordinary attack has no shade")
	var face: Control=view.visual_faces["u:%d"%ally.uid]
	var center: Vector2=face.card_center_in_parent()
	check(is_equal_approx(center.x,face.position.x+face.card_body_rect().get_center().x),"unit center excludes effect rail")
	check(view.target_rects[ally.uid].get_center().is_equal_approx(center),"target geometry uses same printed center")
	var first_hand: Control=view.visual_faces["h:"+str(view.state.players[0].hand[0].instance_id)]
	check(first_hand.position.y>view.visual_faces["hq:0"].get_rect().end.y+16 and first_hand.position.y<view.layout_size.y-75,"Hand leaves support clear while keeping a visible grabbing area")
	if not view.touch_mode:
		view._inspect(first_hand)
		await get_tree().create_timer(0.12).timeout
		check(is_instance_valid(view.inspector),"hover opens hand details")
		first_hand.mouse_exited.emit()
		check(not is_instance_valid(view.inspector),"leaving hand closes details synchronously")
		view._inspect(first_hand)
		first_hand.mouse_exited.emit()
		await get_tree().create_timer(0.12).timeout
		check(not is_instance_valid(view.inspector),"leaving before delay cancels pending popup")
	check(game.apply_action(0,{"type":"play","hand_id":"binding"}).is_empty(),"deploy suspends for target")
	view.present_snapshot(game.view_for(0),true,"",-1)
	await settle()
	check(view.choice_overlay.visible and "部署" in view.choice_overlay.message.text,"deployment shade has explicit prompt")
	check(not view.choice_overlay.can_cancel,"committed choice cannot cancel paid deployment")
	check(not view.choice_overlay._has_point(view.target_rects[target.uid].get_center()),"target click passes shade")
	check(view.choice_overlay._has_point(Vector2(32,430)),"shade blocks background")
	view._face_pressed(view.visual_faces["u:%d"%ally.uid])
	check(actions.is_empty(),"invalid ally cannot submit choice")
	view._emit_action({"type":"end_turn"})
	check(actions.is_empty(),"cannot end turn during choice")
	await snap("deployment")
	var target_face: Control=view.visual_faces["u:%d"%target.uid]
	var click: Vector2=target_face.get_global_transform()*target_face.card_body_rect().get_center()
	# Keep the native pointer aligned with injected events between rendered frames.
	get_viewport().warp_mouse(click)
	await get_tree().process_frame
	var motion:=InputEventMouseMotion.new()
	motion.position=click;motion.global_position=click
	get_viewport().push_input(motion,true)
	for pressed in [true,false]:
		var button:=InputEventMouseButton.new()
		button.position=click;button.global_position=click;button.button_index=MOUSE_BUTTON_LEFT;button.pressed=pressed
		get_viewport().push_input(button,true)
		await get_tree().process_frame
	check(actions.size()==1 and actions[0].type=="choose_target" and actions[0].target_uid==target.uid,"legal target submits choice")
	check(game.apply_action(0,actions.pop_back()).is_empty(),"authority accepts choice")
	view.present_snapshot(game.view_for(0),true,"",-1)
	await settle()
	check(not view.choice_overlay.visible,"shade clears after choice")
	var order:=spec.duplicate(true)
	order.name="精确炮击";order.kind="order";order.unit_class=null;order.attack=0;order.health=0;order.operation_cost=0;order.appearance.emblem="order"
	order.abilities=[{"trigger":"on_play","effects":[{"op":"damage","target":"enemy_hq","amount":2}]}]
	var compiled:=CardRuntime.compile_card(order,[])
	check(compiled.ok,"order reveal fixture compiles")
	for owner in 2:
		game.state.active_player=owner;game.state.players[owner].credits=12
		game.state.players[owner].hand.append({"instance_id":"order"+str(owner),"card":compiled})
		check(game.apply_action(owner,{"type":"play","hand_id":"order"+str(owner)}).is_empty(),"order resolves")
		view.present_snapshot(game.view_for(0),true,"",-1)
		await get_tree().create_timer(0.34).timeout
		check(view.presentation.reveals.size()==1,"both owners show played order face")
		check(view.presentation.reveals[0].spec.name=="精确炮击" and view.presentation.reveals[0].modulate.a>0.9,"revealed card readable")
		check(view.presentation.reveals[0].mouse_filter==Control.MOUSE_FILTER_IGNORE,"order flash does not intercept input")
		await snap("order-"+str(owner))
		await settle()
		check(not view.presentation.reveals.is_empty(),"input resumes while cosmetic reveal remains readable")
		await get_tree().create_timer(0.80).timeout
		check(view.presentation.reveals.is_empty(),"reveal cleans up after animation")
	await snap("finished")
	print("CHOICE REVEAL UI: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
