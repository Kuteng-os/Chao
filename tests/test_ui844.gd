extends "res://tests/test_engine.gd"
const View = preload("res://scripts/ui/battle_view.gd")
var view: Control
var game: RefCounted
func _initialize() -> void: run.call_deferred()
func run() -> void:
	await cardbacks()
	for mobile in [false,true]:
		await discard_click(mobile)
	print("UI844: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func discard_click(mobile: bool) -> void:
	root.size=Vector2i(1440,900)
	game=_game()
	var seat:=_rich(game)
	game.state.players[seat].hand=[]
	var fixture: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/inheritance841_cards.json"))
	var hatch: Dictionary=fixture.filter(func(r):return r.card_id=="06c0ce91-5cf3-4ff9-97ff-d2f1fe341371")[0]
	game._receive_card(seat,_compile(fixture[0].definition),"test")
	game._receive_card(seat,_compile(hatch.definition),"test")
	view=View.new();view.state=game.view_for(seat);view.me=seat;view.connected=true;view.size=Vector2(1440,900)
	root.add_child(view)
	await process_frame
	view.action_requested.connect(func(a):
		print("UI_ACTION ",a)
		var err: String=game.apply_action(seat,a)
		_check(err.is_empty(),"UI command accepted "+err)
		view.present_snapshot(game.view_for(seat),true,"",-1))
	view._emit_action({"type":"play","hand_id":game.state.players[seat].hand.back().instance_id})
	await create_timer(2.0).timeout
	_check(game.state.has("pending_choice"),"discard selection pending")
	_check(view.choice_overlay.card_scroll.visible,"discard choices visible")
	_check(not view.input_locked,"discard selection unlocked")
	var options: Array=view.choice_overlay.card_row.get_children()
	_check(not options.is_empty(),"discard cards built")
	if not options.is_empty():
		for child in options[0].get_children():
			if child is CardFace:
				var point: Vector2=child.get_global_transform_with_canvas()*(child.size*0.5)
				if mobile:
					# Matches Android touch-to-mouse emulation used by Button controls.
					Input.emulate_mouse_from_touch=true
					for down in [true,false]:
						var event:=InputEventScreenTouch.new();event.position=point;event.index=0;event.pressed=down
						Input.parse_input_event(event);await process_frame
				else:
					var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion)
					for down in [true,false]:
						var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
						root.push_input(event);await process_frame
				break
	await create_timer(2.0).timeout
	_check(not game.state.has("pending_choice"),"hatch choice resumes resolution")
	_check(not view.input_locked,"input unlocked after discard")
	view.queue_free()
	await process_frame

func cardbacks() -> void:
	var props=preload("res://scripts/ui/battle_props.gd")
	for sin in SinCatalog.IDS+[""]:
		var back=props.new();back.kind="back";back.sin_id=sin;back.faction_id="unrelated-faction"
		root.add_child(back)
		_check(back.back_color==SinCatalog.color_for({"sin":sin}),"card back uses selected sin color "+sin)
		_check(back.back_icon==SinCatalog.icon(sin),"card back uses selected sin icon "+sin)
		back.queue_free()
	await process_frame
