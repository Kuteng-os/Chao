extends Node
## Run: godot --headless --path . tests/inspector_expand_ui.tscn
## A quick hover shows the card and its keywords; resting on it adds the reasons its numbers changed.
var checks:=0
var failures:=0
var view: Control

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _details() -> String:
	if not is_instance_valid(view.inspector_panel): return ""
	for node in view.inspector_panel.find_children("*","RichTextLabel",true,false): return node.text
	return ""

func _run() -> void:
	get_viewport().warp_mouse(Vector2(4,4))
	var spec: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	spec.keywords=[{"id":"core.guard","version":2,"params":{}}];spec.abilities=[];spec.cost=1;spec.health=10
	var deck: Array=[]
	for i in 10:
		spec.name="检视单位"+str(i)
		var card:=CardRuntime.compile_card(spec,CardRuntime.builtin_keywords())
		for n in 4: deck.append(card)
	var game:=BattleEngine.new()
	check(game.setup(deck,deck,57).is_empty(),"battle fixture initializes")
	game.state.active_player=0
	var unit: Dictionary=game._new_unit(0,deck[0])
	var buff:Dictionary=deck[1].duplicate(true);buff.definition.name="战旗"
	game._reset_budget()
	game._effect({"op":"modify_stats","target":"chosen","attack_delta":2,"health_delta":0,"duration":"battle"},game._context(0,-1,buff,unit.uid))
	view=load("res://scripts/ui/battle_view.gd").new()
	view.state=game.view_for(0);view.connected=true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	view.present_snapshot(game.view_for(0),true,"",-1)
	await get_tree().process_frame
	var face: Control=view.visual_faces["u:%d"%unit.uid]
	view._inspect(face)
	await get_tree().create_timer(0.2).timeout
	var quick:=_details()
	check(not quick.is_empty(),"the inspector opens on hover")
	check(quick.contains("守护") and quick.contains("词条"),"the keyword glossary is shown right away")
	check(not quick.contains("数值变化"),"stat reasons wait for a longer hover")
	await get_tree().create_timer(0.8).timeout
	var rested:=_details()
	check(rested.contains("数值变化") and rested.contains("战旗"),"resting on the card explains the buff and its source: "+rested.substr(rested.find("数值变化")))
	view._inspect(face,true)
	await get_tree().create_timer(0.2).timeout
	check(_details().contains("数值变化"),"a pinned inspector shows everything at once")
	print("inspector expand checks: ",checks," failures: ",failures)
	get_tree().quit(1 if failures else 0)
