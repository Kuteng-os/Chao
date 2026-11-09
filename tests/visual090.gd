extends Node
var view: Control

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	get_viewport().warp_mouse(Vector2(4,4))
	var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/visual090_assets/catalog.json"))
	FactionCatalog.entries=FactionCatalog.parse(JSON.parse_string(FileAccess.get_file_as_string("res://tests/visual090_assets/factions.json")))
	for entry in FactionCatalog.entries.values():
		if entry.get("icon_id") is String:CardArtCache.textures[entry.icon_id]=load("res://tests/visual090_assets/"+entry.icon_id+".png")
	var theme:=Theme.new()
	var font:=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei UI"])
	font.multichannel_signed_distance_field=true;font.msdf_size=96
	theme.default_font=font;theme.default_font_size=18
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	source.keywords=[];source.abilities=[];source.cost=2;source.operation_cost=1;source.attack=3;source.health=4
	var deck: Array=[]
	for i in 10:
		var definition:=source.duplicate(true);definition.name=["都市巡逻队","灰色黎明","无声档案","边界哨兵","夜行者"][i%5]+str(i)
		definition["sin"]=["wrath","gloom","pride","envy",null][i%5]
		definition.name=fixtures[i].name
		definition["display_text"]=fixtures[i].text
		definition.unit_class=fixtures[i].kind
		definition["faction_id"]=fixtures[i].faction_id
		var compiled:=CardRuntime.compile_card(definition,[])
		assert(compiled.ok,JSON.stringify(compiled))
		compiled["art_id"]=fixtures[i].art_id
		CardArtCache.textures[fixtures[i].art_id]=load("res://tests/visual090_assets/"+fixtures[i].art_id+".png")
		for copy in 4:deck.append(compiled)
	var engine:=BattleEngine.new();assert(engine.setup(deck,deck,56).is_empty())
	engine.state.players[0]["main_sin"]="wrath"
	engine.state.players[1]["main_sin"]="pride"
	engine.state.active_player=0;engine.state.players[0].credits=8
	engine.state.players[0].max_credits=8;engine.state.players[1].max_credits=7
	for i in 5:
		var unit:Dictionary=engine._new_unit(0 if i<3 else 1,deck[i*4]);unit.born_turn=-1
		unit.row="front" if i==0 else "support"
	view=load("res://scripts/ui/battle_view.gd").new();view.theme=theme
	view.state=engine.view_for(0);view.connected=true;view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(view)
	view.backdrop.set_scene("rooftop")
	await get_tree().create_timer(3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../../preview090-battle.png")
	print("STAGE_CARDS ",view.backdrop.cards.size())
	var game_hash:=CardRuntime.canonical(engine.state).sha256_text()
	for item in view.backdrop.cards.values():
		var quad:MeshInstance3D=item.quad
		var pixel:Vector2=view.backdrop.camera.unproject_position(quad.global_position)*view.backdrop.size/Vector2(view.backdrop.viewport.size)
		var expected:Vector2=item.source.get_global_transform()*(item.source.size*0.5)
		assert(pixel.distance_to(expected)<1.0,"3D card and input must align")
		assert(item.paint.pivot_offset==Vector2.ZERO,"Card render capture is not cropped")
	assert(view.backdrop.cards.size()>=18)
	view.backdrop.set_scene("atelier")
	assert(game_hash==CardRuntime.canonical(engine.state).sha256_text(),"Scenes never mutate game rules")
	await get_tree().create_timer(1).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../../preview090-atelier.png")
	# Compare native UI rasterization against the projected card surface.
	view.backdrop.set_process(false)
	for item in view.backdrop.cards.values():
		item.quad.visible=false;item.solid.visible=false
		item.source.self_modulate.a=1.0
		if item.source is CardFace and is_instance_valid(item.source.watermark):item.source.watermark.self_modulate.a=1.0
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../../preview090-native-comparison.png")
	for item in view.backdrop.cards.values():
		item.source.self_modulate.a=0.0
	view.backdrop.set_process(true)
	for window_size in [Vector2i(1280,720),Vector2i(2560,1440)]:
		get_window().size=window_size
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		_check_render_density()
		get_viewport().get_texture().get_image().save_png("res://../../preview090-battle-%d.png"%window_size.x)
	BattleSceneCatalog.quality="high";view.backdrop.set_scene("rooftop")
	await get_tree().create_timer(0.5).timeout
	assert(view.backdrop.viewport.msaa_3d==Viewport.MSAA_8X)
	_check_render_density()
	BattleSceneCatalog.quality="balanced";view.backdrop.set_scene("atelier")
	get_window().size=Vector2i(1440,900)
	await get_tree().create_timer(0.5).timeout
	view._inspect(view.visual_faces["u:1"])
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../../preview090-card.png")
	print("PROJECTION_AND_SCENE_CHECKS passed")
	view.queue_free()
	await get_tree().process_frame
	view=null
	SinCatalog.icons.clear()
	CardArtCache.textures.clear()
	_finish.call_deferred()

func _finish() -> void:
	# Allow GPU objects to retire after the scenario's local references are gone.
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()

func _check_render_density() -> void:
	var stage:Control=view.backdrop
	var screen:Transform2D=get_viewport().get_screen_transform()*stage.get_global_transform_with_canvas()
	var physical:Vector2=stage.size*Vector2(screen.x.length(),screen.y.length())
	assert(stage.viewport.size.x>=physical.x and stage.viewport.size.y>=physical.y,"Do not upscale a logical-resolution world")
	for item in stage.cards.values():
		var projected:Vector2=stage.camera.unproject_position(item.quad.global_position)*stage.size/Vector2(stage.viewport.size)
		var expected:Vector2=item.source.get_global_transform()*(item.source.size*0.5)
		assert(projected.distance_to(expected)<1.0,"Resizing must preserve card/input alignment")
	print("RENDER_DENSITY window=",get_window().size," logical=",stage.size," framebuffer=",stage.viewport.size)
