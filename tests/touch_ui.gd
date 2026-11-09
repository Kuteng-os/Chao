extends Node

var failures := 0
var checks := 0
var clicked := []
var actions := []
var view: Control

func _ready() -> void:
	if OS.get_name() == "Android":
		preload("res://scripts/ui/screen_layout.gd").configure(get_window(), true)
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	get_window().size=Vector2i(1440,900)
	await get_tree().process_frame
	var deck := []
	for i in 10:
		var spec := {"schema_version":"1.0.0","ruleset_version":"frontline-1","name":"触摸测试 %d" % i,"flavor_text":"","kind":"unit","unit_class":"infantry","cost":1,"operation_cost":0,"attack":3,"health":3,"keywords":[],"play_target":null,"abilities":[],"tokens":[],"appearance":{"emblem":"infantry"}}
		var compiled := CardRuntime.compile_card(spec, [])
		check(compiled.ok, "Compile touch fixture")
		for copy in 4: deck.append(compiled)
	var engine := BattleEngine.new()
	check(engine.setup(deck, deck, 123).is_empty(), "Set up touch battle")
	engine.state.active_player = 0
	engine.state.players[0].credits = 12
	view = load("res://scripts/ui/battle_view.gd").new()
	view.state = engine.view_for(0)
	view.connected = true
	view.touch_mode = true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	view.hand_clicked.connect(func(card): clicked.append(card.instance_id))
	view.action_requested.connect(func(action): actions.append(action))
	await get_tree().process_frame
	var hands: Array = view.board.get_children().filter(func(n): return n is CardFace and n.hand_mode)
	check(not hands.is_empty(), "Hand cards rendered")
	var face: CardFace = hands.back()
	var rest := face.position
	var tilt := face.rotation
	var pickup: Vector2 = face.get_global_transform() * Vector2(95, 55)
	await mouse_move(pickup)
	check(face.position == rest and face.scale == Vector2.ONE, "Touch hover keeps hand geometry")
	for tap in 3:
		await mouse_button(pickup, true)
		await mouse_button(pickup, false)
	check(clicked.is_empty(), "Touch taps inspect without selecting or playing")
	check(face.position == rest and face.rotation == tilt and face.scale == Vector2.ONE and not face.extended_hover, "Repeated taps never lift or resize the hand")
	await get_tree().create_timer(0.35).timeout
	check(is_instance_valid(view.inspector), "Touch opens a separate card inspector")
	if is_instance_valid(view.inspector):
		var rect: Rect2 = view.inspector._print_rect()
		check(is_equal_approx(rect.size.x / rect.size.y, 252.0 / 354.0), "Inspector preserves printed proportions")
	view._hide_inspector()
	await get_tree().process_frame
	await mouse_button(pickup, true)
	await mouse_move(pickup + Vector2(0, -35), MOUSE_BUTTON_MASK_LEFT)
	var destination: Vector2 = view.board.get_global_transform() * Vector2(500, 630)
	await mouse_move(destination, MOUSE_BUTTON_MASK_LEFT)
	await mouse_button(destination, false)
	check(actions.size() == 1 and actions[0].get("type") == "play", "Touch-emulated native drag emits one deploy action")
	check(clicked.is_empty(), "Dragging does not also click the card")
	var stretched := CardFace.new()
	stretched.spec = face.spec
	stretched.custom_minimum_size = Vector2(126,177)
	add_child(stretched)
	check(stretched.custom_minimum_size == Vector2(126,177), "Ready preserves drag preview dimensions")
	stretched.size = Vector2(226,600)
	var printed := stretched._print_rect()
	check(is_equal_approx(printed.size.x / printed.size.y,252.0/354.0), "Tall mobile details cannot stretch the card")
	stretched.queue_free()
	# A desktop hand already raised by a real mouse must settle before touch.
	await get_tree().create_timer(0.22).timeout
	view.touch_mode = false
	face.mouse_entered.emit()
	# Hover uses a 120 ms tween; inspect its settled geometry, not the start frame.
	await get_tree().create_timer(0.16).timeout
	check(face.extended_hover and face.scale.x > 1.0, "Desktop hover still works")
	var touch := InputEventScreenTouch.new()
	touch.position = pickup
	touch.pressed = true
	view._input(touch)
	check(view.touch_mode and face.position == rest and face.scale == Vector2.ONE, "Switching from desktop mouse to touch resets stale hover")
	view.queue_free()
	await get_tree().process_frame
	var enemy: Dictionary = engine._new_unit(1, deck[0])
	engine._new_unit(0, deck[4])
	enemy.stack_layers = [{"stack":"heavy_armor","amount":3,"mode":"add","expires_turn":-1}]
	engine._recompute(enemy)
	check(engine._combat_damage(enemy, enemy, "attack") == 0, "Armor clamps combat damage on this platform")
	engine.state.active_player = 1
	engine.state["pending_choice"] = {"choice_id":"10-0", "owner":0, "source_name":"最后一击", "source_uid":999, "trigger":"on_death", "targets":[enemy.uid]}
	view = load("res://scripts/ui/battle_view.gd").new()
	view.state = engine.view_for(0)
	view.connected = true
	view.touch_mode = true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	view.action_requested.connect(func(action): actions.append(action))
	await get_tree().process_frame
	check(view.choosing and not view.my_turn, "Nonactive controller can select death target")
	var candidates: Array = view.board.get_children().filter(func(n): return n is CardFace and n.compact and n.is_target)
	check(candidates.size() == 1 and not candidates[0].can_act, "Highlight only legal death targets, disable ordinary actions")
	check(candidates[0].current_armor == 3, "Numeric armor rendered on compact field unit")
	var point: Vector2 = candidates[0].get_global_transform() * Vector2(65,80)
	await mouse_button(point,true)
	await mouse_button(point,false)
	check(actions.size() == 2 and actions.back() == {"type":"choose_target", "choice_id":"10-0", "target_uid":enemy.uid}, "Phone tap sends exactly one death choice during opponent turn")
	check("阵亡" in view.toast_label.text, "Show concise death selection prompt")
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://touch-regression.png")
	var search_game := BattleEngine.new()
	check(search_game.setup(deck,deck,42).is_empty(), "Set up named summon on this platform")
	var owner: int = search_game.state.active_player
	var jade: Dictionary = deck[0].source.duplicate(true)
	jade.name = "玉石"
	jade.keywords = [{"id":"standard.heavy_armor","version":1,"params":{"x":2}}]
	var frozen := CardRuntime.compile_card(jade,CardRuntime.builtin_keywords())
	check(frozen.ok,"Compile searched armored card on this platform")
	search_game.state.players[owner].deck = [frozen]
	var caller: Dictionary = deck[0].source.duplicate(true)
	caller.abilities = [{"trigger":"on_play","effects":[{"op":"summon_from_deck","card_name":"玉石","amount":1}]}]
	var compiled := CardRuntime.compile_card(caller,[])
	check(compiled.ok,"Compile named summon on this platform")
	search_game.state.players[owner].hand = [{"instance_id":"qa-summon","card":compiled}]
	search_game.state.players[owner].credits = 12
	check(search_game.apply_action(owner,{"type":"play","hand_id":"qa-summon"}).is_empty(),"Resolve named summon on this platform")
	check(search_game.state.units.size() == 2 and search_game.state.players[owner].deck.is_empty(),"Summon moves actual deck card exactly once")
	check(search_game.state.units[1].card.definition.name == "玉石" and search_game.state.units[1].stacks.heavy_armor == 2,"Summoned name and armor survive on this platform")
	for kind in ["unit","order","counter"]:
		var child := {"token_id":"child","name":"衍生"+kind,"kind":kind,"cost":0,"operation_cost":0,"unit_class":"infantry" if kind == "unit" else null,"attack":1 if kind == "unit" else 0,"health":3 if kind == "unit" else 0,"keywords":[],"abilities":[]}
		if kind == "counter": child["counter_trigger"] = "enemy_order_played"
		child.abilities = [{"trigger":"on_reveal" if kind == "counter" else "on_play","effects":[{"op":"heal","target":"own_hq","amount":1}]}]
		var maker: Dictionary = deck[0].source.duplicate(true)
		maker.tokens = [child]
		maker.abilities = [{"trigger":"on_play","effects":[{"op":"create_card","token_id":"child","player":"owner","amount":1}]}]
		var frozen_maker := CardRuntime.compile_card(maker,[])
		check(frozen_maker.ok,"Compile generated " + kind)
		var generated_game := BattleEngine.new()
		generated_game.setup(deck,deck,42)
		owner = generated_game.state.active_player
		generated_game.state.players[owner].credits = 12
		generated_game.state.players[owner].hand = [{"instance_id":"maker","card":frozen_maker}]
		check(generated_game.apply_action(owner,{"type":"play","hand_id":"maker"}).is_empty(),"Create " + kind + " in hand")
		var hand: Array = generated_game.state.players[owner].hand
		check(hand.size() == 1 and hand[0].card.definition.kind == kind,"Correct generated hand kind")
		check(generated_game.apply_action(owner,{"type":"play","hand_id":hand[0].instance_id}).is_empty(),"Play generated " + kind)
		check(generated_game.state.players[owner].hand.is_empty(),"Generated card removed exactly once")
	print("TOUCH_UI_RESULT platform=%s checks=%d failures=%d" % [OS.get_name(),checks,failures])
	get_tree().quit(1 if failures else 0)

func mouse_move(point: Vector2, mask: int = 0) -> void:
	if OS.get_name() != "Android": get_viewport().warp_mouse(point)
	else: point = get_viewport().get_screen_transform() * point
	var event := InputEventMouseMotion.new()
	event.device = 0
	event.position = point
	event.global_position = point
	event.relative = Vector2(0,-35)
	event.button_mask = mask
	Input.parse_input_event(event) if DisplayServer.get_name() != "headless" else get_viewport().push_input(event,true)
	await get_tree().process_frame
	await get_tree().process_frame

func mouse_button(point: Vector2, pressed: bool) -> void:
	if OS.get_name() == "Android": point = get_viewport().get_screen_transform() * point
	var event := InputEventMouseButton.new()
	event.device = 0
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event) if DisplayServer.get_name() != "headless" else get_viewport().push_input(event,true)
	await get_tree().process_frame
