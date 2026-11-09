extends Node
const Audio = preload("res://scripts/ui/frontline_audio.gd")
var checks := 0
var failures := 0
var view: Control
var game: BattleEngine
var audio: Node
var sounds: Array = []
var deck: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func _ready() -> void: _run.call_deferred()

func frames(count := 2) -> void:
	for i in count: await get_tree().process_frame
	await RenderingServer.frame_post_draw

func at(time: float) -> void:
	view.presentation._process(maxf(0,time-view.presentation.elapsed))
	await frames()

func receive(count := 1, owner := 0) -> void:
	for i in count: game._draw(owner)
	game.state.state_seq += 1
	view.present_snapshot(game.view_for(view.me),true,"",-1)
	view.presentation.set_process(false)

func _run() -> void:
	Engine.max_fps = 60
	get_viewport().warp_mouse(Vector2(3,3))
	audio = Audio.new(); audio.config_path = "user://draw0909-test-audio.cfg"; add_child(audio)
	audio.preferences.animations = true; audio.preferences.muted = true
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	spec.name="晨光联络员"; spec.cost=1; spec.operation_cost=0; spec.attack=2; spec.health=3; spec.keywords=[]
	spec.abilities=[{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]
	spec["sin"]="wrath"
	var art := Image.create(64,64,false,Image.FORMAT_RGBA8); art.fill(Color.WHITE)
	var art_id := "f".repeat(64); CardArtCache.textures[art_id]=ImageTexture.create_from_image(art)
	for i in 10:
		var definition := spec.duplicate(true); definition.name+=str(i)
		var card := CardRuntime.compile_card(definition,[]); card.art_id=art_id
		check(card.ok,"Draw fixture compiles")
		if not card.ok: print(card); get_tree().quit(1); return
		for copy in 4: deck.append(card)
	game=BattleEngine.new(); check(game.setup(deck,deck,56).is_empty(),"Battle initializes")
	game.state.active_player=0; game.state.players[0].credits=10; game.state.players[0].max_credits=10
	game.state.players[0].main_sin="wrath"; game.state.players[1].main_sin="pride"
	game._new_unit(0,deck[0]); game._new_unit(1,deck[4])
	view=load("res://scripts/ui/battle_view.gd").new(); view.theme=ChaoUI.make_theme(false)
	view.state=game.view_for(0); view.connected=true; view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(view)
	await frames(12)
	check(view.presentation.draw_jobs.is_empty(),"Initial connection does not replay existing hand")
	var count: int=game.state.players[0].hand.size()
	receive()
	var authoritative := CardRuntime.canonical(game.state)
	check(view.presentation.draw_jobs.size()==1,"Own draw creates one automatic display")
	check(view.input_locked and not view.choice_overlay.visible,"Draw needs no selection or dimming overlay")
	var job: Dictionary=view.presentation.draw_jobs[0]
	var node: CardFace=job.node
	var display: Control=job.display
	check(display.front.spec==node.spec and display.front.artwork==node.artwork,"Display uses the actual private hand definition and cached artwork")
	check(display.back.sin_id=="wrath","Card back follows selected sin")
	check(node.get_meta("draw_hidden",false),"Destination stays hidden before arrival")
	check(job.from.x>view.layout_size.x*0.75 and job.from.y>view.layout_size.y*0.7,"Draw begins at own lower-right deck")
	check(view.presentation.duration>1.2 and view.presentation.duration<1.6,"One draw is brief but readable")
	await at(job.at+0.04)
	check(display.visible and display.back.visible and not display.front.visible,"Card first rises showing its back")
	check(not view.backdrop.cards[node.get_instance_id()].quad.visible,"No duplicated hand projection during display")
	await at(job.at+0.21)
	check(display.front.visible and not display.back.visible,"Flip exposes the correct face without mirroring text")
	check(display.scale.x>0,"Face never uses negative mirrored width")
	await at(job.at+0.43)
	check((display.position+display.pivot_offset).distance_to(job.center)<0.1,"Automatic reading position is centered")
	check(is_zero_approx(display.rotation) and display.scale.x>1,"Reading pose is upright and enlarged")
	check(display.mouse_filter==Control.MOUSE_FILTER_IGNORE and display.front.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Reading display never captures clicks or drags")
	var sample_point: Vector2=display.front.get_global_transform_with_canvas()*(display.front._print_rect().position+display.front.printed_art_rect().get_center()*display.front._print_rect().size.x/CardFace.FULL_CARD_SIZE.x)
	var pixel: Color=get_viewport().get_texture().get_image().get_pixelv(Vector2i(sample_point))
	check(pixel.get_luminance()>0.7,"Native render displays complete artwork, no black capture")
	var held: Transform2D=display.get_transform()
	await at(job.at+0.72)
	check(display.get_transform().is_equal_approx(held),"Reading pause is still, with no pulsing or flickering")
	await at(job.at+1.02)
	check(display.position.y>job.center.y-display.pivot_offset.y,"Card then descends towards the hand")
	await at(view.presentation.duration+0.01)
	check(not view.input_locked and view.presentation.draw_jobs.is_empty(),"Draw automatically completes and unlocks input")
	check(node.position.is_equal_approx(node.get_meta("rest_position")) and is_equal_approx(node.rotation,node.get_meta("rest_rotation")),"New card settles in its correct fan position")
	check(node.modulate.a==1 and not node.get_meta("draw_hidden",false) and view.backdrop.cards[node.get_instance_id()].quad.visible,"Arrival restores exactly one ready hand face")
	check(game.state.players[0].hand.size()==count+1 and CardRuntime.canonical(game.state)==authoritative,"Animation never changes hand count or authoritative state")
	view.present_snapshot(game.view_for(0),true,"",-1)
	check(not view.presentation.running and view.presentation.draw_jobs.is_empty(),"Duplicate network refresh cannot replay the draw")
	# Consecutive cards get distinct reading windows. Future faces stay private
	# and invisible until their turn, even while queued snapshots arrive.
	receive(3)
	var batch: Array=view.presentation.draw_jobs.duplicate()
	check(batch.size()==3,"Three received cards get three displays")
	check(view.presentation.duration<3.0,"Multiple draw animation has a bounded faster cadence")
	for i in batch.size():
		var current: Dictionary=batch[i]
		await at(current.at+0.42)
		check(current.display.front.visible and current.display.visible,"Each card has a legible front display")
		var centered:=0
		for other in batch:
			if is_instance_valid(other.display) and other.display.visible and (other.display.position+other.display.pivot_offset).distance_to(other.center)<0.1: centered+=1
		check(centered==1,"Only one card occupies the central reading position")
		for next_index in range(i+1,batch.size()): check(not batch[next_index].display.visible and batch[next_index].node.modulate.a==0,"Following cards wait hidden")
		if i==0:
			game._draw(0); game.state.state_seq+=1
			view.present_snapshot(game.view_for(0),true,"",-1)
			check(not view.queued_snapshot.is_empty(),"Incoming draw snapshot queues behind current display")
	await at(view.presentation.duration+0.01)
	check(view.presentation.draw_jobs.size()==1,"Queued snapshot displays only its newly received card")
	await at(view.presentation.duration+0.01)
	check(not view.input_locked and view.queued_snapshot.is_empty(),"Queued draws drain and release input")
	# Hidden opponent draws must never reach the public card reveal layer.
	receive(1,1)
	check(view.presentation.draw_jobs.is_empty(),"Opponent draw exposes no face")
	check(view.presentation.motions.any(func(m):return m.node.get_script()==preload("res://scripts/ui/battle_props.gd") and m.node.kind=="back" and m.fresh),"Opponent still receives a back-only incoming animation")
	check(view.presentation.reveals.is_empty(),"No opponent hand identity enters order display")
	await at(view.presentation.duration+0.01)
	# Capacity overflow creates no fake card. Disabling animation also skips
	# reading pauses, preserving the local preference.
	while game.state.players[0].hand.size()<10: game._draw(0)
	game.state.state_seq+=1; view.present_snapshot(game.view_for(0),true,"",-1); view.presentation.finish()
	receive()
	check(view.presentation.draw_jobs.is_empty() and game.state.players[0].hand.size()==10,"Burning a full-hand draw never invents an eleventh hand face")
	view.presentation.finish()
	game.state.players[0].hand.pop_back(); game.state.state_seq+=1; view.present_snapshot(game.view_for(0),true,"",-1); view.presentation.finish()
	audio.preferences.animations=false
	receive()
	check(view.presentation.draw_jobs.is_empty() and view.presentation.duration<=0.25,"Reduced motion inserts cards without center display")
	view.presentation.finish(); audio.preferences.animations=true
	# Resize/exit must not leave cards hidden or a presentation lock behind.
	game.state.players[0].hand.pop_back(); game.state.state_seq+=1; view.present_snapshot(game.view_for(0),true,"",-1); view.presentation.finish()
	receive(); node=view.presentation.draw_jobs[0].node
	get_window().size=Vector2i(1600,900); await frames(3)
	check(not view.input_locked and view.presentation.draw_jobs.is_empty() and not node.get_meta("draw_hidden",false),"Resize cancels cleanly and restores the real hand")
	# Visual review with existing local artwork, at desktop and phone ratios.
	var fixtures: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/visual090_assets/catalog.json"))
	for dimensions in [Vector2i(1600,900),Vector2i(1400,630)]:
		get_window().min_size=Vector2i(640,360); get_window().size=dimensions; await frames(3)
		game.state.players[0].hand.pop_back(); game.state.state_seq+=1; view.present_snapshot(game.view_for(0),true,"",-1); view.presentation.finish()
		var top: Dictionary=game.state.players[0].deck[-1]; top.art_id=fixtures[0].art_id
		CardArtCache.textures[top.art_id]=load("res://tests/visual090_assets/"+top.art_id+".png")
		receive(); job=view.presentation.draw_jobs[0]; await at(job.at+0.44)
		var bounds: Rect2=job.display.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,job.display.size)
		check(get_viewport().get_visible_rect().encloses(bounds),"Whole reading card fits the display aspect ratio")
		get_viewport().get_texture().get_image().save_png("res://../../.runtime/draw0909-%dx%d.png"%[dimensions.x,dimensions.y])
		view.presentation.finish()
	# Opening replacements are managed by the mulligan screen, not this layer.
	view.queue_free(); await frames()
	game=BattleEngine.new(); game.setup(deck,deck,56,[],true)
	view=load("res://scripts/ui/battle_view.gd").new(); view.theme=ChaoUI.make_theme(false)
	view.me=1; view.spectating=true; view.state=game.view_for(1); view.connected=true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(view); await frames(8)
	var opening_ids: Array=game.state.players[1].hand.slice(0,2).map(func(h):return h.instance_id)
	check(game.apply_action(1,{"type":"mulligan","hand_ids":opening_ids}).is_empty(),"Followed player replaces opening cards")
	view.present_snapshot(game.view_for(1),true,"",-1); view.presentation.set_process(false)
	check(view.presentation.draw_jobs.is_empty() and view.opening_overlay.visible,"Mulligan does not trigger a second reading animation")
	view.presentation.finish()
	check(game.apply_action(0,{"type":"mulligan","hand_ids":[]}).is_empty(),"Other player confirms opening")
	view.present_snapshot(game.view_for(1),true,"",-1); view.presentation.set_process(false)
	check(view.presentation.draw_jobs.is_empty(),"Opening confirmation does not redisplay the starting hand")
	view.presentation.finish()
	receive(1,0)
	check(view.presentation.draw_jobs.is_empty(),"Seat-one spectator cannot see the other player's draw")
	view.presentation.finish()
	game._stat("turn_start",1,{},1)
	receive(1,1)
	check(view.presentation.draw_jobs.size()==1,"Seat-one spectator sees only the followed player's drawn card")
	job=view.presentation.draw_jobs[0]
	var turn_caption: Array=view.presentation.jobs.filter(func(j):return j.kind=="caption")
	check(turn_caption.size()==1 and job.at>=turn_caption[0].at+0.38,"Draw waits for the turn announcement to finish")
	await at(job.at+0.44)
	check(job.node.get_meta("card").instance_id==game.state.players[1].hand[-1].instance_id and job.display.front.spec==job.node.spec,"Spectator's display is the authorized followed hand")
	view.presentation.finish()
	print("DRAW_SHOWCASE0909: %d checks, %d failures"%[checks,failures])
	view.queue_free(); audio.queue_free(); await frames()
	get_tree().quit(1 if failures else 0)
