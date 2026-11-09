extends Node
## Run natively, or as the main scene in a signed QA patch on Android.
const Layout = preload("res://scripts/ui/screen_layout.gd")
const Prop = preload("res://scripts/ui/battle_props.gd")
var failures := 0
var checks := 0
var app: Control
var actions := []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	OS.set_environment("FRONTLINE_MOBILE_TEST", "1")
	OS.set_environment("FRONTLINE_PROFILE_PATH", "user://responsive-qa-%d.json" % Time.get_ticks_usec())
	_run.call_deferred()

func settle() -> void:
	for frame in 5: await get_tree().process_frame

func snap(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://responsive-" + label + ".png")

func _run() -> void:
	var safe := Layout.canvas_safe_rect(Vector2(1800,800), Transform2D(Vector2(1.5,0),Vector2(0,1.5),Vector2.ZERO), Rect2(120,0,2580,1170))
	check(safe.is_equal_approx(Rect2(80,0,1720,780)), "Pixel insets convert to logical canvas coordinates")
	safe = Layout.canvas_safe_rect(Vector2(1800,800), Transform2D(Vector2(1.5,0),Vector2(0,1.5),Vector2(30,40)), Rect2(30,40,2580,1200))
	check(safe.is_equal_approx(Rect2(0,0,1720,800)), "Window offsets and opposite-edge cutout are handled")
	check(Layout.canvas_safe_rect(Vector2(1800,800),Transform2D.IDENTITY,Rect2()).size == Vector2(1800,800), "Unavailable safe area falls back to entire canvas")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await settle()
	app.store.online = false
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	spec.keywords = []
	spec.cost = 1
	spec.operation_cost = 0
	var deck := []
	for i in 10:
		var definition := spec.duplicate(true)
		definition.name = "适配测试 %d" % i
		var compiled := CardRuntime.compile_card(definition,[])
		check(compiled.ok, "Responsive fixture compiles")
		for copy in 4: deck.append(compiled)
	var engine := BattleEngine.new()
	check(engine.setup(deck,deck,42).is_empty(), "Responsive battle starts")
	engine.state.active_player = 0
	engine.state.players[0].credits = 12
	for owner in [0,1]:
		for i in 2: engine._new_unit(owner,deck[i*4])
	for unit in engine.state.units: unit.born_turn = -1
	var sizes := [Vector2i(1280,800),Vector2i(1280,720),Vector2i(1404,648),Vector2i(1440,648),Vector2i(1422,630),Vector2i(1470,630),Vector2i(1280,960),Vector2i(1100,1000)]
	if OS.get_name() == "Android": sizes = [get_window().size]
	for resolution in sizes:
		if OS.get_name() != "Android": get_window().size = resolution
		await settle()
		var physical: Vector2 = get_window().size
		var logical: Vector2 = get_viewport().get_visible_rect().size
		check(absf(physical.x/physical.y-logical.x/logical.y) < 0.01, "Viewport fills physical aspect %s" % resolution)
		check(get_window().content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "Runtime expand works for older installed APKs")
		for page in ["home","library","network","profile","settings"]:
			app._navigate(page)
			await settle()
			check(app.size.is_equal_approx(logical), "Menu fills viewport: " + page)
			check(app.shell_header.get_global_rect().end.x <= logical.x+1, "Navigation fits: " + page)
			check(app.shell_bottom.get_global_rect().end.y <= logical.y+1, "Footer fits: " + page)
			if page == "library":
				var filters := app.content.find_child("LibraryFilters",true,false) as HBoxContainer
				check(filters!=null and filters.get_child_count()==5,"Exactly five filters in a single row")
				check(filters.get_global_rect().end.x<=logical.x+1,"Filters fit screen width")
				for control in filters.get_children():
					check(is_equal_approx(control.global_position.y,filters.global_position.y),"Filters never wrap into another row")
				await snap("library-%dx%d" % [resolution.x,resolution.y])
		app._modal("屏幕适配")
		await settle()
		check(app.modal_margin.get_global_rect().size.is_equal_approx(logical), "Modal margins fill viewport")
		app._close_modal()
		app.page = "battle"
		app.shell_header.hide()
		app.shell_line.hide()
		app.shell_bottom.hide()
		app.shell_box.add_theme_constant_override("separation",0)
		app._update_screen_margins()
		for child in app.content.get_children(): child.queue_free()
		await settle()
		var view = load("res://scripts/ui/battle_view.gd").new()
		view.state = engine.view_for(0)
		view.connected = true
		view.touch_mode = true
		view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		app.content.add_child(view)
		app.battle_view = view
		view.action_requested.connect(func(action): actions.append(action))
		await settle()
		check(view.size.is_equal_approx(logical), "Battle fills viewport")
		check(view.backdrop.size.is_equal_approx(logical), "Table art fills viewport without pillarboxes")
		var usable: Rect2 = Layout.safe_rect(view)
		check((view.board.size * view.board.scale).is_equal_approx(usable.size), "Board expands to entire safe area")
		check(view.board.position.is_equal_approx(usable.position), "Board starts at safe area")
		check(is_equal_approx(view.board.scale.x,view.board.scale.y), "Cards retain uniform scale")
		for node in view.board.get_children():
			if not node is Control or not node.has_meta("layout_rect"): continue
			if node is CardFace and node.hand_mode: continue
			if node is Prop and node.kind == "back": continue
			var bounds := Rect2(node.position,node.size)
			check(Rect2(Vector2.ZERO,view.board.size).grow(1).encloses(bounds), "Control inside safe area: " + str(node))
			if node.has_meta("target_uid"):
				check(view.target_rects[node.get_meta("target_uid")].is_equal_approx(bounds), "Hit region follows visible unit")
		var hands: Array = view.board.get_children().filter(func(n): return n is CardFace and n.hand_mode)
		check(not hands.is_empty(), "Hand remains visible")
		var face: CardFace = hands.back()
		var rest := face.position
		face.mouse_entered.emit()
		face.pressed.emit()
		await get_tree().create_timer(0.32).timeout
		check(face.position == rest and face.scale == Vector2.ONE, "Tap/hover does not resize mobile hand")
		check(is_instance_valid(view.inspector), "Card inspector opens")
		if is_instance_valid(view.inspector):
			check(Rect2(Vector2.ZERO,view.board.size).grow(1).encloses(Rect2(view.inspector.position,view.inspector.size)), "Inspector fits right edge")
		view._hide_inspector()
		var support: Rect2 = view._combat_rect(Rect2(250,558,910,186))
		var destination: Vector2 = view.board.position + (support.position + Vector2(8,80)) * view.board.scale
		var play: Dictionary = view._drop_action(destination,face.drag_payload)
		check(play.get("type") == "play", "Expanded support area accepts deploy")
		var front: Rect2 = view._combat_rect(Rect2(250,380,910,180))
		destination = view.board.position + (front.position + Vector2(8,80)) * view.board.scale
		var uid: int = engine.state.units[0].uid
		check(view._drop_action(destination,{"type":"unit","uid":uid}).get("type") == "move", "Expanded frontline accepts movement")
		await snap("battle-%dx%d" % [resolution.x,resolution.y])
		print("RESPONSIVE_SIZE physical=%s canvas=%s safe=%s" % [physical,logical,usable])
		if OS.get_name() == "Android":
			var to_screen: Transform2D = view.get_viewport().get_screen_transform() * view.get_global_transform_with_canvas()
			print("RESPONSIVE_INSETS native=%s transform=%s cutouts=%s" % [DisplayServer.get_display_safe_area(),to_screen,DisplayServer.get_display_cutouts()])
			check((to_screen * usable).is_equal_approx(Rect2(DisplayServer.get_display_safe_area())), "Safe canvas converts back to native pixels on either orientation")
		app.battle_view = null
		view.queue_free()
		await settle()
	print("RESPONSIVE_UI_RESULT platform=%s checks=%d failures=%d" % [OS.get_name(),checks,failures])
	get_tree().quit(1 if failures else 0)
