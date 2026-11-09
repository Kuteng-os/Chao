extends Node
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	source.keywords = [{"id":"core.mobilize","version":1,"params":{}},{"id":"core.fury","version":1,"params":{}}]
	var deck: Array = []
	for i in 10:
		source.name = "词条测试"+str(i)
		var compiled := CardRuntime.compile_card(source,CardRuntime.builtin_keywords())
		check(compiled.ok,"UI fixture compiles")
		for copy in 4: deck.append(compiled)
	var engine := BattleEngine.new()
	check(engine.setup(deck,deck,56).is_empty(),"Keyword UI match setup")
	engine.state.active_player = 0
	var unit: Dictionary = engine._new_unit(0,deck[0])
	unit["pinned_until"] = int(engine.state.turn)+2
	engine.state.players[1].hand[0]["revealed"] = true
	var view: Control = load("res://scripts/ui/battle_view.gd").new()
	view.state = engine.view_for(0)
	view.connected = true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	var shown: Control = view.visual_faces["u:%d"%unit.uid]
	var badges: Array = shown.field_effects
	for id in ["mobilize","fury","pin"]: check(badges.any(func(b): return b.id==id),"State badge visible: "+id)
	check(not shown.can_act,"Pinned card has no ready highlight")
	var known: Control
	for key in view.visual_faces:
		if key.begins_with("intel:"): known = view.visual_faces[key]
	check(known != null,"Known enemy hand has an inspectable face")
	check(view.state.players[1].hand.is_empty(),"Enemy hidden hand remains absent in UI state")
	if known != null:
		check(known.size==Vector2(108,156),"Intel face keeps hand-back size without covering HQ")
		view._face_pressed(known)
		await get_tree().create_timer(0.15).timeout
		check(view.inspector != null,"Touch/click opens Intel inspector")
		check(view.selected_hand.is_empty() and view.selected_unit < 0,"Inspecting Intel selects no playable card or target")
	view._hide_inspector()
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://keywords.png")
	print("KEYWORD UI: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
