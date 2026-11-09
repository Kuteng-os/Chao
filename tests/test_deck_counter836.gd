extends "res://tests/test_engine.gd"

func _initialize() -> void:
	_run.call_deferred()

func _settle(view: Control) -> void:
	var deadline:=Time.get_ticks_msec()+6000
	while view.input_locked and Time.get_ticks_msec()<deadline: await process_frame
	_check(not view.input_locked,"queued presentation settles")

func _run() -> void:
	root.size=Vector2i(1440,900)
	var g:=_game();var seat:=_rich(g)
	var copy_card:=_base("阵亡复制测试")
	copy_card.abilities=[{"trigger":"on_death","effects":[{"op":"transfer_card","source":"self","destination":"deck","mode":"copy","selection":"random","amount":1}]}]
	var unit:Dictionary=g._new_unit(seat,_compile(copy_card))
	var view:Control=load("res://scripts/ui/battle_view.gd").new()
	view.me=seat;view.state=g.view_for(seat);view.connected=true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(view)
	await process_frame
	var count:int=g.state.players[seat].deck.size()
	_check(view.board.get_node("DeckCounter").value==count,"initial count uses actual private deck size")
	unit.destroyed=true;g._checkpoint();g._drain_deaths();g.state.state_seq+=1
	view.present_snapshot(g.view_for(seat),true,"",-1)
	_check(view.board.get_node("DeckCounter").value==count+1,"death-copy snapshot updates visible counter immediately")
	_check(view.board.get_node("DeckCounter").tooltip_text.contains(str(count+1)),"tooltip agrees with numeric counter")
	_check(g.state.log.any(func(line):return str(line).contains("加入牌库，剩余 %d 张" % (count+1))),"deck addition has its own count record")
	_check(not g.view_for(1-seat).presentation_events.any(func(e):return e.kind=="deck_insert"),"private inserted-card identity is not broadcast")
	# A follow-up draw may arrive while the death animation is still running.
	g._draw(seat);g.state.state_seq+=1
	view.present_snapshot(g.view_for(seat),true,"",-1)
	await _settle(view)
	_check(view.board.get_node("DeckCounter").value==count,"queued follow-up draw reduces count exactly once")
	_check(view.state.players[seat].deck_count==g.state.players[seat].deck.size(),"final snapshot and authoritative count agree")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.runtime/screenshots")
		root.get_texture().get_image().save_png("res://.runtime/screenshots/deck-counter836.png")
	print("DECK COUNTER836: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
