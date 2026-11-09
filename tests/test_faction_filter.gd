extends "res://tests/test_ui.gd"

func _run() -> void:
	root.size = Vector2i(1440, 900)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.store.settings.backend_url = "http://127.0.0.1:1"
	app.store._ensure_context()
	await process_frame
	var specs := [{"faction_id":"11111111-1111-4111-8111-111111111111","name":"晨曦","role":"major","color":"#ac8561","icon_id":null},{"faction_id":"22222222-2222-4222-8222-222222222222","name":"极夜","role":"major","color":"#6389aa","icon_id":null}]
	specs.append({"faction_id":"33333333-3333-4333-8333-333333333333","name":"尚无卡牌的阵营","role":"major","color":"#6389aa","icon_id":null})
	app.store._faction_catalogs[app.store._bound_server] = specs
	app.store._activate_factions()
	var c: Dictionary = CardRuntime.parse_json(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json")).value
	c.keywords = []
	for i in 2:
		c["faction_id"] = specs[i].faction_id
		c.name = "单位"+str(i)
		var draft: Dictionary = await app.store.create_draft(c)
		check(draft.ok,"Faction filter fixture")
		await app.store.confirm_draft(draft.draft)
	for phone in [false,true]:
		app.mobile = phone
		root.size = Vector2i(1280,800) if phone else Vector2i(1440,900)
		app._navigate("library")
		await process_frame
		var picker := app.content.find_child("LibraryFactionFilter",true,false) as OptionButton
		if picker == null:
			check(false, "Faction filter must be a dropdown")
			quit(1)
			return
		check(picker != null and picker.item_count == specs.size()+1,"Dropdown includes all registered factions, including those without cards")
		check(not is_instance_valid(app.overlay),"Faction selection needs no search dialog")
		if capture:
			root.gui_embed_subwindows = true
			picker.show_popup()
			await snap("faction-dropdown-mobile" if phone else "faction-dropdown-desktop")
			picker.get_popup().hide()
		var selected := -1
		for index in picker.item_count:
			if picker.get_item_metadata(index) == specs[1].faction_id: selected = index
		picker.select(selected)
		picker.item_selected.emit(selected)
		await process_frame
		check(app.library_faction==specs[1].faction_id and app.library_count.text=="1 张卡牌","Selecting faction filters cards")
		check(app.library_grid.get_child(0).get_child(0).spec.name=="单位1","Filter returns matching faction only")
		app.library_filter = "missing"
		app._populate_library()
		check(app.library_count.text=="0 张卡牌","Faction and text filters combine")
		app.library_filter = ""
		picker.select(0)
		picker.item_selected.emit(0)
		await process_frame
		check(app.library_faction.is_empty() and app.library_count.text=="2 张卡牌","All factions restores collection")
		await process_frame
		check(app.deck_drop.get_global_rect().end.x<=root.get_visible_rect().size.x,"Faction control fits desktop/mobile")
		for button in app.nav_buttons.values():
			var text_width: float = button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
			for state_name in ["normal", "hover", "pressed", "disabled"]:
				check(button.size.x - button.get_theme_stylebox(state_name).get_minimum_size().x >= text_width - 0.1, "Navigation text fits in " + state_name + ": " + button.text)
		if capture:
			for button in app.nav_buttons.values():
				button.toggle_mode = true
				button.set_pressed_no_signal(true)
			await snap("navigation-selected-mobile" if phone else "navigation-selected-desktop")
			for button in app.nav_buttons.values():
				button.set_pressed_no_signal(false)
				button.toggle_mode = false
	app.queue_free()
	await process_frame
	print("FACTION_FILTER_RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
