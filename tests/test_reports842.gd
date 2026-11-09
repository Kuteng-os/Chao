extends "res://tests/test_engine.gd"
var fixtures: Array
func _initialize() -> void:
	fixtures=JSON.parse_string(FileAccess.get_file_as_string("res://tests/reports842.json")).cards
	for r in fixtures:
		var c:=_compile(r.definition)
		_check(c.definition_hash==r.definition_hash and c.compiled_program_hash==r.compiled_program_hash,"Node/Godot parity")
		_check(not "[object" in Runtime.rules_text(c),"readable rules")
	_kill()
	_faction()
	_choice()
	_return()
	print("REPORTS842: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func _kill() -> void:
	for hp in [1,2,3]:
		var g:=_game();var p:=_rich(g)
		var d:=_base("目标");d.health=hp
		var victim:Dictionary=g._new_unit(1-p,_compile(d));var n:int=g.state.players[p].deck.size()
		_play(g,fixtures[0].definition,victim.uid)
		_check(g.state.players[p].deck.size()==n-(2 if hp<=2 else 1),"extra draw only on direct lethal")
	var g:=_game();var p:=_rich(g);var n:int=g.state.players[p].deck.size()
	_play(g,fixtures[0].definition)
	_check(g.state.players[p].deck.size()==n-1,"missing target still ordinary draw; no false lethal")
	var ctx:Dictionary=g._context(p,-1,_compile(_base()));ctx.last_damage_killed=true
	g._effect({"op":"damage","target":"chosen","amount":0},ctx)
	_check(not ctx.last_damage_killed,"zero/fizzled damage resets prior result")
	var invalid:Dictionary=fixtures[0].definition.duplicate(true);invalid.abilities[0].effects.remove_at(0)
	_check(not Runtime.compile_card(invalid,Runtime.builtin_keywords()).ok,"kill result requires same-group damage")

func _faction() -> void:
	var g:=_game();var p:=_rich(g);var d:=_base("剑士");d["faction_id"]="408c3c32-19c5-49ce-9a9d-055c38d516ba"
	var good:Dictionary=g._new_unit(p,_compile(d));var bad:Dictionary=g._new_unit(p,_compile(_base("其他阵营")))
	_check(g._matches_class(good,fixtures[1].definition.play_target) and not g._matches_class(bad,fixtures[1].definition.play_target),"faction target independent of main class")
	_play(g,fixtures[1].definition,good.uid)
	_check(g._unit(good.uid).equipment.get("剑",0)==1 and g._unit(bad.uid).get("equipment",{}).is_empty(),"equip correct faction only")
	var ctx:Dictionary=g._context(p,-1,_compile(_base()))
	g._effect({"op":"modify_stats","target":"all_friendly_units","unit_filter":{"faction_id":d.faction_id},"attack_delta":1,"health_delta":0,"duration":"battle"},ctx)
	_check(g._unit(good.uid).attack==4 and g._unit(bad.uid).attack==3,"area faction filter respected")
	var invalid:Dictionary=fixtures[1].definition.duplicate(true);invalid.play_target.include_hq=true
	_check(not Runtime.compile_card(invalid,Runtime.builtin_keywords()).ok,"HQ not legal faction unit target")

func _choice() -> void:
	for option in [0,1]:
		var g:=_game();var p:=_rich(g);var hp:int=g.state.players[p].hp;var n:int=g.state.players[p].deck.size()
		_play(g,fixtures[2].definition)
		_check(g.state.pending_choice.kind=="effect" and g.state.scheduled.is_empty(),"choice waits without scheduling either branch")
		var restored:=EngineClass.new();restored.state=g.state.duplicate(true)
		for engine in [g,restored]:
			var c:Dictionary=engine.state.pending_choice
			_check(engine.apply_action(p,{"type":"choose_card","choice_id":c.choice_id,"option_index":option}).is_empty(),"choice commits")
		_check(Runtime.sha(g.state)==Runtime.sha(restored.state),"choice deterministic after reload")
		_check(g.state.players[p].hp==hp+(7 if option==1 else 0),"only selected immediate benefit")
		_check(g.state.players[p].deck.size()==n-(2 if option==0 else 0),"only draw branch draws")
		_check(g.state.scheduled.size()==(1 if option==1 else 0),"only chosen branch scheduled")
		g.state.turn+=1;g._run_roots(g._scheduled_roots("turn_start",1-p))
		_check(g.state.players[p].hp==hp+(7 if option==1 else 0),"wrong owner's start cannot trigger")
		g.state.turn+=1;g._run_roots(g._scheduled_roots("turn_start",p))
		_check(g.state.players[p].hp==hp+(9 if option==1 else 0) and g.state.scheduled.is_empty(),"selected delay executes once")
		g.state.turn+=2;g._run_roots(g._scheduled_roots("turn_start",p))
		_check(g.state.players[p].hp==hp+(9 if option==1 else 0),"no repeat")

func _return() -> void:
	for full in [false,true]:
		var g:=_game();var p:=_rich(g);g.state.players[p].hand=[]
		var compiled:=_compile(fixtures[3].definition)
		var other:Dictionary=g._new_unit(p,compiled);var unit:Dictionary=g._new_unit(p,compiled)
		var uid:int=unit.uid
		# An older identical discarded card must remain untouched.
		g.state.discard.append({"owner":p,"card":compiled,"source_uid":other.uid})
		g._leave_battlefield(other,false)
		var ctx:Dictionary=g._context(p,uid,unit.card,uid)
		g._effect({"op":"modify_stats","target":"chosen","attack_delta":2,"health_delta":2,"duration":"match"},ctx)
		g._effect({"op":"modify_stats","target":"chosen","attack_delta":3,"health_delta":0,"duration":"battle"},ctx)
		if full:
			for i in 10:g._receive_card(p,_compile(_base(str(i))),"test")
		var before:int=g.state.players[p].hand.size()
		unit.destroyed=true;g._checkpoint();g._drain_deaths()
		_check(g._unit(uid).is_empty() and g._fault.is_empty(),"fallen unit stays off board")
		_check(g.state.discard.filter(func(e):return e.get("source_uid")==other.uid).size()==1,"same-name older card untouched")
		_check(g.state.discard.filter(func(e):return e.get("source_uid")==uid).is_empty(),"exact fallen original removed")
		if not full:
			_check(g.state.players[p].hand.size()==before+1,"one original returns")
			var card:Dictionary=g.state.players[p].hand.back().card
			var again:Dictionary=g._new_unit(p,card)
			_check(again.attack==compiled.definition.attack+2 and again.max_hp==compiled.definition.health+2,"only permanent layer survives return")
			g._transfer_card(fixtures[3].definition.abilities[0].effects[0],ctx)
			_check(g.state.players[p].hand.size()==before+1,"cannot retrieve same entity twice")
		else:_check(g.state.players[p].hand.size()==before,"full hand burns original")
