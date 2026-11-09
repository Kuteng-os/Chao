extends "res://tests/test_engine.gd"
var fixtures: Dictionary
func _initialize() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/repairs862.json"))
	fixtures=data.fixtures
	for key in fixtures:
		var c:=_compile(fixtures[key]);_check(c.get("compiled_program_hash")==data.hashes[key],"Node/native parity "+key)
	if failures: quit(1);return
	_test_smoke()
	_test_copy()
	_test_selection()
	print("REPAIRS 862: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func _test_smoke() -> void:
	var g:=_game();var me:=_rich(g)
	var c: Dictionary=fixtures.smokeUnit.duplicate(true);c.abilities=[];c.unit_class="fighter";c.appearance.emblem="fighter"
	var u: Dictionary=g._new_unit(me,_compile(c));u.born_turn=0
	var v: Dictionary=g._new_unit(1-me,_compile(_base()));v.card.definition.health=12;g._recompute(v)
	_play(g,fixtures.smokeLoss)
	u=g._unit(u.uid);v=g._unit(v.uid)
	_check(g.apply_action(me,{"type":"attack","uid":u.uid,"target_uid":v.uid}).is_empty(),"smoke attack settles")
	u=g._unit(u.uid);v=g._unit(v.uid)
	_check(u.attack==5 and v.hp==7,"smoke loss +2 applies before damage")
	g._consume_keyword(u,"core.smokescreen");g._drain_deaths();_check(u.attack==5,"no duplicate loss")
	g._effect({"op":"grant_keyword","target":"self","keyword_id":"core.smokescreen","keyword_version":1,"duration":"battle"},g._context(me,u.uid,u.card))
	g._consume_keyword(u,"core.smokescreen");g._drain_deaths();_check(u.attack==7,"regain and consume triggers again")
	var aura: Dictionary=g._new_unit(me,_compile(fixtures.smokeAura));g._checkpoint()
	_check(aura.attack==5,"keyword-based attack aura does not recurse")
	g._consume_keyword(aura,"core.smokescreen");g._checkpoint();_check(aura.attack==3,"aura disappears after loss")
	var timed: Dictionary=g._new_unit(me,_compile(_base()))
	g._effect({"op":"grant_ability","target":"self","duration":"battle","ability":fixtures.smokeUnit.abilities[0]},g._context(me,timed.uid,timed.card))
	g._effect({"op":"grant_keyword","target":"self","keyword_id":"core.smokescreen","keyword_version":1,"duration":"end_of_turn"},g._context(me,timed.uid,timed.card))
	_check(g.apply_action(me,{"type":"end_turn"}).is_empty(),"expiry settles")
	_check(g._unit(timed.uid).attack==5,"expiring smoke fires once")

func _test_copy() -> void:
	var g:=_game();var me:=_rich(g)
	var u: Dictionary=g._new_unit(me,_compile(fixtures.attackCopy));u.born_turn=0
	var v: Dictionary=g._new_unit(1-me,_compile(_base("被攻击目标")))
	var ctx: Dictionary=g._context(1-me,v.uid,v.card)
	g._effect({"op":"modify_stats","target":"self","attack_delta":2,"health_delta":2,"duration":"battle"},ctx)
	g._effect({"op":"modify_operation_cost","target":"self","cost_delta":2,"duration":"battle"},ctx)
	v.damage_taken=4;g._recompute(v)
	# Bomber cannot retaliate; target dies but its full attack/max-health snapshot survives.
	v.card.definition.unit_class="bomber"
	var n: int=g.state.players[me].hand.size()
	_check(g.apply_action(me,{"type":"attack","uid":u.uid,"target_uid":v.uid}).is_empty(),"attack-copy action settles")
	_check(g.state.players[me].hand.size()==n+1 and g._unit(v.uid).is_empty(),"dead attacked target still copied")
	var copied: Dictionary=g.state.players[me].hand.back().card
	var display:=Runtime.display_definition(copied)
	_check(display.name=="被攻击目标" and display.attack==5 and display.health==6 and display.operation_cost==3,"copy keeps full stats and costs")
	var spawned: Dictionary=g._new_unit(me,copied)
	_check(spawned.attack==5 and spawned.hp==6,"temporary copy stats apply on entry, no damage inherited")
	g._leave_battlefield(spawned,true)
	var returned: Dictionary=g.state.players[me].hand.back().card
	var reenter: Dictionary=g._new_unit(me,returned)
	_check(reenter.attack==3 and reenter.hp==4,"temporary stats not permanently retained")
	# HQ attacks have no unit copy.
	g=_game();me=_rich(g);u=g._new_unit(me,_compile(fixtures.attackCopy));u.born_turn=0
	n=g.state.players[me].hand.size();_check(g.apply_action(me,{"type":"attack","uid":u.uid,"target_uid":-1}).is_empty(),"HQ attack valid")
	_check(g.state.players[me].hand.size()==n,"HQ has no copied card")

func _test_selection() -> void:
	for count in [0,1,2]:
		var g:=_game();var me:=_rich(g)
		var first: Dictionary=g._new_unit(me,_compile(_base("玉石甲")))
		var second: Dictionary=g._new_unit(me,_compile(_base("玉石乙")))
		var other: Dictionary=g._new_unit(me,_compile(_base("普通单位")))
		_play(g,fixtures.jade)
		_check(g.state.has("pending_choice"),"multi select starts")
		_check(not other.uid in g.state.pending_choice.targets,"name filter excludes non-jade")
		_check(g.apply_action(1-me,{"type":"choose_target","choice_id":g.state.pending_choice.choice_id,"target_uid":first.uid})!="","opponent cannot choose")
		for id in [first.uid,second.uid].slice(0,count):
			_check(g.apply_action(me,{"type":"choose_target","choice_id":g.state.pending_choice.choice_id,"target_uid":id}).is_empty(),"choose next jade")
			if g.state.has("pending_choice"):_check(not id in g.state.pending_choice.targets and g.state.units.size()==3,"distinct selection, no premature destruction")
		if count<2:_check(g.apply_action(me,{"type":"choose_target","choice_id":g.state.pending_choice.choice_id,"target_uid":-1000}).is_empty(),"finish zero or one")
		_check(not g.state.has("pending_choice") and g.state.winner==-1,"selection resumes without freeze")
		_check(g.state.units.size()==3 and g.state.discard.filter(func(x):return x.card.definition.kind=="unit").size()==0,"actual destroyed count resummoned")
		_check(not g._unit(other.uid).is_empty(),"unselected unit untouched")
		_check(g.state.units.filter(func(x):return int(x.uid)>int(other.uid)).size()==count,"exactly selected count receives new instances")
	var g:=_game();var me:=_rich(g);_play(g,fixtures.jade)
	_check(not g.state.has("pending_choice") and g.state.winner==-1,"empty battlefield skips selection")
