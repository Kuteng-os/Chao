extends "res://tests/test_engine.gd"

func _initialize() -> void:
	for seat in [0,1]:
		_orders(seat)
		_choices(seat)
		_bound(seat)
		_automatic(seat)
		_grants(seat)
	_derived()
	print("UNTARGETABLE838: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _protected() -> Dictionary:
	var d:=_base("不可指定目标");d.health=20
	d.keywords=[{"id":"core.untargetable","version":1,"params":{}}]
	return d

func _order(side: String = "enemy") -> Dictionary:
	var d:=_base("指定伤害","order")
	d.play_target={"side":side,"row":"any"}
	d.abilities=[{"trigger":"on_play","effects":[{"op":"damage","target":"chosen","amount":1},{"op":"draw","player":"owner","amount":1}]}]
	return d

func _hold(g: RefCounted,d: Dictionary) -> Dictionary:
	g._receive_card(g.state.active_player,_compile(d),"test")
	return {"type":"play","hand_id":g.state.players[g.state.active_player].hand.back().instance_id}

func _orders(seat: int) -> void:
	var g:=_game();g.state.active_player=seat;_rich(g)
	var ally:Dictionary=g._new_unit(seat,_compile(_protected()))
	var enemy:Dictionary=g._new_unit(1-seat,_compile(_protected()))
	for side in ["ally","enemy","any"]:
		var a:=_hold(g,_order(side));var original:=Runtime.sha(g.state)
		_check(g.legal_targets(seat,a)==[-1],"only protected targets auto skip: "+side)
		a.target_uid=ally.uid if side=="ally" else enemy.uid
		_check(not g.apply_action(seat,a).is_empty() and Runtime.sha(g.state)==original,"forged protected target rejected atomically")
		a.target_uid=-1
		var deck_count:int=g.state.players[seat].deck.size()
		_check(g.apply_action(seat,a).is_empty(),"no legal target can still play")
		_check(g.state.players[seat].deck.size()==deck_count-1 and g._unit(enemy.uid).hp==20,"unrelated draw resolves without hurting protected unit")
	var normal:Dictionary=g._new_unit(1-seat,_compile(_base()))
	var a:=_hold(g,_order())
	_check(g.legal_targets(seat,a)==[normal.uid],"normal target still selectable and required")
	a.target_uid=-1
	_check(not g.apply_action(seat,a).is_empty(),"cannot skip while legal normal target exists")
	var attacker:=_base("炮兵");attacker.unit_class="artillery";attacker.keywords=[{"id":"core.blitz","version":2,"params":{}}]
	var u:Dictionary=g._new_unit(seat,_compile(attacker))
	_check(enemy.uid in g.legal_targets(seat,{"type":"attack","uid":u.uid}),"ordinary attack can target protected unit")
	_check(g.apply_action(seat,{"type":"attack","uid":u.uid,"target_uid":enemy.uid}).is_empty(),"ordinary attack executes")
	_check(g._unit(enemy.uid).hp==17,"attack actually damages")

func _choices(seat: int) -> void:
	var g:=_game();g.state.active_player=seat;_rich(g)
	var protected:Dictionary=g._new_unit(1-seat,_compile(_protected()))
	var normal:Dictionary=g._new_unit(1-seat,_compile(_base()))
	var d:=_base("技能选择")
	d.abilities=[{"trigger":"on_play","target":{"side":"enemy","row":"any","timing":"trigger"},"effects":[{"op":"damage","target":"chosen","amount":1}]}]
	_play(g,d)
	_check(g.state.pending_choice.targets==[normal.uid],"skill prompt excludes protected unit")
	var id:String=g.state.pending_choice.choice_id
	var before:=Runtime.sha(g.state)
	_check(not g.apply_action(seat,{"type":"choose_target","choice_id":id,"target_uid":protected.uid}).is_empty() and Runtime.sha(g.state)==before,"malicious pending selection rejected")
	var restored:=EngineClass.new();restored.state=g.state.duplicate(true)
	_check(restored.apply_action(seat,{"type":"choose_target","choice_id":id,"target_uid":normal.uid}).is_empty(),"choice survives server snapshot restoration")
	_check(restored._unit(normal.uid).hp==3 and restored._unit(protected.uid).hp==20,"choice replay affects only legal target")

func _bound(seat: int) -> void:
	var g:=_game();g.state.active_player=seat;_rich(g)
	var target:Dictionary=g._new_unit(1-seat,_compile(_base()))
	var d:=_base("绑定目标")
	d.abilities=[{"trigger":"on_death","target":{"side":"enemy","row":"any"},"effects":[{"op":"damage","target":"chosen","amount":2},{"op":"draw","player":"owner","amount":1}]}]
	var source:=_play(g,d)
	_check(g.apply_action(seat,{"type":"choose_target","choice_id":g.state.pending_choice.choice_id,"target_uid":target.uid}).is_empty(),"bind normal target")
	var grant:=_base("赋予保护","order")
	grant.abilities=[{"trigger":"on_play","effects":[{"op":"grant_keyword","target":"all_enemy_units","keyword_id":"core.untargetable","keyword_version":1,"duration":"battle"}]}]
	_play(g,grant)
	var kill:=_order("ally");kill.abilities=[{"trigger":"on_play","effects":[{"op":"destroy","target":"chosen"}]}]
	var count:int=g.state.players[seat].deck.size()
	_play(g,kill,source)
	_check(g._unit(target.uid).hp==4 and not g.state.has("pending_choice"),"bound target now protected fizzles without reselect")
	_check(g.state.players[seat].deck.size()==count-1,"bound non-targeted effects continue")

func _automatic(seat: int) -> void:
	for mode in ["all_enemy_units","random_enemy_unit","trigger_unit","creator","self","adjacent_to_self","adjacent_to_chosen"]:
		var g:=_game();g.state.active_player=seat;_rich(g)
		var owner:int=seat if mode in ["self","adjacent_to_self","adjacent_to_chosen"] else 1-seat
		var target:Dictionary=g._new_unit(owner,_compile(_protected()))
		var source:Dictionary=g._new_unit(seat,_compile(_base()))
		if mode.begins_with("adjacent"):
			g._remove_from_line(source);g._position_unit(source,g.line_order(seat,"support").find(target.uid)+1)
		var context:Dictionary=g._context(seat,target.uid if mode=="self" else source.uid,source.card,source.uid)
		context.trigger_unit=target.uid
		context.card["creator_uid"]=target.uid
		g._effect({"op":"damage","target":mode,"amount":1},context)
		_check(g._unit(target.uid).hp==19,"automatic effect still hits: "+mode)
	# Non-targeted suppression clears the printed protection.
	var g:=_game();g.state.active_player=seat;_rich(g)
	var target:Dictionary=g._new_unit(1-seat,_compile(_protected()))
	var d:=_base("群体抑制","order");d.abilities=[{"trigger":"on_play","effects":[{"op":"suppress","target":"all_enemy_units"}]}]
	_play(g,d)
	_check(target.uid in g.legal_targets(seat,_hold(g,_order())),"area suppression removes immunity")

func _grants(seat: int) -> void:
	var g:=_game();g.state.active_player=seat;_rich(g)
	var target:Dictionary=g._new_unit(1-seat,_compile(_base()))
	var d:=_base("回合保护","order");d.abilities=[{"trigger":"on_play","effects":[{"op":"grant_keyword","target":"all_enemy_units","keyword_id":"core.untargetable","keyword_version":1,"duration":"end_of_turn"}]}]
	_play(g,d)
	_check(g.legal_targets(seat,_hold(g,_order()))==[-1],"temporary granted protection applies")
	g.apply_action(seat,{"type":"end_turn"});g.apply_action(1-seat,{"type":"end_turn"});_rich(g)
	_check(target.uid in g.legal_targets(seat,_hold(g,_order())),"grant expiration restores selection")

func _derived() -> void:
	var parent:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/kill837_card.json"))
	parent.abilities[0].premise={"test":"compare","left":{"unit_stat":{"target":"chosen","stat":"health"}},"cmp":"gt","right":0}
	parent.tokens[0].keywords=[{"id":"core.untargetable","version":1,"params":{}}]
	var g:=_game();var owner:=_rich(g)
	var sacrifice:Dictionary=g._new_unit(owner,_compile(_base()))
	_play(g,parent,sacrifice.uid)
	var source:Dictionary=g.state.units[0]
	_check(source.card.definition.name=="luser" and g._has_keyword(source,"core.untargetable"),"report76 summoned luser preserves protection")
	_check(g.legal_targets(owner,_hold(g,_order("ally")))==[-1],"summoned luser cannot be selected by friendly order")
	_play(g,parent)
	_check(g.state.units.size()==1,"protected ally cannot satisfy sacrifice or grant a free summon")
	g.apply_action(owner,{"type":"end_turn"});g.apply_action(1-owner,{"type":"end_turn"})
	_check(g.state.players[owner].hand.filter(func(e):return e.card.definition.name=="倒灌").size()==3,"protection does not disable turn-start generation")
