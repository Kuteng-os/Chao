extends "res://tests/draw_showcase0909.gd"
var samples: Array[float] = []
var phase := ""
var last_tick := 0
func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if last_tick > 0 and not phase.is_empty(): samples.append((now-last_tick)/1000.0)
	if last_tick > 0 and not phase.is_empty() and now-last_tick>16000: print("LONG_FRAME ",phase," ms=",(now-last_tick)/1000.0," timeline=",view.presentation.elapsed)
	last_tick=now

func report(label: String) -> void:
	samples.sort()
	if not samples.is_empty(): print(label," frames=",samples.size()," median=",samples[samples.size()/2]," p95=",samples[int(samples.size()*0.95)]," max=",samples[-1])
	samples.clear()

func _run() -> void:
	Engine.max_fps=144
	get_viewport().warp_mouse(Vector2(3,3))
	audio=Audio.new();audio.config_path="user://profile0912-audio.cfg";add_child(audio);audio.preferences.animations=true;audio.preferences.muted=true
	var records: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/visual090_assets/records.json"))
	for i in 10:
		var record:Dictionary=records[i%records.size()]
		var spec:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"));spec.keywords=[];spec.abilities=[];spec.cost=0;spec.name=record.definition.name+str(i)
		if OS.get_environment("FRONTLINE_PERF_DENSE")=="1":spec["display_text"]=record.rules_text
		var card:=CardRuntime.compile_card(spec,[])
		if not card.ok:print(card);get_tree().quit(1);return
		card.art_id=record.art.id
		CardArtCache.textures[card.art_id]=load("res://tests/visual090_assets/"+card.art_id+".png")
		for copy in 4:deck.append(card)
	game=BattleEngine.new()
	var error:=game.setup(deck,deck,56)
	if not error.is_empty():print(error);get_tree().quit(1);return
	game.state.active_player=0;game.state.players[0].credits=12;game.state.players[0].max_credits=12
	if OS.get_environment("FRONTLINE_PERF_DENSE")=="1":
		for i in 4:game._draw(0)
	view=load("res://scripts/ui/battle_view.gd").new();view.theme=ChaoUI.make_theme(false)
	view.state=game.view_for(0);view.connected=true;view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(view)
	await get_tree().create_timer(1.0).timeout
	phase="idle";samples.clear();await get_tree().create_timer(0.8).timeout;report("IDLE")
	for round in 3:
		phase="draw";samples.clear()
		for i in 2:game._draw(0)
		game.state.state_seq+=1
		var stamp:=Time.get_ticks_usec()
		view.present_snapshot(game.view_for(0),true,"",-1)
		print("DRAW_SNAPSHOT_MS ",(Time.get_ticks_usec()-stamp)/1000.0)
		await get_tree().create_timer(2.5).timeout
		report("DRAW"+str(round))
		phase="remove";samples.clear()
		game.state.players[0].hand.pop_back();game.state.players[0].hand.pop_back();game.state.state_seq+=1
		stamp=Time.get_ticks_usec();view.present_snapshot(game.view_for(0),true,"",-1)
		print("REMOVE_SNAPSHOT_MS ",(Time.get_ticks_usec()-stamp)/1000.0)
		await get_tree().create_timer(0.5).timeout
		report("REMOVE"+str(round))
	phase="";view.queue_free();audio.queue_free();await frames();get_tree().quit()
