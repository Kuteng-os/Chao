extends "res://tests/test_engine.gd"
var fixtures: Dictionary

func _initialize() -> void:
	fixtures=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/repairs850.json"))
	for key in fixtures:
		var c:=_compile(fixtures[key])
		if c.ok: _check(not Runtime.rules_text(c).is_empty(),"rules: "+key)
	if failures: quit(1);return
	_filters()
	_combat_events()
	_deaths_and_limits()
	_schedules()
	_transfers_and_control()
	_choice_regression()
	_veteran()
	print("REPAIRS 850: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _spawn(g: RefCounted,owner: int,spec: Dictionary) -> Dictionary:
	return g._new_unit(owner,_compile(spec))

func _filters() -> void:
	var g:=_game();var me:=_rich(g)
	var small:=_base();small.health=1
	var a:=_spawn(g,me,small);var b:=_spawn(g,1-me,small);var healthy:=_spawn(g,me,_base())
	_play(g,fixtures.low_health)
	a=g._unit(a.uid);b=g._unit(b.uid);healthy=g._unit(healthy.uid)
	_check(a.hp==4 and b.hp==4 and healthy.hp==4,"stat group filter excludes healthy units")
	a.damage_taken=2;g._recompute(a)
	_play(g,fixtures.set_health)
	a=g._unit(a.uid);healthy=g._unit(healthy.uid)
	_check(a.attack==a.hp and healthy.attack==healthy.hp,"set attack snapshots post-buff current defense per target")
	var attack: int=a.attack;a.damage_taken+=1;g._recompute(a)
	_check(a.attack==attack,"set attack is snapshot not aura")
	var even:=_spawn(g,1-me,fixtures.attack_gain)
	var odd:=_spawn(g,1-me,_base())
	var id: String='even';g.state.players[me].hand.append({'instance_id':id,'card':_compile(fixtures.even_destroy)})
	var legal: Array=g.legal_targets(me,{'type':'play','hand_id':id})
	_check(even.uid in legal and not odd.uid in legal,"even current attack restricts chosen target")
	g=_game();me=_rich(g)
	var guard:=_base();guard.keywords=[{'id':'core.guard','version':1,'params':{}}]
	_spawn(g,me,guard)
	# Put the HQ on the outside so the two units really are adjacent.
	g.state.players[me].hq_index=0
	var adjacent:=_play(g,fixtures.adjacent_guard)
	_check(g._unit(adjacent).attack==4,"adjacent guard is counted without headquarters")

func _combat_events() -> void:
	var g:=_game();var me:=_rich(g)
	var a:=_spawn(g,me,fixtures.attack_gain);var b:=_spawn(g,1-me,_base())
	g._attack(a.uid,b.uid)
	_check(a.attack==5 and a.max_hp==9,"on_attack reads target before combat")
	g=_game();me=_rich(g)
	a=_spawn(g,me,fixtures.after_set);b=_spawn(g,1-me,_base());b.damage_taken=0
	g._attack(a.uid,b.uid)
	_check(b.hp==2 and b.attack==2,"after_attack targets surviving attacked unit")
	g=_game();me=_rich(g)
	a=_spawn(g,me,_base());var uid: int=a.uid
	_play(g,fixtures.grant,uid)
	a=g._unit(uid)
	_check(a.card.get('match_abilities',[]).size()==1,"permanent grant persisted in card")
	g._attack(uid,-1)
	_check(g.state.players[me].hp==23,"attached after_attack executes for recipient")

func _deaths_and_limits() -> void:
	var g:=_game();var me:=_rich(g)
	var victim:=_spawn(g,me,fixtures.death_ground)
	var attacker:=_spawn(g,1-me,_base())
	g._effect({'op':'damage','target':'chosen','amount':10},g._context(1-me,attacker.uid,attacker.card,victim.uid));g._checkpoint();g._drain_deaths()
	_check(g.state.players[me].hp==23 and g.state.players[1-me].hp==20,"death remembers ground killer")
	g=_game();me=_rich(g)
	for i in 3: _spawn(g,me if i==0 else 1-me,_base())
	_play(g,fixtures.destroy_count)
	_check(g.state.players[me].hp==23 and g.state.players[1-me].hp==17,"later group sees actual same-card kills")
	_play(g,fixtures.destroy_count)
	_check(g.state.players[me].hp==23,"destroy count resets between actions")
	g=_game();me=_rich(g)
	_spawn(g,me,fixtures.once)
	var destroy:=_base('消灭','order');destroy.abilities=[{'trigger':'on_play','effects':[{'op':'destroy','target':'all_enemy_units'}]}]
	for i in 2:_spawn(g,1-me,_base())
	_play(g,destroy)
	_check(g.state.units.filter(func(u):return u.owner==me).size()==2,"simultaneous deaths share once-per-turn limit")
	g.state.turn+=2
	_spawn(g,1-me,_base());_play(g,destroy)
	_check(g.state.units.filter(func(u):return u.owner==me).size()==3,"per-turn limit resets")

func _schedules() -> void:
	var g:=_game();var me:=_rich(g)
	_play(g,fixtures.entry)
	var before: int=g.state.players[me].deck.size()
	_play(g,_base());_play(g,_base())
	_check(g.state.players[me].deck.size()==before-2,"repeated entry listener covers later deployments")
	var summoned:=_spawn(g,me,_base());g._initialize_summoned_unit(summoned);g._drain_deaths()
	_check(g.state.players[me].deck.size()==before-3,"entry listener includes summons")
	g.state.turn+=1
	_spawn(g,me,_base());g._drain_deaths()
	g._prune_schedules();_check(g.state.scheduled.is_empty(),"turn listener expires")
	g=_game();me=_rich(g);_play(g,fixtures.hq_attack)
	var a:=_spawn(g,me,_base());before=g.state.players[me].deck.size()
	g._attack(a.uid,-1);g._attack(a.uid,-1)
	_check(g.state.players[me].deck.size()==before-2,"HQ-attack schedule repeats")

func _transfers_and_control() -> void:
	var g:=_game();var me:=_rich(g)
	var before: int=g.state.players[me].deck.size();var hand_before: int=g.state.players[me].hand.size()
	_play(g,fixtures.hand_move)
	_check(g.state.has('pending_choice'),"hand-to-deck prompts choice")
	var choice: Dictionary=g.state.pending_choice
	var error: String=g.apply_action(me,{'type':'choose_card','choice_id':choice.choice_id,'option_index':0})
	_check(error.is_empty() and not g.state.has('pending_choice'),"hand move choice replay completes")
	_check(g.state.players[me].deck.size()==before-4,"one card returned before five draws")
	_check(g.state.players[me].hand.size()==hand_before+4,"moved hand card removed exactly once")
	g=_game();me=_rich(g)
	var enemy:=_spawn(g,1-me,_base());enemy.damage_taken=1;g._recompute(enemy)
	var uid: int=enemy.uid
	_play(g,fixtures.control,uid)
	_check(g._unit(uid).owner==me and g._unit(uid).hp==3,"control retains instance damage")
	g._end_turn()
	_check(g._unit(uid).owner==1-me and g._unit(uid).hp==3,"temporary control returns at turn end")

func _choice_regression() -> void:
	var g:=_game();var me:=_rich(g);var b:=_spawn(g,1-me,_base())
	_play(g,fixtures.choice,b.uid)
	_check(g.state.has('pending_choice'),"chosen target plus branch opens prompt")
	var error: String=g.apply_action(me,{'type':'choose_card','choice_id':g.state.pending_choice.choice_id,'option_index':1})
	_check(error.is_empty() and g._unit(b.uid).hp==3,"nested choice retains common target")

func _veteran() -> void:
	var g:=_game();var me:=_rich(g)
	var a:=_spawn(g,me,fixtures.veteran);var uid: int=a.uid
	a.born_turn=0;a.attacks_used=1;a.moved=true;a.damage_taken=1
	var context: Dictionary=g._context(me,uid,a.card)
	g._effect({"op":"modify_stats","target":"self","attack_delta":2,"health_delta":2,"duration":"match"},context)
	g._effect({"op":"modify_stacks","target":"self","stack":"heavy_armor","amount":2,"duration":"match"},context)
	g._effect({"op":"become_veteran","target":"self"},context);g._drain_deaths()
	a=g._unit(uid)
	_check(a.is_veteran and a.attack==4 and a.hp==5,"veteran changes preset form and replaces buffs/damage")
	_check(a.attacks_used==1 and a.moved and a.born_turn==0,"veteran does not refresh actions or redeploy")
	_check(g._has_keyword(a,"core.guard") and not g._has_keyword(a,"core.blitz") and a.stacks.heavy_armor==0,"veteran replaces abilities/armor")
	_check(g.state.players[me].hp==21,"on_veteran fires, ordinary deployment does not")
	_check(a.card.definition.sin=="wrath","veteran inherits unspecified sin")
	g._effect({"op":"become_veteran","target":"self"},g._context(me,uid,a.card));g._drain_deaths()
	_check(g.state.players[me].hp==21,"veteran is idempotent")
	_check(g._premise_met({"test":"unit_state","target":"self","state":"is_veteran"},g._context(me,uid,a.card)),"veteran state can be queried")
	g=_game();me=_rich(g)
	a=_spawn(g,me,fixtures.veteran);a.born_turn=0;uid=a.uid
	var error: String=g.apply_action(me,{"type":"move","uid":uid})
	_check(error.is_empty(),"veteran move action: "+error)
	a=g._unit(uid)
	_check(a.row=="front" and a.is_veteran and a.moved,"frontline condition upgrades in place")
	g._leave_battlefield(a,true)
	var returned: Dictionary=g.state.players[me].hand.back().card
	_check(returned.definition.name==fixtures.veteran.name and returned.has("veteran_form")==false,"return to hand restores original form")
	_check(returned.definition.veteran.token_id=="veteran","returned unit can earn veteran again")
