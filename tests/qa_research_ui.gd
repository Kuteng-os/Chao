extends "res://tests/test_research.gd"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size=Vector2i(1440,900)
	var g:=_game();var seat:=_rich(g)
	var d:=_research_card();d.tokens=d.tokens.slice(0,4)
	d.abilities[0].effects=[{"op":"develop","source":"tokens","token_ids":["reward_a","reward_b","reward_c","reward_d"]}]
	_play(g,d)
	var battle:=preload("res://scripts/ui/battle_view.gd").new()
	battle.state=g.view_for(seat);battle.me=seat;battle.connected=true
	battle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(battle)
	await process_frame
	await process_frame
	_check(battle.choice_overlay.visible,"selection shade visible")
	_check(battle.choice_overlay.card_row.get_child_count()==3,"three card options rendered")
	var emitted:=[]
	battle.action_requested.connect(func(a):emitted.append(a))
	battle.choice_overlay.card_row.get_child(2).get_child(1).pressed.emit()
	_check(emitted.size()==1 and emitted[0].type=="choose_card" and emitted[0].option_index==2,"third visible button submits correct choice")
	await create_timer(0.2).timeout
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("FRONTLINE_QA_SCREEN"))
	battle.queue_free()
	await process_frame
	print("RESEARCH UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
