extends "res://tests/test_ui.gd"
func _run() -> void:
	var registry := {"large":{"category":"large"},"normal":{},"small":{"category":"small"}}
	var cards: Array=[]
	for i in 40: cards.append({"name":"卡"+str(i),"kind":"unit","sin":"wrath" if i<30 else "gloom","faction_id":"large" if i<30 else "small"})
	check(DeckRules.composition(cards,registry,"wrath","gloom").error.is_empty(),"30 main plus 10 secondary is legal")
	cards[0].faction_id="small"
	check("小阵营" in DeckRules.composition(cards,registry,"wrath","gloom").error,"Small cannot occupy main sin")
	cards[0].faction_id="large";cards[39].faction_id="large"
	check("大阵营" in DeckRules.composition(cards,registry,"wrath","gloom").error,"Large cannot occupy secondary sin")
	cards[39].faction_id="small";cards[0].sin="envy"
	check(not DeckRules.composition(cards,registry,"wrath","gloom").error.is_empty(),"Third sin rejected")
	cards[0].sin=null
	check(DeckRules.composition(cards,registry,"wrath","gloom").error.is_empty(),"Neutral fills remaining slot")
	for card in cards: card.sin=null
	check(DeckRules.composition(cards,registry,"wrath","gloom").error.is_empty(),"All neutral cards remain unrestricted")
	check(not DeckRules.composition(cards,registry,"wrath","wrath").error.is_empty(),"Two chosen sins must differ")
	check(DeckRules.composition(cards.slice(0,4),registry,"wrath","gloom",false).error.is_empty(),"Partial draft may be saved")
	check(not DeckRules.composition(cards.slice(0,4),registry,"wrath","gloom").error.is_empty(),"Incomplete deck cannot start")
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.store.settings.backend_url="http://127.0.0.1:1";app.store._ensure_context()
	await process_frame
	app.store.new_local_deck("新规则构筑","","wrath","gloom")
	var spec: Dictionary=CardRuntime.parse_json(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json")).value
	spec.keywords=[]
	for i in 11:
		spec.name="双罪孽"+str(i);spec["sin"]="wrath" if i<8 else "gloom"
		var draft: Dictionary=await app.store.create_draft(spec)
		check(draft.ok,"Deck card compiles: "+str(draft.get("error","")))
		if not draft.ok: quit(1);return
		await app.store.confirm_draft(draft.draft)
		for j in (2 if i==7 or i==10 else 4): check(app.store.add_to_deck(app.store.cards[-1].card_id).is_empty(),"Composition accepts legal count")
	check(app.store.compile_deck().ok,"30/10 deck compiles for practice and cloud")
	app._navigate("library");await process_frame
	var status: Label=app.deck_drop.find_child("DeckRulesStatus",true,false)
	check("30 / 30" in status.text and "10 / 10" in status.text,"Deck UI shows both quotas")
	app.store.remove_from_deck(app.store.cards[0].card_id)
	check(not app.store.compile_deck().ok,"Incomplete remains editable but cannot play")
	var previous: Array=app.store.deck_ids.duplicate()
	check(app.store.select_deck_sins("envy","gloom").is_empty(),"Existing deck may change sins")
	check(app.store.deck_ids==previous and not app.store.deck_composition().error.is_empty(),"Changing sins preserves cards and reports mismatch")
	check(app.store.save_local_deck("不完整草稿").ok,"Invalid old deck may still be saved locally")
	app.store.select_deck_sins("wrath","gloom")
	var controller=load("res://scripts/network/match_controller.gd").new();root.add_child(controller)
	controller.main_sin="wrath";controller.ally_sin="gloom"
	app.store.add_to_deck(app.store.cards[0].card_id)
	var compiled: Dictionary=app.store.compile_deck()
	check(controller._prepare_deck(compiled.deck,[]).ok,"LAN preparation validates own sins")
	check(not controller._prepare_deck(compiled.deck,[],"envy","gloom").ok,"LAN host checks remote sin choices independently")
	controller.queue_free();app.queue_free();await process_frame
	print("DECK_COMPOSITION903_RESULT checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

