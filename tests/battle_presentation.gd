extends Node
var checks := 0
var failures := 0
var view: Control
var actions: Array = []

func _ready() -> void:
	if OS.get_name()=="Android": preload("res://scripts/ui/screen_layout.gd").configure(get_window(),true)
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func settle() -> void:
	var deadline := Time.get_ticks_msec()+6500
	while view.input_locked and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(not view.input_locked,"Playback completes within bounded time")

func snap(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://presentation-"+label+".png")

func _run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	source.name = "前线突击队"
	source.keywords = []
	source.cost = 1
	source.operation_cost = 0
	source.attack = 3
	source.health = 4
	var compiled := CardRuntime.compile_card(source,[])
	if not compiled.ok: push_error(JSON.stringify(compiled)); get_tree().quit(1); return
	check(compiled.ok,"Presentation fixture compiles")
	var deck: Array = []
	for i in 10:
		var definition := source.duplicate(true)
		definition.name += str(i)
		var card := CardRuntime.compile_card(definition,[])
		for copy in 4: deck.append(card)
	var engine := BattleEngine.new()
	check(engine.setup(deck,deck,56).is_empty(),"Presentation battle initializes")
	engine.state.active_player = 0
	engine.state.players[0].credits = 12
	var attacker: Dictionary = engine._new_unit(0,compiled)
	attacker.row = "front"
	attacker.born_turn = -1
	var defender: Dictionary = engine._new_unit(1,compiled)
	defender.hp = 2
	defender.damage_taken = 2
	view = load("res://scripts/ui/battle_view.gd").new()
	view.state = engine.view_for(0)
	view.connected = true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	view.action_requested.connect(func(action): actions.append(action))
	await get_tree().process_frame
	var identity: int = view.get_instance_id()
	var key := "u:%d" % int(attacker.uid)
	var original: int = view.visual_faces[key].get_instance_id()
	var original_backdrop: int = view.backdrop.get_instance_id()
	var hand_key: String = "h:"+str(view.state.players[0].hand[0].instance_id)
	var original_hand: int = view.visual_faces[hand_key].get_instance_id()
	view.present_snapshot(engine.view_for(0),true,"",int(attacker.uid))
	check(view.visual_faces[key].get_instance_id()==original,"Selection preserves existing field controls")
	check(view.visual_faces[key].highlighted,"Selection refreshes visible highlight")
	check(view.targets==engine.legal_targets(0,{"type":"attack","uid":attacker.uid}),"Aim uses authoritative legal targets")
	var point: Vector2 = view.target_rects[defender.uid].get_center()*view.board.scale+view.board.position
	get_viewport().warp_mouse(point)
	await get_tree().process_frame
	check(view.aim.active and view.aim.legal_rects.size()>0,"Selection activates visible aiming geometry")
	await snap("aim")
	check(engine.apply_action(0,{"type":"attack","uid":attacker.uid,"target_uid":defender.uid}).is_empty(),"Resolve legal attack")
	var next := engine.view_for(0)
	var attack_events: Array = next.presentation_events.filter(func(e): return e.kind=="attack")
	check(attack_events.size()==1 and attack_events[0].source_uid==attacker.uid and attack_events[0].target_uid==defender.uid,"Public event names exact attacking and defending instances")
	view.present_snapshot(next,true,"",-1)
	check(view.get_instance_id()==identity and view.input_locked,"Authoritative update retains view and gates input during playback")
	check(view.presentation.ghosts.size()==1,"Dead unit stays visible for its death animation")
	check(view.visual_faces[key].get_instance_id()==original,"An attack preserves the living unit node and cached artwork")
	check(view.visual_faces[hand_key].get_instance_id()==original_hand,"An attack preserves unrelated hand controls")
	check(view.backdrop.get_instance_id()==original_backdrop,"Battlefield texture is retained across action snapshots")
	check(view.presentation.duration<=0.48,"A simple attack releases input within 480 ms")
	var ghost: Control = view.presentation.ghosts[0]
	var ghost_rest: Vector2 = view.presentation.ghost_origins[ghost.get_instance_id()]
	view._emit_action({"type":"end_turn"})
	check(actions.is_empty(),"Playback cannot submit duplicate actions")
	var damage_jobs: Array = view.presentation.jobs.filter(func(j): return j.kind=="damage")
	check(damage_jobs.size()==2,"Both combat damage events are presented")
	check(damage_jobs.all(func(j): return j.target is CardFace),"Unit damage never animates headquarters by mistake")
	await get_tree().create_timer(0.40).timeout
	check(ghost.position.distance_to(ghost_rest)<6,"Death ghost shake never accumulates across frames")
	await snap("impact")
	await settle()
	check(view.presentation.ghosts.is_empty(),"Death ghosts are removed after playback")
	check(view.visual_faces[key].current_health==engine._unit(attacker.uid).hp,"Final visual HP equals authoritative HP")
	check(view.visual_faces["hq:0"].value==20,"Unit combat preserves displayed headquarters HP")
	view.present_snapshot(next,true,"",-1)
	check(not view.presentation.running,"Repeated snapshot never repeats an attack")
	# Hidden hand/deck identities and facedown counter names never enter public animation data.
	var hidden := source.duplicate(true)
	hidden.name = "SECRET_COUNTER_QA"
	hidden.kind = "counter"
	hidden.unit_class = null
	hidden.attack = 0
	hidden.health = 0
	hidden.appearance = {"emblem":"counter"}
	hidden["counter_trigger"] = "enemy_order_played"
	hidden.abilities = [{"trigger":"on_reveal","effects":[{"op":"draw","player":"owner","amount":1}]}]
	var counter := CardRuntime.compile_card(hidden,[])
	if not counter.ok: push_error(JSON.stringify(counter)); get_tree().quit(1); return
	check(counter.ok,"Hidden counter fixture compiles")
	engine.state.players[0].hand.append({"instance_id":"hidden-counter","card":counter})
	check(engine.apply_action(0,{"type":"play","hand_id":"hidden-counter"}).is_empty(),"Place hidden counter")
	var public_data := JSON.stringify(engine.view_for(1).presentation_events)
	check(not "SECRET_COUNTER_QA" in public_data and not "definition_hash" in public_data and not "compiled" in public_data,"Public animations exclude facedown names and compiled definitions")
	view.present_snapshot(engine.view_for(0),true,"",-1)
	check(engine.apply_action(0,{"type":"end_turn"}).is_empty(),"Queue opponent turn")
	view.present_snapshot(engine.view_for(0),true,"",-1)
	check(engine.apply_action(1,{"type":"end_turn"}).is_empty(),"Queue local turn")
	view.present_snapshot(engine.view_for(0),true,"",-1)
	check(not view.queued_snapshot.is_empty(),"Rapid snapshots coalesce without interrupting current impact")
	await settle()
	check(view.state.state_seq==engine.state.state_seq,"Latest queued snapshot is eventually rendered")
	check(view.last_event_id==engine.view_for(0).presentation_events.back().id,"Stable event cursor advances once per resolution")
	view.present_snapshot(next,true,"",-1)
	check(view.state.state_seq==engine.state.state_seq and not view.presentation.running,"A delayed old snapshot cannot rewind the board or replay effects")
	var cached: Array = view._legal_for({"type":"unit","uid":attacker.uid})
	var stable := true
	for index in 100: stable = stable and view._legal_for({"type":"unit","uid":attacker.uid})==cached
	check(stable,"Pointer frames reuse stable target legality")
	check(view.legal_cache.size()==1,"Aim maintains one legality cache per source")
	var hand_face: CardFace = view.visual_faces[hand_key]
	view._hover_hand(hand_face,true)
	await get_tree().create_timer(0.14).timeout
	check(hand_face.position.is_equal_approx(hand_face.get_meta("rest_position")-Vector2(0,24)),"Desktop hand lift settles at its intended offset")
	view._hover_hand(hand_face,false)
	await get_tree().create_timer(0.14).timeout
	check(hand_face.position.is_equal_approx(hand_face.get_meta("rest_position")) and hand_face.scale.is_equal_approx(Vector2.ONE),"Desktop hand return restores its exact resting transform")
	var face: CardFace = view.visual_faces[key]
	view.touch_mode = true
	var resting := face.position
	view._inspect(face)
	await get_tree().create_timer(0.3).timeout
	check(is_instance_valid(view.inspector) and is_instance_valid(view.inspector_panel),"Inspection includes full card and separate rules panel")
	check(view.inspector.size.x>=380 and face.position==resting,"Mobile inspector is large and does not transform the touched card")
	check(Rect2(Vector2.ZERO,view.layout_size).encloses(Rect2(view.inspector_panel.position,view.inspector_panel.size)),"Complete inspection panel fits safe board bounds")
	await snap("inspect")
	view._hide_inspector()
	view.present_snapshot(engine.view_for(0),false,"",-1)
	check(not view.input_locked and not view.presentation.running,"Connection-only status changes do not add animation waits")
	await settle()
	check(not view.my_turn,"Connection pause disables input after its snapshot")
	check(view._drop_action(point,{"type":"unit","uid":attacker.uid}).is_empty(),"Disconnected board cannot attack")
	print("BATTLE_PRESENTATION_RESULT platform=%s checks=%d failures=%d" % [OS.get_name(),checks,failures])
	view.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
