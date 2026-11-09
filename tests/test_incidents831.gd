extends "res://tests/test_engine.gd"

func _initialize() -> void:
	_first_strike()
	_actions_and_classes()
	_death_listeners()
	_marks()
	_unused_tokens()
	_real_generated_cards()
	print("INCIDENTS 831: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _rule(op: String, extra: Dictionary = {}) -> Dictionary:
	var r := {"op":op,"target":"self","duration":"battle"}
	r.merge(extra,true)
	return r

func _unit_with(g: RefCounted, owner: int, name: String, rules: Array, kind := "tank") -> Dictionary:
	var d := _base(name);d.unit_class=kind;d.appearance.emblem=kind
	if not rules.is_empty(): d.abilities=[{"trigger":"on_play","effects":rules}]
	var u:Dictionary=g._new_unit(owner,_compile(d))
	g._initialize_summoned_unit(u)
	u.born_turn=0
	return u

func _first_strike() -> void:
	for side in [0,1,2]:
		var g := _game();var seat := _rich(g)
		var first := _rule("set_combat_priority",{"applies_to":"both"})
		var a := _unit_with(g,seat,"先手甲",[first] if side in [0,2] else [])
		var b := _unit_with(g,1-seat,"先手乙",[first] if side in [1,2] else [])
		a.card.definition.attack=5;b.card.definition.attack=5;g._recompute(a);g._recompute(b)
		g._resolve_combat(a,b);g._checkpoint();g._drain_deaths()
		_check(g.state.units.size()==(0 if side==2 else 1),"first strike kill prevents second hit; equal priority simultaneous")
		if side!=2:_check(g.state.units[0].uid==(a.uid if side==0 else b.uid),"correct priority survivor")
	var g := _game();var seat := _rich(g)
	var a := _unit_with(g,seat,"攻击者",[])
	var b := _unit_with(g,1-seat,"先手轰炸机",[_rule("set_combat_priority",{"applies_to":"both"})],"bomber")
	g._resolve_combat(a,b)
	_check(a.hp==4,"first strike never creates bomber retaliation")
	var armor := _unit_with(g,1-seat,"重甲",[_rule("modify_stacks",{"stack":"heavy_armor","amount":2})])
	g._resolve_combat(a,armor)
	_check(armor.hp==3,"armor still reduces combat damage")

func _actions_and_classes() -> void:
	var g := _game();var seat := _rich(g)
	var d := _base("驯鹿");d.abilities=[{"trigger":"on_play","effects":[_rule("grant_unit_class",{"unit_class":"fighter"})]},{"trigger":"after_action","effects":[_rule("modify_operation_cost",{"cost_delta":2})]}]
	var id := _play(g,d);var u:Dictionary=g._unit(id);u.born_turn=0
	_check(g._matches_class(u,{"unit_classes":["fighter"]}) and g._matches_class(u,{"unit_classes":["tank"]}),"both identities queryable")
	_check(g._premise_value({"count_units":{"side":"ally","row":"any","unit_classes":["tank","fighter"]}},g._context(seat,id,u.card))==1,"multiclass union counts once")
	_check(g._card_filter(u.card,{"unit_class":"fighter"}),"hand/deck filter sees static identity")
	_check(g.can_move(id),"main tank movement preserved")
	var c:int=g.state.players[seat].credits
	_check(g.apply_action(seat,{"type":"move","uid":id}).is_empty(),"move completes")
	u=g._unit(id)
	_check(g.state.players[seat].credits==c-1 and u.operation_cost==3,"move pays old cost, after-action raises next cost")
	c=g.state.players[seat].credits
	_check(g.apply_action(seat,{"type":"attack","uid":id,"target_uid":-1}).is_empty(),"attack HQ completes")
	u=g._unit(id)
	_check(g.state.players[seat].credits==c-3 and u.operation_cost==5,"attack pays raised cost, may exceed old four cap")
	g._suppress(u)
	_check(not g._matches_class(u,{"unit_classes":["fighter"]}) and u.operation_cost==1,"suppression clears identities and cost buffs")

func _death_listeners() -> void:
	for simultaneous in [false,true]:
		var g := _game();var seat := _rich(g)
		var d := _base("孵化场");d.abilities=[{"trigger":"own_unit_died","effects":[{"op":"draw","player":"owner","amount":1},{"op":"gain_kredits","amount":1}]}]
		var listener:Dictionary=g._new_unit(seat,_compile(d));var victim:=_unit_with(g,seat,"牺牲",[])
		g.state.players[seat].credits=0
		var before:int=g.state.players[seat].deck.size()
		victim["destroyed"]=true
		if simultaneous: listener["destroyed"]=true
		g._checkpoint();g._drain_deaths()
		_check(g.state.players[seat].credits==(2 if simultaneous else 1),"death listeners snapshot simultaneous batch including self")
		_check(g.state.players[seat].deck.size()==before-(2 if simultaneous else 1),"draw once for each death")
		_check(g._fault.is_empty(),"death chain has no runtime fault")

func _marks() -> void:
	var g := _game();var seat := _rich(g)
	var u:=_unit_with(g,1-seat,"标记目标",[])
	var mark:=_base("战术集火","order");mark.play_target={"side":"enemy","row":"any"};mark.abilities=[{"trigger":"on_play","effects":[_rule("modify_incoming_damage",{"target":"chosen","amount":2,"damage_kind":"both","duration":"end_of_turn"}),_rule("grant_order_target_reward",{"target":"chosen","amount":1,"duration":"end_of_turn"})]}]
	_play(g,mark,u.uid)
	_check(g.state.players[seat].credits==11,"marking order does not reward itself")
	var order:=_base("射击","order");order.play_target={"side":"enemy","row":"any"};order.abilities=[{"trigger":"on_play","effects":[{"op":"damage","target":"chosen","amount":1}]}]
	_play(g,order,u.uid)
	u=g._unit(u.uid)
	_check(u.hp==1 and g.state.players[seat].credits==12,"later order rewards caster and damage plus two")
	g._reset_budget();g._resolution_id="different";g.state.players[seat].credits=0
	g._order_target_reward(seat,u.uid,_compile(order));g._order_target_reward(seat,u.uid,_compile(order))
	_check(g.state.players[seat].credits==1,"same order same target reward deduplicated")
	g._order_target_reward(1-seat,u.uid,_compile(order))
	_check(g.state.players[seat].credits==1,"enemy order gives no reward")
	_check(g._incoming_damage(u,0,"combat")==0,"vulnerability does not create zero-base damage")
	g._end_turn()
	_check(g._unit(u.uid).extra_rules.is_empty(),"marks expire at end of marked turn")
	# HQs use the same chosen-target contract and duration.
	mark.play_target={"side":"enemy","row":"any","include_hq":true}
	var seat2:int=g.state.active_player
	_play(g,mark,-101-(1-seat2))
	_check(g.state.players[1-seat2].extra_rules.size()==2,"HQ may receive marks")

func _unused_tokens() -> void:
	var d:=_base("司令");var token:=_base("待用衍生")
	for key in ["schema_version","ruleset_version","appearance","tokens"]:token.erase(key)
	token["token_id"]="unused"
	d.tokens=[token]
	_check(Runtime.compile_card(d,Runtime.builtin_keywords()).ok,"unreferenced derived template can be saved")

func _real_generated_cards() -> void:
	var path := OS.get_environment("INCIDENT831_MODELS")
	if path.is_empty(): return
	var records: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	for row in records:
		if not row.has("compiled"): continue
		var compiled := _compile(row.compiled.definition)
		_check(compiled.compiled_program_hash == row.compiled.compiled_program_hash,"real model compiles identically: "+row.name)
		var g := _game();var seat := _rich(g)
		if compiled.definition.kind == "unit":
			var uid := _play(g,row.compiled.definition)
			var u: Dictionary = g._unit(uid)
			if row.name == "交战先手": _check(g._strikes_first(u,"retaliation"),"generated priority initializes")
			if row.name == "行动加费":
				_check(g._matches_class(u,{"unit_classes":["fighter"]}),"generated extra class initializes")
				var before: int = u.operation_cost
				g._complete_action(u,"move")
				_check(u.operation_cost == before+2,"generated after-action cost runs")
			if row.name == "阵亡监听":
				var v := _unit_with(g,seat,"阵亡测试",[])
				var before: int = g.state.players[seat].deck.size()
				v["destroyed"]=true;g._checkpoint();g._drain_deaths()
				_check(g.state.players[seat].deck.size()==before-1,"generated death listener runs")
		else:
			var u := _unit_with(g,1-seat,"标记",[])
			_play(g,row.compiled.definition,u.uid)
			_check(g._unit(u.uid).extra_rules.size()==2,"generated targeted marks run")
		_check(g._fault.is_empty(),"real generated card resolves")
