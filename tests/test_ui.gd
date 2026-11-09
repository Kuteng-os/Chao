extends SceneTree

var failures := 0
var checks := 0
var app: Control
var capture := false
var mouse_position := Vector2.ZERO

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	OS.set_environment("FRONTLINE_PROFILE_PATH", ProjectSettings.globalize_path("res://.runtime/ui-profile-%d-%d.json" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]))
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func _run() -> void:
	root.size = Vector2i(1440, 900)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	check(app.store.cards.is_empty(), "Fresh profile must have empty card library")
	await snap("home")
	app.store.online = false
	app.work_mode = 0
	app._navigate("workshop")
	app.manual.name = "界面测试单位"
	app.manual.kind = 0
	app.manual.cost = 1
	app.manual.attack = 2
	app.manual.health = 3
	await app._generate_card()
	check(not app.draft.is_empty(), "Manual card preview should succeed")
	check(app.store.cards.is_empty(), "Preview must not publish a card")
	await snap("workshop")
	app.creator_effects = [{"trigger":"on_play","op":"draw","amount":2},{"trigger":"on_play","op":"heal","amount":3}]
	await app._generate_card()
	check(not app.draft.is_empty() and app.draft.definition.abilities[0].effects.size() == 2, "Visual effect combination produces preview")
	await snap("workshop-effects")
	app.creator_effects.clear()
	await app._generate_card()
	app._choose_card_keywords()
	await snap("workshop-keywords")
	app._close_modal()
	var store: AppStore = app.store
	store._faction_catalogs[store._bound_server] = [{"faction_id":"11111111-1111-4111-8111-111111111111","name":"测试主阵营","role":"major","color":"#496359","icon_id":null}]
	store._activate_factions()
	store.main_faction_id = "11111111-1111-4111-8111-111111111111"
	var selected_definition: Dictionary = app.draft.definition.duplicate(true)
	selected_definition["faction_id"] = store.main_faction_id
	app.draft = (await store.create_draft(selected_definition)).draft
	await app._confirm_card()
	check(app.store.cards.size() == 1, "Confirm should publish exactly one card")
	var first: Dictionary = app.store.cards[0].definition
	for index in range(1, 10):
		var spec: Dictionary = first.duplicate(true)
		spec.name = "验收单位 %d" % index
		spec.unit_class = "tank" if index % 2 else "infantry"
		spec.appearance.emblem = spec.unit_class
		spec.cost = index % 3 + 1
		spec.attack = index % 3 + 1
		spec.health = index % 3 + 2
		var d: Dictionary = await app.store.create_draft(spec)
		check(d.ok, "User authored fixture must validate")
		await app.store.confirm_draft(d.draft)
	for record in app.store.cards:
		for copy in range(4):
			check(app.store.add_to_deck(record.card_id).is_empty(), "Add valid deck copy")
	check(not app.store.add_to_deck(app.store.cards[0].card_id).is_empty(), "Deck capacity must reject 41st card")
	app._navigate("library")
	await snap("library")
	app._navigate("keywords")
	await snap("keywords")
	app._navigate("network")
	await snap("lobby")
	app._navigate("settings")
	await snap("settings")
	app._navigate("network")
	app._start_solo()
	check(not app.match_controller.state.is_empty(), "Playable deck must start solo battle")
	app.match_controller.set_process(false)
	var engine: BattleEngine = app.match_controller._engine
	var deck: Dictionary = app.store.compile_deck()
	engine.setup(deck.deck, deck.deck, 1944)
	for step in 90:
		if engine.state.winner != -1 or (engine.state.turn >= 8 and engine.state.active_player == 0): break
		var active := int(engine.state.active_player)
		var error := engine.apply_action(active, engine.ai_action(active))
		check(error.is_empty(), "Simulated battle action must be legal")
	app.match_controller._refresh_views()
	await settle_battle()
	await process_frame
	check(not app.shell_header.visible, "Battle must use the whole screen without app navigation")
	check(app.battle_view != null, "Battle presentation must exist")
	check(app.battle_view.target_rects[-1].get_center().x == 706.0, "Enemy HQ must occupy the middle of its support row")
	check(app.battle_view.toast_label.text.is_empty(), "Battle must not show permanent tutorial or status prose")
	check(not app.battle_view._can_drop_data(Vector2(10, 10), {"type":"play", "hand_id":"missing"}), "Invalid drag must not generate an action")
	var view = app.battle_view
	var hand_faces: Array = []
	for node in view.board.get_children():
		if node is CardFace and node.hand_mode: hand_faces.append(node)
	check(hand_faces.size() == engine.state.players[0].hand.size(), "Every local hand card must be displayed")
	for face in hand_faces:
		check(face.spec.size() > 0, "Hand must contain only disclosed definitions")
	await snap("battle")
	for unit in app.match_controller.state.units:
		if unit.owner != 0: continue
		var targets: Array = engine.legal_targets(0, {"type":"attack", "uid":int(unit.uid)})
		if targets.is_empty(): continue
		app.selected_unit = int(unit.uid)
		app._render()
		await process_frame
		view = app.battle_view
		check(view.targets == targets, "Selected unit targets must match the rules engine")
		var point: Vector2 = view.target_rects[int(targets[0])].get_center() * view.board.scale + view.board.position
		check(view._drop_action(point, {"type":"unit", "uid":int(unit.uid)}).get("type") == "attack", "Drag to legal target must produce an attack")
		await snap("battle-selected")
		break
	root.size = Vector2i(1120, 720)
	await process_frame
	await process_frame
	check(view.board.size * view.board.scale + view.board.position <= view.size + Vector2.ONE, "Small window must contain the logical board")
	await snap("battle-small")
	root.size = Vector2i(1440, 900)
	# A new legal opening exercises drag-deploy independently of a full mid-game support row.
	engine.setup(deck.deck, deck.deck, 1944)
	for turn_index in 6:
		if engine.state.active_player == 0 and engine.state.players[0].credits >= 3: break
		engine.apply_action(int(engine.state.active_player), {"type":"end_turn"})
	app.match_controller._refresh_views()
	await settle_battle()
	await process_frame
	view = app.battle_view
	var playable := 0
	for hand_card in app.match_controller.state.players[0].hand:
		if view.rules.legal_targets(0, {"type":"play", "hand_id":str(hand_card.instance_id)}).is_empty(): continue
		var position: Vector2 = view.board.position + Vector2(706, 660) * view.board.scale
		var action: Dictionary = view._drop_action(position, {"type":"play", "hand_id":str(hand_card.instance_id)})
		check(action.get("type") == "play", "A legal hand drag to support should create a play action")
		playable += 1
	check(playable > 0, "Interaction fixture must exercise playable hand cards")
	var drag_face: CardFace
	for node in view.board.get_children():
		if node is CardFace and node.hand_mode and node.can_act: drag_face = node
	if drag_face != null and DisplayServer.get_name() != "headless":
		var resting: Vector2 = drag_face.position
		var pickup: Vector2 = drag_face.get_global_transform() * Vector2(100, 135)
		pickup.y = minf(pickup.y, 884.0)
		await move_mouse(pickup)
		check(drag_face.position.y < resting.y, "Hover must raise a hand card")
		await process_frame
		await process_frame
		check(drag_face.position.y < resting.y, "Lower hand hover must stay raised without oscillation")
		await create_timer(0.35).timeout
		await snap("battle-hover")
		pickup = drag_face.get_global_transform() * Vector2(100, 55)
		await move_mouse(pickup)
		await press_mouse(pickup, true)
		await move_mouse(pickup - Vector2(0, 25), MOUSE_BUTTON_MASK_LEFT)
		var destination: Vector2 = view.board.position + Vector2(707, 651) * view.board.scale
		await move_mouse(destination, MOUSE_BUTTON_MASK_LEFT)
		var units_before: int = engine.state.units.size()
		await press_mouse(destination, false)
		check(engine.state.units.size() == units_before + 1, "Actual mouse drag must deploy through the authoritative controller")
	# On the following friendly turn the same unit can be dragged into the frontline.
	engine.apply_action(0, {"type":"end_turn"})
	engine.apply_action(1, {"type":"end_turn"})
	app.match_controller._refresh_views()
	await settle_battle()
	await process_frame
	view = app.battle_view
	for unit in engine.state.units:
		if not engine.can_move(int(unit.uid)): continue
		if DisplayServer.get_name() != "headless":
			app.selected_unit = int(unit.uid)
			app._render()
			await process_frame
			view = app.battle_view
			var card_point: Vector2 = view.board.position + view.target_rects[int(unit.uid)].get_center() * view.board.scale
			await move_mouse(card_point)
			await press_mouse(card_point, true, MOUSE_BUTTON_RIGHT)
			await press_mouse(card_point, false, MOUSE_BUTTON_RIGHT)
			check(app.selected_unit == -1, "Right click on a unit must cancel selection")
			view = app.battle_view
		var point: Vector2 = view.board.position + Vector2(707, 465) * view.board.scale
		var action: Dictionary = view._drop_action(point, {"type":"unit", "uid":int(unit.uid)})
		check(action.get("type") == "move", "Drag a ready support unit into frontline must produce a move")
		app._act(action)
		check(engine.state.units[0].row == "front", "Frontline move must reach authoritative state")
		break
	app.match_controller.leave_game()
	app.queue_free()
	await process_frame
	print("UI_TEST_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func move_mouse(point: Vector2, mask: int = 0) -> void:
	root.warp_mouse(point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = mask
	event.relative = point - mouse_position
	mouse_position = point
	Input.parse_input_event(event)
	await process_frame

func press_mouse(point: Vector2, pressed: bool, button_index: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button_index
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func snap(name: String) -> void:
	await process_frame
	await process_frame
	if not capture:
		return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var folder := ProjectSettings.globalize_path("res://.runtime/screenshots")
	DirAccess.make_dir_recursive_absolute(folder)
	picture.save_png(folder.path_join(name + ".png"))

func settle_battle() -> void:
	var deadline := Time.get_ticks_msec()+6500
	while is_instance_valid(app.battle_view) and app.battle_view.input_locked and Time.get_ticks_msec()<deadline: await process_frame
