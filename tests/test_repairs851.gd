extends "res://tests/test_engine.gd"
var fixtures: Dictionary

func _initialize() -> void:
	fixtures=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/repairs851.json"))
	var parity: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/parity851.json"))
	for key in fixtures:
		var c:=_compile(fixtures[key])
		if c.ok:
			_check(not Runtime.rules_text(c).is_empty(),"print "+key)
			if parity is Dictionary:_check(c.compiled_program_hash==parity[key].compiled_program_hash,"Node/native parity "+key)
	if failures:quit(1);return
	_filters_and_packets()
	_draw_and_hand()
	_lifecycle()
	_events()
	_choices()
	_token_parameters()
	_remaining_packets()
	print("REPAIRS 851: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _spawn(g: RefCounted,owner: int,c: Dictionary) -> Dictionary:
	return g._new_unit(owner,_compile(c))

func _filters_and_packets() -> void:
	var g:=_game();var me:=_rich(g)
	var green:=_base();green["sin"]="gluttony"
	var a:=_spawn(g,me,green);var b:=_spawn(g,me,_base());var enemy:=_spawn(g,1-me,green)
	_play(g,fixtures.sin)
	_check(g._unit(a.uid).attack==4 and g._unit(b.uid).attack==3 and g._unit(enemy.uid).attack==3,"sin filter applies only friendly gluttony")
	var before: int=g.state.players[me].deck.size()
	_play(g,fixtures.remove_draw,a.uid)
	_check(g.state.players[me].deck.size()==before-2 and g._unit(a.uid).is_empty(),"removed friendly target retains identity for next condition")
	before=g.state.players[me].deck.size();_play(g,fixtures.remove_draw,enemy.uid)
	_check(g.state.players[me].deck.size()==before,"removed enemy target does not draw")
	g=_game();me=_rich(g);g.state.players[1-me].hq_index=0
	var one:=_base();one.attack=1;var air:=_base();air.unit_class="fighter";air.appearance.emblem="fighter"
	a=_spawn(g,1-me,one);b=_spawn(g,1-me,_base());enemy=_spawn(g,1-me,air)
	g._write_line(1-me,"support",[-1,a.uid,b.uid,enemy.uid])
	_play(g,fixtures.capped,b.uid)
	_check(g._unit(a.uid).hp==3 and g._unit(b.uid).hp==2 and g._unit(enemy.uid).hp==3,"per-target attack and air cap independently evaluate")
	g=_game();me=_rich(g);a=_spawn(g,me,fixtures.higher_attack);b=_spawn(g,1-me,_base())
	g._initialize_summoned_unit(a)
	_check(g._combat_damage(a,b,"attack")==3,"equal attack does not meet strictly greater")
	b.attack=5
	_check(g._combat_damage(a,b,"attack")==6 and g._combat_damage(a,b,"retaliation")==3,"conditional attack-only modifier does not buff counterattack")
	g=_game();me=_rich(g);a=_spawn(g,me,_base());a.damage_taken=1;g._recompute(a)
	_play(g,fixtures.max_only,a.uid);a=g._unit(a.uid)
	_check(a.hp==3 and a.max_hp==6,"max defense does not heal")
	g._effect({"op":"heal","target":"self","amount":3},g._context(me,a.uid,a.card));g._checkpoint()
	_check(a.hp==6,"max-only capacity can subsequently be healed")
	g=_game();me=_rich(g);a=_spawn(g,me,fixtures.random_hq)
	g._effect({"op":"damage","target":"random_enemy_target","amount":4},g._context(me,a.uid,a.card));g._checkpoint()
	_check(g.state.players[1-me].hp==16,"random target includes HQ when there are no enemy units")

func _draw_and_hand() -> void:
	var g:=_game();var me:=_rich(g)
	var before: int=g.state.players[me].deck.size()
	var old: Array=g.state.players[me].hand.map(func(e):return e.instance_id)
	_play(g,fixtures.return_drawn)
	_check(g.state.players[me].deck.size()==before,"odd freshly drawn card actually returns to deck")
	_check(g.state.players[me].hand.map(func(e):return e.instance_id)==old,"same-name old hand instances remain untouched")
	var even:=_base();even.cost=2;g.state.players[me].deck.append(_compile(even));before=g.state.players[me].deck.size()
	_play(g,fixtures.top);_check(g.state.players[me].deck.size()==before-1,"peek even deck top draws it")
	before=g.state.players[me].deck.size();_play(g,fixtures.top);_check(g.state.players[me].deck.size()==before,"odd top does not draw or reorder")
	g=_game();me=_rich(g);var a:=_spawn(g,me,_base());var context: Dictionary=g._context(me,a.uid,a.card)
	g._choice_answers=[0];g._choice_cursor=0
	before=g.state.players[me].hand.size()
	g._effect(fixtures.hand_summon.abilities[0].effects[0],context);g._checkpoint();g._drain_deaths()
	_check(g.state.players[me].hand.size()==before-1 and g.state.units.size()==2,"summoning from hand removes original hand instance")
	_check(g._fault.is_empty(),"hand summon completes")

func _lifecycle() -> void:
	var g:=_game();var me:=_rich(g)
	var a:=_spawn(g,1-me,_base());a.damage_taken=2;a.moved=true;a.attacks_used=1;g._recompute(a)
	var id: int=a.uid
	_play(g,fixtures.suspend,id)
	_check(g._unit(id).is_empty() and g.state.suspended.size()==1,"temporary removal does not kill")
	g._release_suspended("end_of_turn");g._checkpoint();g._drain_deaths();a=g._unit(id)
	_check(a.hp==2 and a.moved and a.attacks_used==1,"return retains damage and action state")
	_check(g.state.suspended.is_empty() and not g.state.discard.any(func(e):return e.get("source_uid")==id),"temporary removal does not create discard duplicate")
	g=_game();me=_rich(g);a=_spawn(g,1-me,_base());id=a.uid
	var prison: int=_play(g,fixtures.prison,id)
	_check(g._unit(id).is_empty(),"source holds captured unit")
	var before: int=g.state.players[1-me].hand.size()
	g._leave_battlefield(g._unit(prison),true);g._checkpoint();g._drain_deaths()
	_check(g.state.players[1-me].hand.size()==before+1,"bouncing captor releases exact captured card")
	_check(g.play_cost(1-me,g.state.players[1-me].hand.back().card)==0,"returned card is free")
	g=_game();me=_rich(g);id=_play(g,fixtures.evolve)
	_check(g.state.scheduled.size()==1,"evolution is scheduled")
	_play(g,fixtures.evolve_now,id)
	_check(g._unit(id).is_empty() and g.state.units.size()==1 and g.state.units[0].attack==6,"external evolution uses target's own template")
	_check(g.state.scheduled.is_empty(),"early evolution consumes old schedule")
	a=g.state.units[0];a.destroyed=true;g._checkpoint();g._drain_deaths()
	_check(g.state.units.size()==1 and g.state.units[0].card.definition.name==fixtures.evolve.name,"derived death can summon original main card")

func _events() -> void:
	var g:=_game();var me:=_rich(g);var a:=_spawn(g,me,fixtures.on_damage)
	g.state.players[me].hp=15
	g._effect({"op":"damage","target":"self","amount":2},g._context(me,a.uid,a.card));g._checkpoint();g._drain_deaths()
	_check(a.attack==5 and g.state.players[me].hp==17,"damage event amount supplies both attack and healing")
	g=_game();me=_rich(g);a=_spawn(g,me,fixtures.occurrence)
	var before: int=g.state.players[me].deck.size()
	_play(g,_base());_play(g,_base());_play(g,_base());a=g._unit(a.uid)
	_check(g.state.players[me].deck.size()==before-1 and a.attack==4,"first tank draws, second buffs, third does neither")
	g=_game();me=_rich(g);a=_spawn(g,me,fixtures.retreat_event);var b:=_spawn(g,me,_base())
	g._effect({"op":"return_to_hand","target":"chosen"},g._context(me,a.uid,a.card,b.uid));g._checkpoint();g._drain_deaths()
	_check(a.attack==3,"generic bounce is distinct from retreat event")
	b=_spawn(g,me,_base());g._effect({"op":"retreat","target":"chosen"},g._context(me,a.uid,a.card,b.uid));g._checkpoint();g._drain_deaths()
	_check(a.attack==4 and a.hp==6,"explicit retreat triggers listener once")
	g=_game();me=_rich(g);a=_spawn(g,me,fixtures.attacks)
	g.state.players[1-me].hp=100
	for i in 6:g._attack(a.uid,-1)
	_check(g.state.players[1-me].hp==77,"attack watcher covers its own attacks within limit")

func _choices() -> void:
	var g:=_game();var me:=_rich(g);var enemy:=_spawn(g,1-me,_base())
	var infantry:=_base();infantry.unit_class="infantry";infantry.appearance.emblem="infantry"
	var ally:=_spawn(g,me,infantry)
	_play(g,fixtures.choice)
	_check(g.state.has("pending_choice") and g.state.pending_choice.kind=="effect","choice asks branch before unit")
	var error: String=g.apply_action(me,{"type":"choose_card","choice_id":g.state.pending_choice.choice_id,"option_index":1})
	_check(error.is_empty(),"branch choice succeeds "+error)
	if not g.state.has("pending_choice"):return
	_check(g.state.pending_choice.targets==[ally.uid],"branch target pool contains only friendly infantry")
	error=g.apply_action(me,{"type":"choose_target","choice_id":g.state.pending_choice.choice_id,"target_uid":ally.uid})
	_check(error.is_empty() and not g.state.has("pending_choice"),"unit choice finishes action "+error)
	_check(g._unit(ally.uid).attack==5 and not g._unit(enemy.uid).has("pinned_until"),"only chosen branch takes effect")

func _token_parameters() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/token851.json"))
	var c: Dictionary=Runtime.compile_card(fixture.card,[fixture.keyword])
	_check(c.ok,"native token parameter compiles "+c.get("error",""))
	if c.ok:_check(c.definition.abilities[0].effects[0].effects[0].token_id=="form","token parameter substitutes deep in schedule")

func _remaining_packets() -> void:
	var g:=_game();var me:=_rich(g);var a:=_spawn(g,me,fixtures.guard_damage);var b:=_spawn(g,1-me,_base())
	g._initialize_summoned_unit(a)
	_check(g._combat_damage(a,b,"attack")==3,"guard bonus does not apply to ordinary unit")
	g._effect({"op":"grant_keyword","target":"self","keyword_id":"core.guard","duration":"battle"},g._context(1-me,b.uid,b.card))
	_check(g._combat_damage(a,b,"attack")==5,"guard combat bonus checks current keyword")
	g=_game();me=_rich(g);a=_spawn(g,me,fixtures.air_attack)
	var air:=_base();air.unit_class="fighter";air.appearance.emblem="fighter";air.attack=0
	b=_spawn(g,1-me,air);var other:=_spawn(g,1-me,air)
	b.damage_taken=3;g._recompute(b);g._attack(a.uid,b.uid)
	_check(g._unit(b.uid).is_empty() and g._unit(other.uid).hp==3,"after-attack class query survives defeated air target")
	g=_game();me=_rich(g);a=_spawn(g,me,fixtures.random_hq)
	g._effect({"op":"trigger_death","target":"self"},g._context(me,a.uid,a.card));g._drain_deaths();g._checkpoint()
	_check(not g._unit(a.uid).is_empty() and g.state.players[1-me].hp==16,"trigger death ability does not kill source")
	g=_game();me=_rich(g)
	a=_spawn(g,me,_base());b=_spawn(g,me,_base());other=_spawn(g,me,_base())
	g._write_line(me,"support",[-1,a.uid,b.uid,other.uid])
	g.state.players[1-me].counters=[{"card":_compile(fixtures.counter),"armed_turn":int(g.state.turn)-1}]
	g.state.players[1-me].credits=12
	g._trigger_counters(me,"enemy_unit_deployed",b.uid);g._checkpoint();g._drain_deaths()
	_check(g._pinned(a) and g._pinned(b) and g._pinned(other),"counter covers triggering unit and adjacent neighbors")
	g=_game();me=_rich(g)
	_check(g._premise_value({"stat":"friendly_turn_number"},{"owner":me})==1,"personal first turn is one")
	g.state.players[me]["turns_started"]=6
	_check(g._premise_met({"test":"compare","left":{"stat":"friendly_turn_number"},"cmp":"gte","right":6},{"owner":me}),"personal turn does not depend on kredit capacity")
	g.state.players[1-me].credits=1
	g._effect({"op":"lose_kredits","player":"opponent","amount":2},g._context(me,-1,_compile(fixtures.lose)))
	_check(g.state.players[1-me].credits==0,"kredit loss never becomes negative")
