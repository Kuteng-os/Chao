extends SceneTree
func _initialize() -> void:
	var parsed := CardRuntime.parse_json(FileAccess.get_file_as_string("res://docs/cards/examples/generic_test_deck.json"))
	assert(parsed.ok)
	var deck: Array = []
	for spec in parsed.value.specs:
		var card := CardRuntime.compile_card(spec.definition,parsed.value.keywords)
		assert(card.ok)
		for n in int(spec.count): deck.append(card)
	assert(deck.size()==40 and DeckRules.check_copies(deck).is_empty())
	var played := {}
	var revealed := {}
	var actions := 0
	for seed_value in range(1,21):
		var engine := BattleEngine.new()
		assert(engine.setup(deck,deck,seed_value).is_empty())
		for step in 2000:
			if engine.state.winner!=-1: break
			var player: int = engine.state.pending_choice.owner if engine.state.has("pending_choice") else engine.state.active_player
			var action := engine.ai_action(player)
			var result := engine.apply_action(player,action)
			assert(result.is_empty(),result)
			actions += 1
		assert(engine.state.winner in [0,1,2],"Test deck simulation must end without engine abort")
		for event in engine.state.telemetry:
			if event.kind=="play": played[event.name]=true
			if event.kind=="counter_reveal": revealed[event.name]=true
	assert(played.size()==14,"All 14 sample cards should see play across seeded games")
	assert(revealed.size()==3,"All three counter triggers should resolve in seeded games")
	print("GENERIC_DECK_PASS games=20 actions=%d played=%d counters=%d" % [actions,played.size(),revealed.size()])
	quit()

