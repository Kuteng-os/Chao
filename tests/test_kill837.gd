extends "res://tests/test_engine.gd"

func _initialize() -> void:
	for seat in [0,1]:
		for row in ["support","front"]:
			_run_chain(seat,row)
		_not_lethal(seat)
	print("KILL837: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _fixture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/kill837_card.json"))

func _run_chain(seat: int, row: String) -> void:
	var g:=_game();g.state.active_player=seat;_rich(g);g.state.players[seat].hand=[]
	var parent:=_fixture()
	_play(g,parent)
	_check(g.state.units.is_empty(),"no friendly target means no sacrifice or summon")
	var ally:Dictionary=g._new_unit(seat,_compile(_base("祭品")))
	_play(g,parent,ally.uid)
	_check(g._unit(ally.uid).is_empty(),"sacrifice dies")
	var source:Dictionary=g.state.units[0]
	_check(source.card.definition.name=="luser" and source.owner==seat,"luser summoned on correct side")
	g.apply_action(seat,{"type":"end_turn"});g.apply_action(1-seat,{"type":"end_turn"});_rich(g)
	var orders:Array=g.state.players[seat].hand.filter(func(e):return e.card.definition.name=="倒灌")
	_check(orders.size()==3,"turn start generates three actual orders")
	_check(orders[0].card.creator_uid==source.uid,"order remembers its generating luser")
	# A full support line does not block replacement on the front line.
	var enemy:=_base("敌方目标");enemy.health=1
	var target:Dictionary=g._new_unit(1-seat,_compile(enemy))
	if row=="front":
		g._remove_from_line(target);target.row="front";g._position_unit(target,0)
		for i in 4:g._new_unit(1-seat,_compile(_base("后援"+str(i))))
	else:
		for i in 3:g._new_unit(1-seat,_compile(_base("同线"+str(i))))
	var slot:int=g.line_order(1-seat,row).find(target.uid)
	_check(g.apply_action(seat,{"type":"play","hand_id":orders[0].instance_id,"target_uid":target.uid}).is_empty(),"generated order resolves lethal damage")
	_check(g._unit(target.uid).is_empty(),"victim removed normally")
	var replacements:Array=g.state.units.filter(func(u):return u.card.definition.name=="津液")
	_check(replacements.size()==1,"only one replacement summoned")
	if replacements.size()!=1:return
	var replacement:Dictionary=replacements[0]
	_check(replacement.owner==1-seat and replacement.row==row,"victim owner and row preserved")
	_check(g.line_order(1-seat,row).find(replacement.uid)==slot,"victim's exact position preserved")
	_check(replacement.attack==1 and replacement.hp==1 and replacement.operation_cost==1,"correct derived unit stats")
	_check(g._unit(source.uid).attack==2,"luser aura reacts to enemy replacement immediately")
	# Creator gone: its previously generated orders resolve for zero, never kill.
	g._leave_battlefield(g._unit(source.uid),false)
	_check(g.apply_action(seat,{"type":"play","hand_id":orders[1].instance_id,"target_uid":replacement.uid}).is_empty(),"orphaned order resolves normally")
	_check(not g._unit(replacement.uid).is_empty() and g._unit(replacement.uid).hp==1,"missing creator means zero damage, no replacement")

func _not_lethal(seat: int) -> void:
	for immune in [false,true]:
		var g:=_game();g.state.active_player=seat;_rich(g)
		var parent:=_compile(_fixture())
		var source:Dictionary=g._new_unit(seat,g._generated_card(parent,"luser"),"luser")
		var d:=_base("不应触发");d.health=1 if immune else 4
		if immune:d.keywords=[{"id":"core.immune","version":1,"params":{}}]
		var victim:Dictionary=g._new_unit(1-seat,_compile(d))
		var order:Dictionary=g._generated_card(source.card,"daoguan",source.uid)
		g._receive_card(seat,order,"test")
		_check(g.apply_action(seat,{"type":"play","hand_id":g.state.players[seat].hand.back().instance_id,"target_uid":victim.uid}).is_empty(),"nonlethal or immune target resolves")
		_check(g.state.units.size()==2 and not g._unit(victim.uid).is_empty(),"nonlethal/immune damage cannot summon replacement")
		_check(g._unit(victim.uid).hp==(1 if immune else 3),"damage remains ordinary effect damage")
