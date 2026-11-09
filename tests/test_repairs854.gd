extends "res://tests/test_engine.gd"
var fixtures: Dictionary

func _initialize() -> void:
	fixtures=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/repairs854.json"))
	var parity: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/parity854.json"))
	for key in fixtures:
		var card:=_compile(fixtures[key])
		if card.ok and parity is Dictionary: _check(card.compiled_program_hash==parity[key].compiled_program_hash,"native/Node parity "+key)
	if failures: quit(1);return
	_counter()
	_aura()
	_costs()
	_field()
	_liberation()
	print("REPAIRS 854: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _spawn(g: RefCounted,owner: int,c: Dictionary) -> Dictionary:
	return g._new_unit(owner,_compile(c))

func _counter() -> void:
	var g:=_game();var me:=_rich(g)
	var a:=_spawn(g,me,_base());var b:=_spawn(g,1-me,_base())
	a.row="front";a.born_turn=-1
	var c:=_compile(fixtures.counter)
	g.state.players[1-me].credits=4
	g.state.players[1-me].counters.append({"instance_id":"trap","card":c,"armed_turn":g.state.turn-1})
	_check(g.apply_action(me,{"type":"attack","uid":a.uid,"target_uid":b.uid}).is_empty(),"attack triggers hidden unit counter")
	_check(g.state.units.is_empty(),"counter destroys attacker and defender before damage")
	_check(g.state.players[1-me].credits==3 and g.state.players[1-me].counters.is_empty(),"counter pays only on activation")
	_check(g.state.discard.size()==3,"both victims and counter reach discard")

func _aura() -> void:
	var g:=_game();var me:=_rich(g)
	var a:=_spawn(g,me,_base());a.damage_taken=1
	var enemy:=_spawn(g,1-me,_base())
	var source:=_spawn(g,me,fixtures.aura)
	g._checkpoint()
	_check(a.attack==5 and a.max_hp==6 and a.hp==3,"max-only group aura increases ceiling without healing")
	_check(enemy.attack==3 and enemy.max_hp==4,"friendly aura does not buff enemy")
	var fresh:=_spawn(g,me,_base());g._checkpoint()
	_check(fresh.attack==5 and fresh.hp==4 and fresh.max_hp==6,"future entrants gain capacity-only aura")
	g._effect({"op":"heal","target":"self","amount":2},g._context(me,a.uid,a.card));g._checkpoint()
	_check(a.hp==5,"increased capacity can be healed")
	g._suppress(source);g._checkpoint()
	_check(a.attack==3 and a.max_hp==4 and fresh.attack==3,"suppression removes aura immediately")

func _costs() -> void:
	var g:=_game();var me:=_rich(g);var c:=_compile(fixtures.cost)
	for pair in [[4,2],[5,3],[7,3],[8,4],[12,4]]:
		g.state.players[me].turns_started=pair[0]
		_check(g.play_cost(me,c)==pair[1],"surcharge highest tier only at turn "+str(pair[0]))
	g.state.players[me].hand.append({"instance_id":"cost","card":c})
	g.state.players[me].credits=3
	_check(g.legal_targets(me,{"type":"play","hand_id":"cost"}).is_empty(),"insufficient conditional cost prevents the play")
	var budget: Dictionary=g._budget.duplicate(true)
	for i in 100: g.play_cost(me,c)
	_check(g._budget==budget,"cost display consumes no action budget")

func _field() -> void:
	var g:=_game();var me:=_rich(g)
	for player in [0,1]:
		g.state.players[player].hand.clear();g.state.players[player].deck.clear()
		var c:=_base("入场抽牌");c.abilities=[{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]},{"trigger":"on_summon","effects":[{"op":"damage","target":"own_hq","amount":7}]}]
		g.state.players[player].deck.append(_compile(c))
		_spawn(g,player,_base("场上"))
		g.state.discard.append({"owner":player,"card":_compile(_base("弃牌"))})
		g.state.players[player].hand.append({"instance_id":"old"+str(player),"card":_compile(_base("手牌"))})
	_play(g,fixtures.field)
	_check(g.state.has("pending_choice") and g.state.pending_choice.owner==me,"first player chooses own deck unit")
	for i in 2:
		if not g.state.has("pending_choice"): _check(false,"missing deck deployment choice");return
		var choice: Dictionary=g.state.pending_choice
		var index:=0
		for j in choice.options.size():
			if choice.options[j].definition.name=="入场抽牌":index=j
		_check(g.apply_action(choice.owner,{"type":"choose_card","choice_id":choice.choice_id,"option_index":index}).is_empty(),"free deployment resolves selection")
	_check(not g.state.has("pending_choice") and g.state.units.size()==2,"both selections settle")
	for player in [0,1]:
		_check(g.state.players[player].hp==20,"free deploy fires deployment, not summon effects")
		_check(g.state.players[player].hand.size()==1 and g.state.players[player].deck.size()==2,"shuffle conserves cards and deployment draw resolves")
		_check(not g._unit_entry_allowed(player),"field blocks additional unit entry")
		var u: Dictionary=g.state.units.filter(func(x):return x.owner==player)[0]
		_check(u.attack==8 and u.max_hp==9 and g._has_keyword(u,"core.guard") and g._has_keyword(u,"core.fury") and g._has_keyword(u,"core.immune"),"field continuously buffs both units")
	var before: int=g.state.players[me].deck.size()
	g._reset_budget();g._transfer_card({"source":"deck","destination":"support","mode":"move","selection":"top","amount":1},g._context(me,-1,_compile(fixtures.field)))
	_check(g.state.players[me].deck.size()==before and g.state.units.size()==2,"blocked summon never consumes a deck card")
	g.state.erase("field");g._checkpoint()
	_check(g._unit_entry_allowed(me) and g.state.units[0].attack==3 and not g._has_keyword(g.state.units[0],"core.immune"),"field replacement removes buffs and entry cap")

func _liberation() -> void:
	var g:=_game();var me:=_rich(g)
	var a:=_spawn(g,me,fixtures.liberate);var b:=_spawn(g,me,_base())
	a.row="front";a.attacks_used=1;a.moved=true;a.pinned_until=99
	g._emit_unit_event(me,"unit_retreated",b.uid,b.card);g._drain_deaths()
	_check(not a.get("liberated",false),"another unit retreat never liberates source")
	g._emit_unit_event(me,"unit_retreated",a.uid,a.card);g._drain_deaths();g._checkpoint()
	_check(a.get("liberated",false) and a.attack==4 and a.operation_cost==0,"self retreat swaps to authored form")
	_check(a.attacks_used==1 and a.moved and a.pinned_until==99,"liberation preserves action and pin state")
	var hash_before: String=a.card.definition_hash
	g._liberate(a,"released")
	_check(a.card.definition_hash==hash_before,"liberation happens once per in-play instance")
	g._leave_battlefield(a,true)
	var returned: Dictionary=g.state.players[me].hand.back().card
	_check(returned.definition.name==fixtures.liberate.name and returned.definition.attack==3 and not returned.has("liberated_form"),"returned card restores its waiting base form")
	var next: Dictionary=g._new_unit(me,returned)
	g._emit_unit_event(me,"unit_retreated",next.uid,next.card);g._drain_deaths()
	_check(next.get("liberated",false),"new battlefield instance can liberate again")
