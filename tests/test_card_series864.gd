extends "res://tests/test_ui.gd"
const Series = preload("res://scripts/core/card_series.gd")
func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.store.settings.backend_url = "http://127.0.0.1:1"
	app.store._ensure_context()
	await process_frame
	var spec: Dictionary = CardRuntime.parse_json(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json")).value
	spec.keywords = []
	for i in 3:
		spec.name = "期数筛选"+str(i)
		var draft: Dictionary = await app.store.create_draft(spec)
		check(draft.ok,"Series fixture compiles")
		await app.store.confirm_draft(draft.draft)
	check(app.store.cards.size()==3,"Three distinct cards")
	check(Series.number(app.store.cards[2])==2,"New local card defaults to second series")
	app.store.cards[0].erase("series")
	app.store.cards[1].series = 1
	check(Series.number(app.store.cards[0])==1,"Legacy records default to first series")
	var raw: Dictionary = app.store.cards[2].duplicate(true)
	var hashes: Array = [raw.definition_hash,raw.compiled_program_hash]
	app.store.cards[2].series = 1
	app.store._ingest_remote(raw,app.store._bound_server,[])
	check(app.store.cards.size()==3 and app.store.cards[2].series==2,"Same-revision metadata refresh updates cached series without duplication")
	check([app.store.cards[2].definition_hash,app.store.cards[2].compiled_program_hash]==hashes,"Series preserves gameplay hashes")
	for phone in [false,true]:
		app.mobile = phone
		root.size = Vector2i(1280,800) if phone else Vector2i(1440,900)
		app.library_series = 0
		app.library_filter = ""
		app._navigate("library")
		await process_frame
		var picker: OptionButton = app.content.find_child("LibrarySeriesFilter",true,false)
		check(picker.item_count==3,"Both series always selectable")
		picker.item_selected.emit(1)
		await process_frame
		check(app.library_count.text=="2 张卡牌","First series includes legacy card")
		picker.item_selected.emit(2)
		await process_frame
		check(app.library_count.text=="1 张卡牌","Second series filters accurately")
		check(app.library_grid.get_child(0).find_child("CardSeries",true,false)==null,"Series is hidden metadata without card badges")
		check(app.library_grid.get_child(0).get_child(0).spec.name=="期数筛选2","Period never prefixes card names")
		app.library_filter = "期数筛选0"
		app._populate_library()
		check(app.library_count.text=="0 张卡牌","Period combines with search")
		app.library_filter = ""
		picker.item_selected.emit(0)
		await process_frame
		check(app.library_count.text=="3 张卡牌","All series restores collection")
		var cost: Control = app.content.find_child("LibraryCostFilter",true,false)
		check(absf(picker.global_position.y-cost.global_position.y)<1,"Filters remain on one row")
		check(cost.get_global_rect().end.x<=root.get_visible_rect().size.x,"New filter fits desktop and phone")
		check(app.store.add_to_deck(app.store.cards[0].card_id).is_empty(),"First series can enter deck")
		check(app.store.add_to_deck(app.store.cards[2].card_id).is_empty(),"Mixed series remain legal")
	app.queue_free()
	await process_frame
	print("CARD_SERIES864_RESULT checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
