extends "res://tests/test_ui.gd"

func frames(count := 4) -> void:
	for i in count: await process_frame

func _run() -> void:
	root.size = Vector2i(1440, 900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime"))
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.store.settings.backend_url = "http://127.0.0.1:1"
	app.store._ensure_context()
	await frames()
	var faction := "11111111-1111-4111-8111-111111111111"
	app.store._faction_catalogs[app.store._bound_server] = [{"faction_id":faction,"name":"滚动测试","role":"major","color":"#876440","icon_id":null}]
	app.store._activate_factions()
	app.store.main_faction_id = faction
	var base: Dictionary = CardRuntime.parse_json(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json")).value
	base.keywords = []
	base["faction_id"] = faction
	base.abilities = []
	base.cost = 3
	for i in 32:
		var spec := base.duplicate(true)
		spec.name = "滚动卡%02d" % i
		var draft: Dictionary = await app.store.create_draft(spec)
		check(draft.ok, "scroll card fixture validates: " + str(draft.get("error", "")))
		if not draft.ok: quit(1); return
		await app.store.confirm_draft(draft.draft)
	check(app.store.new_local_deck("滚动测试牌组", "", "wrath").ok, "Explicit deck fixture before dropping cards")
	app.library_filter = "滚动卡"
	app.library_faction = faction
	app.library_cost = 3
	app._navigate("library")
	await frames(8)
	app.library_scroll.scroll_vertical = 640
	await frames()
	var before: int = app.library_scroll.scroll_vertical
	check(before > 100, "fixture actually scrolled below first row")
	var id: String = app.store.cards[-1].card_id
	var shelf_node: ScrollContainer = app.library_scroll
	var grid_node: GridContainer = app.library_grid
	var face_node: Node = app.library_grid.get_child(0)
	app.deck_drop.card_dropped.emit(id)
	check(app.library_scroll == shelf_node and app.library_grid == grid_node, "drop keeps live shelf and grid, not replacements")
	for frame in 8:
		check(app.library_scroll.scroll_vertical == before, "adding never flashes to top, frame %d" % frame)
		await process_frame
	check(app.library_grid.get_child(0) == face_node, "unchanged card face is reused")
	check(app.store.deck_count(id) == 1, "drop adds one card")
	check(abs(app.library_scroll.scroll_vertical - before) <= 1, "adding preserves catalog scroll")
	check(app.library_filter == "滚动卡" and app.library_faction == faction and app.library_cost == 3, "all filters preserved")
	# Burst notifications must not overwrite saved position with the new control's zero.
	app.store.changed.emit()
	app.store.changed.emit()
	for frame in 8:
		check(app.library_scroll == shelf_node and app.library_scroll.scroll_vertical == before, "burst notifications never reset shelf on frame %d" % frame)
		await process_frame
	check(abs(app.library_scroll.scroll_vertical - before) <= 1, "rapid refresh preserves position")
	app.library_drop.card_dropped.emit(id)
	for frame in 8:
		check(app.library_scroll.scroll_vertical == before, "removing never flashes on frame %d" % frame)
		await process_frame
	check(app.store.deck_count(id) == 0 and abs(app.library_scroll.scroll_vertical - before) <= 1, "removing preserves catalog position")
	for i in 24: check(app.store.add_to_deck(app.store.cards[i].card_id).is_empty(), "deck scroll fixture adds unique card")
	await frames(8)
	app.deck_scroll.scroll_vertical = 300
	await frames()
	var side_before: int = app.deck_scroll.scroll_vertical
	check(side_before > 0, "deck list also scrolls: %d cards, range %s, page %s" % [app.store.deck_ids.size(), app.deck_scroll.get_v_scroll_bar().max_value, app.deck_scroll.get_v_scroll_bar().page])
	app.deck_drop.card_dropped.emit(id)
	var side_node: ScrollContainer = app.deck_scroll
	for frame in 8:
		check(app.deck_scroll == side_node and abs(app.deck_scroll.scroll_vertical-side_before)<=1, "deck list never flashes on frame %d" % frame)
		await process_frame
	check(abs(app.deck_scroll.scroll_vertical - side_before) <= 1, "deck column preserves independent scroll")
	app.library_filter = "滚动卡00"
	app._populate_library()
	await frames(8)
	check(app.library_scroll.scroll_vertical == 0, "smaller filtered results clamp safely")
	print("LIBRARY SCROLL: %d checks, %d failures" % [checks, failures])
	app.queue_free()
	await frames()
	quit(1 if failures else 0)
