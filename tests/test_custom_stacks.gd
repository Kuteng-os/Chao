extends "res://tests/test_engine.gd"

func _initialize() -> void:
	_trigger_and_creator()
	_layers()
	_limits_and_errors()
	_queue_safety()
	print("CUSTOM STACKS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _fixture() -> Dictionary:
	var model_path:=OS.get_environment("FRONTLINE_CUSTOM_STACK_MODEL")
	if not model_path.is_empty():
		var rows:Array=JSON.parse_string(FileAccess.get_file_as_string(model_path))
		for row in rows:
			if row.get("kind")=="card" and row.get("pass",false):return row.compiled.definition.duplicate(true)
	var d:=_base("Luser");d.attack=1;d.health=8
	d.abilities=[{"trigger":"own_turn_start","effects":[{"op":"create_card","token_id":"pipe","player":"owner","amount":3}]},{"trigger":"on_stack_gained","stack":"high","premise":{"test":"compare","left":{"stack_count":{"target":"self","stack":"high"}},"cmp":"gte","right":3},"effects":[{"op":"set_stacks","target":"self","stack":"high","amount":0,"duration":"battle"},{"op":"modify_stats","target":"self","attack_delta":1,"health_delta":0,"duration":"battle"}]},{"trigger":"own_turn_end","effects":[{"op":"remove_hand","player":"owner","card_name":"倒管子"}]}]
	d.tokens=[{"token_id":"pipe","name":"倒管子","kind":"order","cost":1,"unit_class":null,"attack":0,"health":0,"operation_cost":0,"keywords":[],"play_target":{"side":"enemy","row":"any"},"abilities":[{"trigger":"on_play","effects":[{"op":"damage","target":"chosen","amount":{"unit_stat":{"target":"creator","stat":"attack"}}},{"op":"modify_stacks","target":"creator","stack":"high","amount":1,"duration":"battle"}]}]}]
	return d

func _trigger_and_creator() -> void:
	var g:=_game();var seat:=_rich(g);var compiled:=_compile(_fixture())
	var source:Dictionary=g._new_unit(seat,compiled);var source_id:int=source.uid
	var other:Dictionary=g._new_unit(seat,compiled);var other_id:int=other.uid
	var target_spec:=_base();target_spec.health=20;var enemy:Dictionary=g._new_unit(1-seat,_compile(target_spec));var enemy_id:int=enemy.uid
	var ctx:Dictionary=g._context(seat,source_id,source.card)
	g._effect({"op":"create_card","token_id":compiled.definition.tokens[0].token_id,"player":"owner","amount":3},ctx)
	var hand:Array=g.state.players[seat].hand
	var ids:Array=hand.filter(func(e):return e.card.definition.name=="倒管子").map(func(e):return e.instance_id)
	_check(ids.size()==3,"creates three linked orders")
	for id in ids:
		_check(g._hand(seat,id).card.creator_uid==source_id,"each order linked to exact creator")
		_check(g.apply_action(seat,{"type":"play","hand_id":id,"target_uid":enemy_id}).is_empty(),"play generated order")
	_check(g._unit(enemy_id).hp==17,"three orders read creator's current attack")
	_check(g._unit(source_id).attack==2 and g.stack_count(g._unit(source_id),"high")==0,"three gains clear counter and reward once")
	_check(g._unit(other_id).attack==1 and g.stack_count(g._unit(other_id),"high")==0,"same-name second unit is independent")
	source=g._unit(source_id);ctx=g._context(seat,source_id,source.card)
	g._effect({"op":"create_card","token_id":compiled.definition.tokens[0].token_id,"player":"owner","amount":2},ctx)
	var id:String=g.state.players[seat].hand.back().instance_id
	_check(g.apply_action(seat,{"type":"play","hand_id":id,"target_uid":enemy_id}).is_empty(),"fourth linked order")
	_check(g._unit(enemy_id).hp==15 and g.stack_count(g._unit(source_id),"high")==1,"new attack read and counter starts next cycle")
	var stale:Dictionary=g.state.players[seat].hand.back().card
	g._leave_battlefield(g._unit(source_id),true)
	var returned:Dictionary=g._new_unit(seat,g.state.players[seat].hand.back().card)
	_check(returned.uid!=source_id and g._effect_value({"unit_stat":{"target":"creator","stat":"attack"}},g._context(seat,-1,stale))==0,"leaving then reentry does not rebind old cards")
	g._run_roots(g._abilities(g._context(seat,other_id,g._unit(other_id).card),"own_turn_end"))
	_check(not g.state.players[seat].hand.any(func(e):return e.card.definition.name=="倒管子"),"named hand cleanup removes only matching cards")
	_check(g.state.players[seat].hand.size()>0,"other cards remain")
	var repeated:=_game();var owner:=_rich(repeated);var unit:Dictionary=repeated._new_unit(owner,compiled)
	for i in 90:
		repeated._reset_budget();repeated._effect({"op":"modify_stacks","stack":"high","target":"self","amount":1,"duration":"battle"},repeated._context(owner,unit.uid,unit.card));repeated._drain_deaths()
	_check(repeated._fault.is_empty() and repeated.stack_count(unit,"high")==0 and unit.attack==30,"ninety gains do not exhaust layer history and trigger thirty times")
	_check(unit.stack_layers.size()==1,"counter history compacted")

func _layers() -> void:
	var g:=_game();var seat:=_rich(g);var unit:Dictionary=g._new_unit(seat,_compile(_base()));var ctx:Dictionary=g._context(seat,unit.uid,unit.card)
	var reference:Array=[]
	for i in 160:
		g._reset_budget();var amount:int=(i*37)%199-99;var mode:String="set_stacks" if i%7==0 else "modify_stacks"
		if mode=="set_stacks":amount=absi(amount)
		if mode=="modify_stacks" and amount==0:amount=1
		var duration:String="end_of_turn" if i%5==0 else "battle"
		g._effect({"op":mode,"target":"self","stack":"蓄力","amount":amount,"duration":duration},ctx)
		reference.append({"mode":mode,"amount":amount,"duration":duration})
		var expected:=0
		for layer in reference:expected=clampi(layer.amount if layer.mode=="set_stacks" else expected+layer.amount,0,99)
		_check(g.stack_count(unit,"蓄力")==expected,"coalesced counters preserve sequential clipping")
		if i%10==9:
			reference=reference.filter(func(e):return e.duration!="end_of_turn")
			unit.stack_layers=unit.stack_layers.filter(func(e):return e.expires_turn<0)
			expected=0
			for layer in reference:expected=clampi(layer.amount if layer.mode=="set_stacks" else expected+layer.amount,0,99)
			_check(g.stack_count(unit,"蓄力")==expected,"expiry preserves surviving transformations")
	g._effect({"op":"modify_stacks","target":"self","stack":"永久计数","amount":7,"duration":"match"},ctx)
	g._effect({"op":"modify_stacks","target":"self","stack":"永久计数","amount":2,"duration":"battle"},ctx)
	g._leave_battlefield(unit,true);unit=g._new_unit(seat,g.state.players[seat].hand.back().card)
	_check(g.stack_count(unit,"永久计数")==7 and g.stack_count(unit,"蓄力")==0,"only permanent counter survives reentry")
	g._suppress(unit);_check(g.stack_count(unit,"永久计数")==0,"suppression clears counters")
	var missing:Dictionary=g._context(seat,-1,unit.card)
	_check(not g._premise_met({"test":"not","item":{"test":"compare","left":{"stack_count":{"target":"creator","stack":"high"}},"cmp":"gte","right":3}},missing),"missing creator invalidates negated counter premise")

func _limits_and_errors() -> void:
	var d:=_fixture();d.abilities[1].stack=" high ";_check(not Runtime.compile_card(d,Runtime.builtin_keywords()).ok,"trimmed counter names required")
	d=_fixture();d.abilities[1].effects[0].stack="heavy_armor";d.abilities[1].effects[0].amount=101;_check(not Runtime.compile_card(d,Runtime.builtin_keywords()).ok,"armor remains bounded at one hundred")
	_check(Runtime.rules_text(_compile(_fixture())).contains("high"),"rules show custom counter name")

func _queue_safety() -> void:
	var g:=_game();var seat:=_rich(g);var d:=_fixture();var unit:Dictionary=g._new_unit(seat,_compile(d));var ctx:Dictionary=g._context(seat,unit.uid,unit.card)
	for i in 3:g._effect({"op":"modify_stacks","stack":"high","target":"self","amount":1,"duration":"battle"},ctx)
	g._drain_deaths()
	_check(unit.attack==2 and g.stack_count(unit,"high")==0,"queued gains recheck threshold and reward only once")
	g._effect({"op":"set_stacks","stack":"high","target":"self","amount":0,"duration":"battle"},ctx)
	_check(g._events.is_empty(),"setting unchanged zero emits no gain event")
	var cap:=_base();cap.abilities=[{"trigger":"on_stack_gained","stack":"heavy_armor","effects":[{"op":"modify_stats","target":"self","attack_delta":1,"health_delta":0,"duration":"battle"}]}]
	var armored:Dictionary=g._new_unit(seat,_compile(cap));var armor_ctx:Dictionary=g._context(seat,armored.uid,armored.card)
	g._effect({"op":"set_stacks","stack":"heavy_armor","target":"self","amount":100,"duration":"battle"},armor_ctx);g._drain_deaths()
	var attack:int=armored.attack
	g._effect({"op":"modify_stacks","stack":"heavy_armor","target":"self","amount":1,"duration":"battle"},armor_ctx);g._drain_deaths()
	_check(armored.attack==attack,"capped armor does not emit an extra gain")
	var looping:=_base();looping.abilities=[{"trigger":"on_stack_gained","stack":"loop","effects":[{"op":"set_stacks","stack":"loop","target":"self","amount":0,"duration":"battle"},{"op":"modify_stacks","stack":"loop","target":"self","amount":1,"duration":"battle"}]}]
	var safe:=_game();var owner:=_rich(safe);var source:Dictionary=safe._new_unit(owner,_compile(looping))
	safe._effect({"op":"modify_stacks","stack":"loop","target":"self","amount":1,"duration":"battle"},safe._context(owner,source.uid,source.card));safe._drain_deaths()
	_check(safe._fault=="RULE_BUDGET_EXCEEDED","recursive counter chain stops at the rule budget")
