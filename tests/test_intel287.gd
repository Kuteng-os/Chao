extends "res://tests/test_engine.gd"
var fixtures: Dictionary

func _initialize() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/intel287.json"))
	fixtures=data.fixtures
	for key in fixtures:
		_check(_compile(fixtures[key]).compiled_program_hash==data.hashes[key],"Node/native parity "+key)
	_check(Runtime.validate_keyword(data.keyword).is_empty(),"parameterized chosen intel keyword compiles")
	_test_selection()
	_test_empty_and_multiple()
	_test_counter_privacy()
	print("INTEL 287: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func _choose(g: RefCounted,owner: int,index: int) -> String:
	return g.apply_action(owner,{"type":"choose_card","choice_id":g.state.pending_choice.choice_id,"option_index":index})

func _test_selection() -> void:
	var g:=_game();var me:=_rich(g);var enemy:=1-me
	var held: Array=g._held_cards(enemy)
	held[0]["revealed"]=true
	var selected_id: String=held[2].instance_id
	var deck_before: int=g.state.players[me].deck.size()
	_play(g,fixtures.chosen)
	_check(g.state.has("pending_choice"),"chosen intel pauses for the caster")
	var pending: Dictionary=g.state.pending_choice
	_check(pending.kind=="intel" and pending.owner==me,"caster controls choice")
	_check(pending.options.size()==held.size()-1,"already revealed cards excluded")
	_check(pending.options[0].hand_position==1,"original public slot positions retained")
	for option in pending.options:
		_check(option.keys().size()==2 and option.hidden and option.has("hand_position"),"only public slot data in options")
	_check(g.view_for(enemy).pending_choice.get("options",[]).is_empty(),"other player cannot read options")
	_check(g.view_for(me).players[enemy].hand.is_empty(),"opponent hand remains redacted")
	var before:=Runtime.canonical(g.state)
	_check(not _choose(g,enemy,0).is_empty(),"foreign player cannot choose")
	_check(not _choose(g,me,99).is_empty(),"out of bounds choice rejected")
	_check(Runtime.canonical(g.state)==before,"invalid choices leave state unchanged")
	var action: Dictionary={"type":"choose_card","choice_id":pending.choice_id,"option_index":1}
	_check(g.apply_action(me,action).is_empty(),"caster selects original third slot")
	_check(not g.state.has("pending_choice"),"selection finishes")
	_check(g._hand(enemy,selected_id).get("revealed",false),"exact selected card is revealed")
	_check(g.view_for(me).players[enemy].revealed_hand.size()==2,"no extra hand leaked")
	_check(g.state.players[me].deck.size()==deck_before-1,"remaining draw executes once")
	before=Runtime.canonical(g.state)
	_check(not g.apply_action(me,action).is_empty(),"stale choice rejected")
	_check(Runtime.canonical(g.state)==before,"stale replay cannot draw twice")
	var twin:=_game();twin.state=g.state.duplicate(true)
	_check(g.view_for(me)==twin.view_for(me),"reconnected authority preserves known cards")

func _test_empty_and_multiple() -> void:
	for all_known in [false,true]:
		var g:=_game();var me:=_rich(g)
		if all_known:
			for entry in g.state.players[1-me].hand: entry["revealed"]=true
		else: g.state.players[1-me].hand=[]
		var before: int=g.state.players[me].deck.size()
		_play(g,fixtures.chosen)
		_check(not g.state.has("pending_choice"),"no eligible cards skips selection")
		_check(g.state.players[me].deck.size()==before-1,"empty intel still allows other effects")
	var g:=_game();var me:=_rich(g);var enemy:=1-me
	var total: int=g._held_cards(enemy).size()
	var before: int=g.state.players[me].deck.size()
	_play(g,fixtures.multiple)
	for i in total:
		_check(g.state.pending_choice.options.size()==total-i,"previously selected card removed from next choice")
		_check(_choose(g,me,0).is_empty(),"multi-card choice resumes")
	_check(not g.state.has("pending_choice"),"insufficient hand finishes after all available cards")
	_check(g.view_for(me).players[enemy].revealed_hand.size()==total,"all selected cards revealed")
	_check(g.state.players[me].deck.size()==before-1,"nested replay executes followup exactly once")
	g=_game();me=_rich(g);_play(g,fixtures.random)
	_check(not g.state.has("pending_choice") and g.view_for(me).players[1-me].revealed_hand.size()==2,"legacy random intel unchanged")

func _test_counter_privacy() -> void:
	var g:=_game();var me:=_rich(g);var enemy:=1-me
	# Arming cannot change public hand slots or disclose the armed state.
	var entry: Dictionary=g.state.players[enemy].hand.pop_at(1)
	var counter:=_base("隐蔽反制","counter")
	counter.appearance.emblem="counter";counter["counter_trigger"]="enemy_hq_attacked"
	counter.abilities=[{"trigger":"on_reveal","effects":[{"op":"gain_hq_defense","player":"owner","amount":1}]}]
	entry.card=_compile(counter);entry["armed_turn"]=g.state.turn-1
	g.state.players[enemy].counters.append(entry)
	_play(g,fixtures.chosen)
	var count: int=g._held_cards(enemy).size()
	_check(g.state.pending_choice.options.size()==count,"armed counter remains a hidden hand candidate")
	_check(not JSON.stringify(g.view_for(me).pending_choice).contains("armed"),"choice does not reveal counter status")
	_check(_choose(g,me,1).is_empty(),"can reveal selected hidden counter")
	var revealed: Array=g.view_for(me).players[enemy].revealed_hand
	_check(revealed.size()==1 and revealed[0].position==1,"counter exposes only its selected public slot")
