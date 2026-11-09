extends "res://tests/test_engine.gd"
const View=preload("res://scripts/ui/battle_view.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/repairs862.json"))
	for dims in [Vector2i(1440,900),Vector2i(900,430)]:
		root.size=dims
		var g:=_game();var me:=_rich(g)
		g._new_unit(me,_compile(_base("玉石")))
		_play(g,data.fixtures.jade)
		var view:=View.new();view.state=g.view_for(me);view.me=me;view.connected=true;view.size=dims
		root.add_child(view);await process_frame;await process_frame
		_check(view.choice_overlay.visible and view.choice_overlay.finish_button.visible,"zero-choice finish visible "+str(dims))
		_check(view.choice_overlay.finish_button.get_global_rect().end.x<=dims.x,"finish fits viewport")
		view.action_requested.connect(func(a):
			_check(a.type=="choose_target" and a.target_uid==-1000,"finish sends selection completion")
			_check(g.apply_action(me,a).is_empty(),"finish accepted")
			view.present_snapshot(g.view_for(me),true,"",-1))
		view.choice_overlay.finish_button.pressed.emit();await process_frame
		_check(not g.state.has("pending_choice"),"zero choice ends with units intact")
		view.queue_free();await process_frame
	var wire:=preload("res://scripts/network/match_controller.gd").new()
	_check(not wire._normalize_action({"type":"choose_target","choice_id":"2-0","target_uid":-1000}).is_empty(),"multiplayer wire accepts finish")
	wire.free()
	print("CHOICES 862: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
