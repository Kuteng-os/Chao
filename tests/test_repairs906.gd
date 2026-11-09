extends "res://tests/test_engine.gd"
var fixtures: Dictionary

func _initialize() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/repairs906.json"))
	fixtures=data.fixtures
	for key in fixtures:
		var c:=_compile(fixtures[key])
		_check(c.get("compiled_program_hash")==data.hashes[key],"Node/native parity "+key)
	_check(Runtime.validate_keyword(data.keyword).is_empty(),"fixed-cost position aura supported in keyword templates")
	var with_keyword: Dictionary=fixtures.plain.duplicate(true)
	with_keyword.keywords=[{"id":data.keyword.id,"version":1,"params":{}}]
	_check(Runtime.compile_card(with_keyword,[data.keyword]).ok,"keyword expands into the same supported aura")
	if failures: quit(1);return
	_test_copy_and_cost()
	_test_capacity_and_permanence()
	_test_validation()
	print("REPAIRS 906: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func _move(g: RefCounted,uid: int) -> void:
	g._unit(uid).born_turn=g.state.turn-1
	_check(g.apply_action(g.state.active_player,{"type":"move","uid":uid}).is_empty(),"active move resolves")

func _test_copy_and_cost() -> void:
	var g:=_game();var me:=_rich(g);var uid:=_play(g,fixtures.ranger)
	var source: Dictionary=g._unit(uid)
	g._effect({"op":"modify_operation_cost","target":"self","cost_delta":3,"duration":"battle"},g._context(me,uid,source.card))
	_check(g._operation_cost(source)==4,"rear uses original cost plus modifiers")
	var credits: int=g.state.players[me].credits
	_move(g,uid)
	source=g._unit(uid)
	_check(g.state.players[me].credits==credits-4,"entering front pays pre-move cost")
	_check(g._operation_cost(source)==0,"front aura is exactly zero despite additive modifiers")
	_check(g.state.units.size()==2,"move creates exactly one unit without recursive summon triggers")
	var child: Dictionary=g.state.units.back();var child_uid: int=child.uid
	_check(child.row=="support" and child.attack==7 and child.hp==7,"copy enters support with +2/+2")
	_check(source.attack==5 and source.hp==5,"copy buff does not change original")
	_check(g._operation_cost(child)==1,"copy excludes temporary source cost modifiers")
	_check(child.card.definition.abilities==source.card.definition.abilities,"copy retains all full abilities")
	_move(g,child_uid)
	_check(g.state.units.size()==3,"copy can itself generate another copy after moving")
	var next: Dictionary=g.state.units.back()
	_check(next.attack==7 and next.hp==7,"temporary copy buff is not copied into another generation")
	_check(g._operation_cost(g._unit(child_uid))==0,"copy shares frontline zero cost")
	g.state.turn+=2
	g._unit(child_uid).moved=false;g._unit(child_uid).attack_locked=false
	g.state.players[me].credits=0
	_check(g.apply_action(me,{"type":"attack","uid":child_uid,"target_uid":-1}).is_empty(),"frontline unit can attack with zero remaining credits")
	_check(g.state.players[me].credits==0,"zero-cost attack spends no credits")
	g._effect({"op":"retreat","target":"self"},g._context(me,uid,g._unit(uid).card))
	_check(g._unit(uid).row=="support" and g._operation_cost(g._unit(uid))==4,"leaving front restores costs")
	g._effect({"op":"suppress","target":"self"},g._context(me,child_uid,g._unit(child_uid).card))
	_check(g._operation_cost(g._unit(child_uid))==1,"suppression removes fixed aura")
	var copy_uid: int=next.uid
	g._effect({"op":"return_to_hand","target":"self"},g._context(me,copy_uid,next.card))
	var entry: Dictionary=g.state.players[me].hand.back()
	_check(Runtime.display_definition(entry.card).attack==5,"temporary copy buff expires on leaving")
	g.state.players[me].credits=12
	var new_uid: int=g.state.next_uid
	_check(g.apply_action(me,{"type":"play","hand_id":entry.instance_id}).is_empty(),"returned copy can redeploy")
	_check(g._unit(new_uid).attack==5 and g._unit(new_uid).hp==5,"redeployment does not restore expired copy buff")
	_check(g._unit(new_uid).card.definition.abilities.size()==2,"return preserves printed abilities")

func _test_capacity_and_permanence() -> void:
	var g:=_game();var me:=_rich(g);var uid:=_play(g,fixtures.permanent)
	_move(g,uid)
	var child: Dictionary=g.state.units.back()
	_check(child.attack==7 and child.card.get("match_layers",[]).size()==1,"explicit permanent copy buff is saved once")
	_move(g,child.uid)
	_check(g.state.units.back().attack==9,"explicit permanent bonus is inherited then new bonus added once")
	while g._count_row(me,"support")<4:
		_play(g,fixtures.plain)
	var before: int=g.state.units.size()
	g._transfer_card(fixtures.ranger.abilities[0].effects[0],g._context(me,uid,g._unit(uid).card))
	_check(g.state.units.size()==before and g._fault.is_empty(),"full support skips copy cleanly")
	_check(not g.state.has("pending_choice"),"no phantom selection after blocked copy")

func _test_validation() -> void:
	var bad: Dictionary=fixtures.ranger.duplicate(true)
	bad.abilities[1].effects[0]["cost_delta"]=-1
	_check(not Runtime.compile_card(bad,[]).ok,"set and delta are mutually exclusive")
	bad=fixtures.ranger.duplicate(true);bad.abilities[1].premise.state="has_attacked"
	_check(not Runtime.compile_card(bad,[]).ok,"unsafe state aura rejected")
	bad=fixtures.ranger.duplicate(true);bad.abilities[0].effects[0].destination="hand"
	_check(not Runtime.compile_card(bad,[]).ok,"copy buff cannot silently apply to unsupported destination")
	bad=fixtures.ranger.duplicate(true);bad.abilities[1].premise={"test":"not","item":{"test":"unit_state","target":"self","state":"in_support"}}
	_check(Runtime.compile_card(bad,[]).ok,"nested position premise supported")
