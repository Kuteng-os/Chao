extends Node
const Audio=preload("res://scripts/ui/frontline_audio.gd")
var failures:=0
var checks:=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
func _ready() -> void: call_deferred("run")
func run() -> void:
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("FIELD_QA_FIXTURE")))
	CardArtCache.origin="http://127.0.0.1:7505"
	CardArtCache.directory="user://qa-field-media-art"
	var audio:=Audio.new()
	audio.config_path="user://qa-field-media.cfg"
	add_child(audio)
	audio.set_scene("battle")
	var cards:=[]
	var unit:Dictionary=fixture.unit
	for i in 10:
		var spec:=unit.duplicate(true)
		spec.name="测试步兵"+str(i)
		for n in 4: cards.append(CardRuntime.compile_card(spec,[]))
	var engine:=BattleEngine.new()
	check(engine.setup(cards,cards,54).is_empty(),"setup")
	engine.state.active_player=0
	engine.state.players[0].credits=12
	var field:Dictionary=CardRuntime.compile_card(fixture.field,[])
	check(field.ok,"uploaded field compiles in client")
	engine.state.players[0].hand.append({"instance_id":"field-ui","card":field})
	engine._new_unit(0,cards[0])
	engine._new_unit(1,cards[4])
	var stream:=await CardSoundCache.fetch(fixture.field.media.sounds.play,get_tree())
	check(stream!=null and stream.get_length()>0,"uploaded sound downloads verifies and decodes")
	var view:=preload("res://scripts/ui/battle_view.gd").new()
	view.me=0
	view.state=engine.view_for(0)
	view.connected=true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	check(engine.apply_action(0,{"type":"play","hand_id":"field-ui"}).is_empty(),"field drag command accepted")
	view.present_snapshot(engine.view_for(0),true,"",-1)
	var deadline:=Time.get_ticks_msec()+15000
	while (view.input_locked or view.backdrop.field_background==null or CardSoundCache.cached(fixture.field.media.music)==null) and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(view.backdrop.background_id==fixture.field.media.background and view.backdrop.field_background!=null,"uploaded background displayed")
	check(audio.music_players[audio._music_slot].stream==CardSoundCache.cached(fixture.field.media.music),"uploaded field music selected")
	await view._inspect_field(field)
	await get_tree().create_timer(0.3).timeout
	check(is_instance_valid(view.inspector) and view.inspector.spec.kind=="field","field badge opens readable triangle card")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("FIELD_QA_SCREENSHOT"))
	view._hide_inspector()
	engine.state.players[0].credits=12
	var blank:Dictionary=fixture.field.duplicate(true)
	blank.erase("media")
	blank.name="无媒体场地"
	engine.state.players[0].hand.append({"instance_id":"blank-field","card":CardRuntime.compile_card(blank,[])})
	check(engine.apply_action(0,{"type":"play","hand_id":"blank-field"}).is_empty(),"replacement accepted")
	view.present_snapshot(engine.view_for(0),true,"",-1)
	await get_tree().create_timer(1.5).timeout
	check(view.backdrop.background_id.is_empty() and view.backdrop.field_background==null,"replacement resets background")
	check(audio.music_players[audio._music_slot].stream==audio.tracks.battle,"replacement resets music")
	view.queue_free()
	audio.queue_free()
	await get_tree().create_timer(0.2).timeout
	print("FIELD MEDIA UI: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
