extends "res://tests/test_engine.gd"
var f: Dictionary
func _initialize() -> void:
	f=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/repairs858.json"))
	var hashes: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/parity858.json"))
	var compiled:=_compile(f)
	_check(compiled.get("compiled_program_hash")==hashes.parent,"parent Node/native parity")
	var derived:=_child()
	_check(_compile(derived).get("compiled_program_hash")==hashes.child,"derived Node/native parity")
	if failures: quit(1);return
	_invalid_scope()
	for source in ["deck","discard","hand","none"]: _fallback(source)
	_full_hand()
	_flow()
	print("REPAIRS 858: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)

func _child() -> Dictionary:
	var d: Dictionary=f.duplicate(true);d.name="峥嵘岁月";d.cost=3;d.tokens=[];d.abilities=f.tokens[0].abilities.duplicate(true);return d

func _tank(name: String, sin_value: Variant="gloom", cls: String="tank") -> Dictionary:
	var d:=_base(name);d["sin"]=sin_value;d.unit_class=cls;d.appearance.emblem=cls;return _compile(d)

func _invalid_scope() -> void:
	var d:=_child();var direct: Dictionary=d.abilities[0].effects[0].effects[0].duplicate(true)
	d.abilities[0].effects=[direct]
	_check(not Runtime.compile_card(d,Runtime.builtin_keywords()).ok,"on_play cannot directly address trigger unit")
	for trigger in ["next_own_turn_start","next_own_order_played"]:
		d=_child();d.abilities[0].effects[0].trigger=trigger;d.abilities[0].effects[0].repeat="each_turn" if trigger=="next_own_turn_start" else "each_event"
		_check(not Runtime.compile_card(d,Runtime.builtin_keywords()).ok,"scheduled event without unit rejected "+trigger)
	for patch in [{"fallback_sources":[]},{"fallback_sources":["deck"]},{"fallback_sources":["discard","discard"]},{"mode":"move"},{"destination":"deck"},{"source":"self"},{"filter":{"sin":"wrong"}}]:
		d=_child();d.abilities[0].effects[1].merge(patch,true)
		_check(not Runtime.compile_card(d,Runtime.builtin_keywords()).ok,"invalid fallback rejected "+str(patch))

func _fallback(source: String) -> void:
	var g:=_game();var me:=_rich(g)
	var wrong:=_tank("红坦克","wrath");var infantry:=_tank("忧郁步兵","gloom","infantry");var blank:=_tank("空罪孽",null)
	var deck:=_tank("牌库坦克");var grave:=_tank("弃牌坦克");var hand:=_tank("手牌坦克");var enemy:=_tank("敌方坦克")
	g.state.players[me].deck=[wrong,infantry,blank]
	g.state.players[me].hand=[];g.state.discard=[{"owner":1-me,"card":enemy}]
	if source=="deck":g.state.players[me].deck.append(deck)
	if source in ["deck","discard"]:g.state.discard.append({"owner":me,"card":grave})
	if source!="none":g.state.players[me].hand.append({"instance_id":"original","card":hand})
	var before: Dictionary=g.state.duplicate(true)
	var effect: Dictionary=f.tokens[0].abilities[0].effects[1]
	g._effect(effect,g._context(me,-1,_compile(_child())))
	_check(g.state.players[me].deck==before.players[me].deck,"copy leaves source deck unchanged "+source)
	_check(g.state.discard==before.discard,"copy leaves both discard piles unchanged "+source)
	var size: int=before.players[me].hand.size()
	_check(g.state.players[me].hand.size()==size+(0 if source=="none" else 1),"exactly one copy or none "+source)
	if source!="none":
		var expected: String={"deck":"牌库坦克","discard":"弃牌坦克","hand":"手牌坦克"}[source]
		_check(g.state.players[me].hand.back().card.definition.name==expected,"strict region precedence "+source)
		_check(g.state.players[me].hand.back().instance_id!="original","new hand instance")
	_check(g.state.players[me].fatigue==before.players[me].fatigue,"missing match does not cause fatigue")
	_check(g.view_for(1-me).players[me].hand.is_empty(),"copies remain hidden from opponent")
	_check(g._transfer_matches(blank,{"sin":null},{},false),"explicit blank sin matches")
	_check(not g._transfer_matches(deck,{"sin":null},{},false),"blank sin filter excludes assigned sins")

func _full_hand() -> void:
	var g:=_game();var me:=_rich(g);var d:=_tank("满手牌测试")
	g.state.players[me].deck=[d];g.state.players[me].hand=[]
	for i in 10:g.state.players[me].hand.append({"instance_id":"full"+str(i),"card":d})
	var burnt: int=g.state.players[me].burned.size()
	g._effect(f.tokens[0].abilities[0].effects[1],g._context(me,-1,_compile(_child())))
	_check(g.state.players[me].hand.size()==10 and g.state.players[me].burned.size()==burnt+1,"full hand burns one copy only")
	_check(g.state.players[me].deck.size()==1,"burning copy preserves source")

func _flow() -> void:
	var g:=_game();var me:=_rich(g);var tank:=_tank("原坦克");var not_tank:=_tank("步兵","gloom","infantry")
	g.state.players[me].hand=[];g.state.players[me].deck=[tank,not_tank]
	_play(g,f)
	_check(g.state.players[me].deck==[not_tank],"parent draws matching tank, not arbitrary top card")
	_check(g.state.players[me].hand.size()==2,"parent draws tank and generates derived order")
	var child_entry: Dictionary=g.state.players[me].hand.back()
	_check(child_entry.card.definition.name=="峥嵘岁月" and child_entry.card.definition.cost==3,"3-cost derived card generated")
	var existing: Dictionary=g._new_unit(me,tank);g._initialize_deployed_unit(existing);g._drain_deaths()
	var error: String=g.apply_action(me,{"type":"play","hand_id":child_entry.instance_id})
	_check(error.is_empty(),"generated order plays "+error)
	_check(existing.attack==3,"listener does not retroactively buff existing tanks")
	_check(g.state.players[me].hand.size()==2,"no deck match falls back to hand exactly once")
	for owner in [1-me,me]:
		var new_unit: Dictionary=g._new_unit(owner,tank);g._initialize_deployed_unit(new_unit);g._drain_deaths()
		_check(new_unit.attack==(4 if owner==me else 3),"only friendly deployments get +1/+1")
		if owner==me:
			_check(new_unit.hp==5,"buff includes health")
			var departed: Dictionary=g._departure_card(new_unit.card)
			var again: Dictionary=g._new_unit(me,departed)
			_check(again.attack==4,"match enhancement survives departure")
	var infantry: Dictionary=g._new_unit(me,not_tank);g._initialize_deployed_unit(infantry);g._drain_deaths()
	_check(infantry.attack==3,"friendly non-tank excluded")
	var summoned: Dictionary=g._new_unit(me,tank,"",true);g._initialize_summoned_unit(summoned);g._drain_deaths()
	_check(summoned.attack==3,"summoning excluded from deployment listener")
	g.state.turn+=2
	var second: Dictionary=g._new_unit(me,tank);g._initialize_deployed_unit(second);g._drain_deaths()
	_check(second.attack==4,"listener repeats across turns after source order departed")
