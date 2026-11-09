extends Node
var view:Control
var game:BattleEngine
var failures:=0
var checks:=0
var reports:Array=[]
var reference_colors:Dictionary={}

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)

func _ready()->void:_run.call_deferred()

func frames(n:int)->void:
	for i in n:await get_tree().process_frame
	await RenderingServer.frame_post_draw

func sample_face(face:Control, image:Image)->Color:
	var print_rect:Rect2=face._print_rect()
	var design:Vector2=CardFace.FIELD_SIZE if face.compact else CardFace.FULL_CARD_SIZE
	var art_center:Vector2=print_rect.position+face.printed_art_rect().get_center()*print_rect.size.x/design.x
	var point:Vector2=face.get_global_transform_with_canvas()*art_center
	point*=Vector2(image.get_size())/get_viewport().get_visible_rect().size
	return image.get_pixelv(Vector2i(point).clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE))

func observe(label:String, tracked:Array)->void:
	for frame in 24:
		await frames(1)
		# Inspect the rendered battlefield itself. The new draw reading layer
		# intentionally crosses these pixels; its shadow/back is not a black flash.
		var screenshot:Image=view.backdrop.viewport.get_texture().get_image()
		var values:Array=[]
		var deck:Control=view.board.get_node("DeckCounter")
		var back:Control=view.board.get_children().filter(func(n):return n.get_script()==preload("res://scripts/ui/battle_props.gd") and n.kind=="back")[-1]
		for key in ["deck","back"]:
			var node:Control=deck if key=="deck" else back
			var point:Vector2=node.get_global_transform_with_canvas()*(Vector2(28,35) if key=="deck" else Vector2(70,140))
			point*=Vector2(screenshot.get_size())/get_viewport().get_visible_rect().size
			var color:=screenshot.get_pixelv(Vector2i(point))
			if not reference_colors.has(key):reference_colors[key]=color
			check(Vector3(color.r,color.g,color.b).distance_to(Vector3(reference_colors[key].r,reference_colors[key].g,reference_colors[key].b))<0.08,"%s frame %d %s does not turn black"%[label,frame,key])
		for uid in tracked:
			var face:Control=view.visual_faces["u:%d"%uid]
			var color:=sample_face(face,screenshot)
			values.append(snappedf(color.get_luminance(),0.01))
			check(color.get_luminance()>0.7,"%s frame %d unit %d retains printed art (%s)"%[label,frame,uid,color])
		reports.append({"event":label,"frame":frame,"luminance":values})
		if frame<4:screenshot.save_png("res://../../.runtime/render0907-%s-%d.png"%[label,frame])
	while view.input_locked:await get_tree().process_frame

func _run()->void:
	get_viewport().warp_mouse(Vector2(4,4))
	Engine.max_fps=60
	var spec:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	spec.name="render";spec.cost=1;spec.operation_cost=0;spec.keywords=[];spec.abilities=[];spec.attack=2;spec.health=4
	var art:=Image.create(256,256,false,Image.FORMAT_RGBA8);art.fill(Color.WHITE)
	var art_id:="e".repeat(64);CardArtCache.textures[art_id]=ImageTexture.create_from_image(art)
	var deck:Array=[]
	for i in 10:
		var definition:=spec.duplicate(true);definition.name+=str(i)
		var card:=CardRuntime.compile_card(definition,[]);card.art_id=art_id
		for copy in 4:deck.append(card)
	game=BattleEngine.new();check(game.setup(deck,deck,56).is_empty(),"Setup")
	game.state.active_player=0;game.state.players[0].credits=10;game.state.players[0].max_credits=10
	game.state.players[0].main_sin="wrath";game.state.players[1].main_sin="pride"
	var moving:Dictionary=game._new_unit(0,deck[0]);moving.born_turn=-1
	var fixed:Dictionary=game._new_unit(1,deck[4])
	view=load("res://scripts/ui/battle_view.gd").new();view.theme=ChaoUI.make_theme(false)
	view.state=game.view_for(0);view.connected=true;view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(view)
	await frames(20)
	var persistent_deck:Control=view.board.get_node("DeckCounter")
	var fixed_capture:Dictionary=view.backdrop.cards[view.visual_faces["u:%d"%fixed.uid].get_instance_id()]
	var fixed_viewport_id:int=fixed_capture.viewport.get_instance_id()
	await observe("idle",[fixed.uid])
	check(game.apply_action(0,{"type":"move","uid":moving.uid}).is_empty(),"Legal move")
	view.present_snapshot(game.view_for(0),true,"",-1)
	await observe("move",[fixed.uid,moving.uid])
	check(view.board.get_node("DeckCounter")==persistent_deck,"Moving reuses the existing deck prop")
	check(fixed_capture.viewport.get_instance_id()==fixed_viewport_id,"Unchanged unit keeps its printed texture during movement")
	game._draw(0)
	game.state.state_seq+=1
	view.present_snapshot(game.view_for(0),true,"",-1)
	await observe("draw",[fixed.uid,moving.uid])
	check(view.board.get_node("DeckCounter")==persistent_deck,"Drawing reuses the existing deck prop")
	for rate in [30,144]:
		Engine.max_fps=rate
		var fresh:Dictionary=game._new_unit(0,deck[8]);fresh.born_turn=-1
		game.state.state_seq+=1;view.present_snapshot(game.view_for(0),true,"",-1)
		await observe("deploy-%d"%rate,[fixed.uid,moving.uid])
		check(sample_face(view.visual_faces["u:%d"%fresh.uid],view.backdrop.viewport.get_texture().get_image()).get_luminance()>0.7,"New unit has a complete printed face")
		check(game.apply_action(0,{"type":"move","uid":fresh.uid}).is_empty(),"Repeated move")
		view.present_snapshot(game.view_for(0),true,"",-1)
		await observe("move-%d"%rate,[fixed.uid,fresh.uid])
		game._draw(0);game._draw(0)
		game.state.state_seq+=1;view.present_snapshot(game.view_for(0),true,"",-1)
		await observe("draw-%d"%rate,[fixed.uid,fresh.uid])
	# Resize forces capture reallocation, while printing and hit geometry stay aligned.
	get_window().size=Vector2i(2560,1440)
	await frames(8)
	check(sample_face(view.visual_faces["u:%d"%fixed.uid],get_viewport().get_texture().get_image()).get_luminance()>0.7,"High-density capture retains the field card")
	print("RENDER_FRAMES ",JSON.stringify(reports))
	print("RENDER_STABILITY0907: %d checks, %d failures"%[checks,failures])
	view.queue_free();await frames(2)
	get_tree().quit(1 if failures else 0)
