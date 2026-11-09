extends "res://tests/draw_showcase0909.gd"

func _run() -> void:
	Engine.max_fps=60
	get_viewport().warp_mouse(Vector2(3,3))
	audio=Audio.new();audio.config_path="user://hand0912-audio.cfg";add_child(audio);audio.preferences.animations=true;audio.preferences.muted=true
	var spec:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	spec.keywords=[];spec.abilities=[];spec.cost=1
	for i in 10:
		var d:=spec.duplicate(true);d.name="巡逻员"+str(i)
		var card:=CardRuntime.compile_card(d,[])
		for copy in 4:deck.append(card)
	game=BattleEngine.new();game.setup(deck,deck,56);game.state.active_player=0;game.state.players[0].credits=10;game.state.players[0].max_credits=10
	view=load("res://scripts/ui/battle_view.gd").new();view.theme=ChaoUI.make_theme(false);view.state=game.view_for(0);view.connected=true;view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(view)
	await frames(10)
	var old:CardFace=view.visual_faces["h:"+str(game.state.players[0].hand[0].instance_id)]
	var start:=old.position
	# A single authoritative update both removes a card and draws two.
	game.state.players[0].hand.pop_back();receive(2)
	var first:Dictionary=view.presentation.draw_jobs[0]
	await at(0.15)
	check(old.position.distance_to(start)>1,"Surviving hand closes the departed card's gap immediately while new cards are being shown")
	await at(0.31)
	var remaining:int=game.state.players[0].hand.size()-2
	var closed:Dictionary=view.HandLayout.pose(0,remaining,view.layout_size)
	check(old.position.is_equal_approx(closed.position),"Fan first closes to the surviving count, without reserving hidden cards")
	await at(first.at+view.presentation.DRAW_LIFT+first.hold-0.065)
	check(old.position.is_equal_approx(closed.position),"Reading hold leaves the closed fan steady")
	await at(first.at+first.length+0.001)
	check(old.position.is_equal_approx(view.HandLayout.pose(0,remaining+1,view.layout_size).position),"First incoming card opens exactly one slot")
	view.presentation.finish()
	check(old.position.is_equal_approx(old.get_meta("rest_position")),"Combined removal and arrivals finish without a terminal jump")
	# Per-card text caching still reacts to author text, nested edits and costs.
	var before:=old._rules_text()
	old.spec._printed["display_text"]="闪击\n新增描述"
	check(old._rules_text()=="闪击\n新增描述" and old._rules_text()!=before,"Nested printed-description edits invalidate the cached text")
	old.subtitle="临时效果"
	check(old._rules_text()=="临时效果","Current subtitle invalidates text cache")
	old.subtitle=""
	check(old._rules_text()=="闪击\n新增描述","Removing subtitle restores the updated card text")
	var font:=old.get_theme_default_font()
	check(font is SystemFont and not font.multichannel_signed_distance_field and font.oversampling>=4,"Card glyphs retain high resolution without synchronous MSDF construction")
	check(old.Typography.card_font(ChaoUI.make_theme(false).default_font)==font,"UI rebuilds reuse the existing card font atlas")
	game.state.players[0].hand[0].card.definition.cost=5;game.state.state_seq+=1
	view.present_snapshot(game.view_for(0),true,"",-1);view.presentation.finish()
	check(old.spec.cost==5,"A new snapshot still refreshes a changed card's playable cost")
	await frames(3)
	var retired_ids:Array=[]
	for i in 2:
		var entry:Dictionary=game.state.players[0].hand.pop_back()
		var node:Control=view.visual_faces["h:"+str(entry.instance_id)]
		retired_ids.append(view.backdrop.cards[node.get_instance_id()].viewport.get_instance_id())
	game.state.state_seq+=1;view.present_snapshot(game.view_for(0),true,"",-1);view.presentation.finish();await frames(3)
	check(view.backdrop.capture_pool.size()>=2,"Discarded captures stay available instead of freeing GPU targets mid-animation")
	check(view.backdrop.capture_pool.all(func(item):return not item.quad.visible and not item.solid.visible),"Retired card surfaces cannot linger on the table")
	retired_ids=view.backdrop.capture_pool.map(func(item):return item.viewport.get_instance_id())
	var art:=Image.create(32,32,false,Image.FORMAT_RGBA8);art.fill(Color.GREEN)
	var id:="c".repeat(64);CardArtCache.textures[id]=ImageTexture.create_from_image(art)
	game._draw(0);game.state.players[0].hand[-1].card.art_id=id
	game.state.state_seq+=1;view.present_snapshot(game.view_for(0),true,"",-1);view.presentation.set_process(false);await frames(3)
	var arriving:CardFace=view.presentation.draw_jobs[0].node
	var capture:Dictionary=view.backdrop.cards[arriving.get_instance_id()]
	check(capture.viewport.get_instance_id() in retired_ids,"New arrival reuses a retired GPU buffer")
	check(not capture.quad.visible,"Reused capture remains hidden during the separate draw display")
	view.presentation.finish();await frames(3)
	var point:Vector2=arriving.printed_art_rect().get_center()*Vector2(capture.viewport.size)/CardFace.FULL_CARD_SIZE
	# Capture includes a rarity footer: use actual design-to-print scaling.
	point=arriving.printed_art_rect().get_center()*(arriving._print_rect().size.x/CardFace.FULL_CARD_SIZE.x)*(Vector2(capture.viewport.size)/arriving.size)
	var pixel:Color=capture.viewport.get_texture().get_image().get_pixelv(Vector2i(point))
	check(pixel.g>0.85 and pixel.r<0.1 and pixel.b<0.1,"Recycled buffer paints the new artwork, never the retired card")
	check(capture.paint.spec.name==arriving.spec.name and capture.paint.spec.cost==arriving.spec.cost,"Recycled buffer refreshes the new card's text and cost")
	check(view.backdrop.capture_pool.size()<=view.backdrop.CAPTURE_POOL_LIMIT,"Retained GPU buffers remain bounded")
	view.queue_free();audio.queue_free();await frames()
	print("HAND_SMOOTH0912: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
