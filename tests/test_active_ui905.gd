extends "res://tests/test_engine.gd"
var sent: Array=[]
func _initialize() -> void: call_deferred("_run_ui")
func _run_ui() -> void:
	root.size=Vector2i(1440,900)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/repairs905.json"))
	var g:=_game();var me:=_rich(g);var uid:=_play(g,data.fixtures.dragon);_play(g,data.fixtures.jade)
	var view=load("res://scripts/ui/battle_view.gd").new()
	view.state=g.view_for(me);view.me=me;view.connected=true;view.size=Vector2(1440,900)
	root.add_child(view);view.action_requested.connect(func(a):sent.append(a))
	await process_frame
	for mobile in [false,true]:
		view.touch_mode=mobile
		await view._inspect(view.visual_faces["u:%d"%uid],true)
		var buttons:=_activation_buttons(view.inspector_panel)
		_check(buttons.size()==1 and not buttons[0].disabled,"active button available on desktop/mobile")
		buttons[0].pressed.emit()
		_check(sent.back()=={"type":"activate","uid":uid,"ability_index":0},"button emits exact authority command")
		_check(view.inspector==null,"activation closes detail panel")
	view.touch_mode=false
	view.state.unit_activations[str(uid)][0].error="本回合已发动"
	await view._inspect(view.visual_faces["u:%d"%uid],true)
	var exhausted:=_activation_buttons(view.inspector_panel)
	_check(exhausted.size()==1 and exhausted[0].disabled,"used skill disabled")
	view._hide_inspector();view.queue_free();await process_frame
	print("ACTIVE UI 905: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func _activation_buttons(node: Node) -> Array:
	var result: Array=[]
	if node is Button and (node.text.begins_with("发动能力") or node.text=="本回合已发动"):result.append(node)
	for child in node.get_children():result.append_array(_activation_buttons(child))
	return result
