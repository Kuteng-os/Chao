extends "res://tests/test_engine.gd"

func _initialize() -> void:
	_events_and_damage()
	_transfers()
	_auras_and_combat()
	_delayed()
	_hq_targets()
	print("COLLECTED MECHANICS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _buff(n: int = 1, h: int = 1) -> Dictionary:
	return {"op":"modify_stats","target":"self","attack_delta":n,"health_delta":h,"duration":"battle"}

func _transfer(source: String, destination: String, mode: String = "copy") -> Dictionary:
	return {"op":"transfer_card","source":source,"destination":destination,"mode":mode,"selection":"random","amount":1}

func _events_and_damage() -> void:
	var g := _game()
	var seat := _rich(g)
	var s := _base("首次加成")
	s.abilities=[{"trigger":"own_unit_deployed","limit":1,"effects":[_buff()]},{"trigger":"enemy_unit_deployed","limit":1,"effects":[_buff()]}]
	var uid:=_play(g,s)
	_check(g._unit(uid).attack==3,"own deployment doesn't consume first-other-deployment listener")
	_play(g,_base("友一")); _play(g,_base("友二"))
	_check(g._unit(uid).attack==4,"friendly first event buffs exactly once")
	g.state.active_player=1-seat
	_play(g,_base("敌一")); _play(g,_base("敌二"))
	_check(g._unit(uid).attack==5 and g._unit(uid).max_hp==6,"independent enemy listener buffs once")
	g.state.active_player=seat
	var armor:=_base("累计损伤");armor.health=20
	armor.abilities=[{"trigger":"on_damaged","damage_step":2,"effects":[{"op":"modify_stacks","target":"self","stack":"heavy_armor","amount":1,"duration":"battle"}]},{"trigger":"on_death","effects":[_transfer("self","deck")]}]
	var id:=_play(g,armor)
	var ctx: Dictionary=g._context(1-seat,-1,_compile(_base()))
	g._unit_damage(g._unit(id),1,ctx);g._checkpoint();g._drain_deaths()
	_check(g.stack_count(g._unit(id),"heavy_armor")==0,"one damage retains remainder")
	g._unit_damage(g._unit(id),4,ctx);g._checkpoint();g._drain_deaths()
	_check(g.stack_count(g._unit(id),"heavy_armor")==2,"five actual damage yields two stacks")
	g._unit(id).damage_taken=0;g._recompute(g._unit(id))
	g._unit_damage(g._unit(id),1,ctx);g._checkpoint();g._drain_deaths()
	_check(g.stack_count(g._unit(id),"heavy_armor")==3,"healing does not reset cumulative damage")
	var before: int=g.state.players[seat].deck.size()
	g._unit(id).destroyed=true;g._checkpoint();g._drain_deaths()
	_check(g.state.players[seat].deck.size()==before+1,"death copies frozen source card into deck")
	var reflect:=_base("反伤");reflect.attack=0;reflect.health=10
	reflect.abilities=[{"trigger":"on_attacked","effects":[{"op":"damage","target":"trigger_unit","amount":2}]}]
	var defender:Dictionary=g._new_unit(seat,_compile(reflect))
	var attacker:Dictionary=g._new_unit(1-seat,_compile(_base("攻击者")))
	g._resolve_combat(attacker,defender);g._checkpoint();g._drain_deaths()
	_check(g._unit(attacker.uid).hp==2,"on attacked targets attacker once before ordinary combat")
	_check(g._fault.is_empty(),"event processing remains within budget")

func _transfers() -> void:
	var g:=_game();var seat:=_rich(g)
	var a:=_base("低费");a.cost=2
	var b:=_base("最高甲");b.cost=7
	var c:=_base("最高乙");c.cost=7
	g.state.players[seat].hand=[]
	for spec in [a,b,c]:g._receive_card(seat,_compile(spec),"test")
	var op:=_transfer("hand","hand");op.selection="highest_cost"
	var order:=_base("复制","order");order.abilities=[{"trigger":"on_play","effects":[op]}]
	_play(g,order)
	_check(g.state.players[seat].hand.size()==4 and g.state.players[seat].hand.back().card.definition.cost==7,"copy highest remaining hand card excluding played card")
	g.state.players[seat].hand=[];_play(g,order)
	_check(g.state.players[seat].hand.is_empty(),"empty hand copy is a no-op")
	var f:="11111111-1111-4111-8111-111111111111"
	b["faction_id"]=f
	var frozen:=_compile(b)
	g.state.discard.append({"owner":seat,"card":frozen})
	var revive:=_base("复苏","order");op=_transfer("discard","support","move");op["filter"]={"kind":"unit","faction_id":f}
	revive.abilities=[{"trigger":"on_play","effects":[op]}]
	_play(g,revive)
	_check(g.state.units.size()==1 and g.state.units[0].card.definition_hash==frozen.definition_hash,"revive moves actual frozen matching unit")
	_check(g.state.discard.filter(func(e):return e.card.definition.name==b.name).is_empty(),"resurrect removes exactly one graveyard entry")
	var source:=_base("原位置替补");op=_transfer("deck","source_position","move");op["filter"]={"faction_id":f}
	source.abilities=[{"trigger":"on_death","effects":[op]}]
	var uid:=_play(g,source)
	var unit:Dictionary=g._unit(uid);g._remove_from_line(unit);unit.row="front";g._position_unit(unit,0)
	g.state.players[seat].deck.append(frozen)
	unit.destroyed=true;g._checkpoint();g._drain_deaths()
	_check(g.line_units(seat,"front").size()==1 and g.line_units(seat,"front")[0].card.definition.name==b.name,"faction search restores death row and insertion position")
	_check(not g.view_for(1-seat).has("starting_decks") and not g.view_for(1-seat).has("scheduled"),"private card pools and pending rules never leak")
	g=_game();seat=_rich(g)
	while g.state.players[seat].deck.size()<100:g.state.players[seat].deck.append(frozen)
	g.state.discard.append({"owner":seat,"card":frozen})
	var ctx: Dictionary=g._context(seat,-1,frozen)
	g._effect(_transfer("discard","deck","move"),ctx)
	_check(g.state.discard.size()==1 and g.state.players[seat].deck.size()==100,"full destination deck does not consume a graveyard card")

func _auras_and_combat() -> void:
	var g:=_game();var seat:=_rich(g)
	var s:=_base("前线光环")
	s.abilities=[{"trigger":"while_active","premise":{"test":"any","items":[{"test":"compare","left":{"stat":"friendly_front_count"},"cmp":"gt","right":0},{"test":"compare","left":{"stat":"enemy_front_count"},"cmp":"gt","right":0}]},"effects":[_buff(5,0)]}]
	var uid:=_play(g,s)
	_check(g._unit(uid).attack==3,"conditional aura absent with empty front")
	var u:Dictionary=g._new_unit(1-seat,_compile(_base()));g._remove_from_line(u);u.row="front";g._position_unit(u);g._checkpoint()
	_check(g._unit(uid).attack==8,"conditional aura responds to opposing front")
	g._leave_battlefield(u,false);g._checkpoint()
	_check(g._unit(uid).attack==3,"aura disappears immediately without permanent stacking")
	var eq:=_base("剑士");var delta:=_buff(0,0);delta.attack_delta={"equipment":"剑","scale":2}
	eq.abilities=[{"trigger":"while_active","effects":[delta]}]
	var eqid:=_play(g,eq);var ctx:Dictionary=g._context(seat,eqid,g._unit(eqid).card)
	g._effect({"op":"equip","target":"self","tag":"剑","amount":2},ctx);g._checkpoint()
	_check(g._unit(eqid).attack==7,"equipment aura counts matching tag times scale")
	g._effect({"op":"unequip","target":"self","tag":"剑","amount":1},ctx);g._checkpoint()
	_check(g._unit(eqid).attack==5,"unequip removes matching live bonus")
	g._suppress(g._unit(eqid));g._checkpoint()
	_check(g._unit(eqid).attack==3,"suppression clears equipment and aura")
	var rule:={"op":"set_combat_damage_multiplier","target":"self","against":"any","target_row":"front","attack_delta":10,"multiplier":1,"applies_to":"attack","duration":"battle"}
	g._effect(rule,g._context(seat,uid,g._unit(uid).card))
	u=g._new_unit(1-seat,_compile(_base()));u.row="front"
	_check(g._combat_damage(g._unit(uid),u,"attack")==13,"front-only attack increase applies in combat")
	u.row="support"
	_check(g._combat_damage(g._unit(uid),u,"attack")==3 and g._unit(uid).attack==3,"combat modifier never leaks to rear target or permanent stats")
	_check(not Runtime.rules_text(_compile(eq)).is_empty(),"equipment rules render")

func _delayed() -> void:
	for mode in [0,1,2]:
		var g:=_game();var seat:=_rich(g)
		g._new_unit(seat,_compile(_base()))
		g._new_unit(1-seat,_compile(_base()))
		if mode<2:g._new_unit(seat if mode==0 else 1-seat,_compile(_base()))
		var s:=_base("延后清场","order");s.abilities=[{"trigger":"on_play","effects":[{"op":"pin","target":"all_friendly_units","turns":1},{"op":"suppress","target":"all_friendly_units"},{"op":"pin","target":"all_enemy_units","turns":1},{"op":"suppress","target":"all_enemy_units"}]}]
		for cmp in ["gt","lt","eq"]:
			var effects:=[]
			if cmp!="lt":effects.append({"op":"destroy","target":"all_friendly_units"});effects.append({"op":"damage","target":"own_hq","amount":10})
			if cmp!="gt":effects.append({"op":"destroy","target":"all_enemy_units"});effects.append({"op":"damage","target":"enemy_hq","amount":10})
			s.abilities.append({"trigger":"next_own_turn_start","premise":{"test":"compare","left":{"stat":"friendly_unit_count"},"cmp":cmp,"right":{"stat":"enemy_unit_count"}},"effects":effects})
		_play(g,s)
		_check(g.state.units.all(func(u):return g._pinned(u) and u.suppressed),"immediate pin and suppression both apply to each side before delayed branches")
		_check(g.state.players[seat].hp==20,"delayed effect is not immediate")
		g.apply_action(seat,{"type":"end_turn"})
		_check(g.state.players[seat].hp==20,"own-next-turn ignores opponent start")
		g.apply_action(1-seat,{"type":"end_turn"})
		_check(g.state.players[seat].hp==(10 if mode!=1 else 20) and g.state.players[1-seat].hp==(10 if mode!=0 else 20),"exclusive branches snapshot counts before destruction: "+str(mode))
		_check(g.state.scheduled.is_empty(),"delayed effects consumed exactly once")
	var g:=_game();var seat:=_rich(g)
	var s:=_base("下一指令","order");var op:=_transfer("deck","hand","move");op["filter"]={"kind":"unit","event_faction":true,"event_cost_distance":1}
	s.abilities=[{"trigger":"next_own_order_played","effects":[op]}]
	_play(g,s)
	var f:="11111111-1111-4111-8111-111111111111"
	var card:=_base("同阵营近费");card["faction_id"]=f;g.state.players[seat].deck.append(_compile(card))
	var order:=_base("启动","order");order["faction_id"]=f;order.abilities=[{"trigger":"on_play","effects":[{"op":"gain_kredits","amount":1}]}]
	_play(g,order)
	_check(g.state.players[seat].hand.back().card.definition.name==card.name and g.state.scheduled.is_empty(),"next-order watcher filters by actual event card")

func _hq_targets() -> void:
	var g:=_game();var seat:=_rich(g)
	var s:=_base("任意目标","order");s.play_target={"side":"any","row":"any","include_hq":true};s.abilities=[{"trigger":"on_play","effects":[{"op":"damage","target":"chosen","amount":1}]}]
	_play(g,s,-101-seat)
	_check(g.state.players[seat].hp==19,"friendly HQ is a legal explicit chosen target")
	_play(g,s,-101-(1-seat))
	_check(g.state.players[1-seat].hp==19,"enemy HQ selected without confusing no-target sentinel")
