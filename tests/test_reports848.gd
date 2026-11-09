extends "res://tests/test_engine.gd"
var fixtures: Array
func _initialize() -> void:
	fixtures=JSON.parse_string(FileAccess.get_file_as_string("res://tests/reports848.json")).cards
	for f in fixtures:
		var compiled:=_compile(f.definition)
		if compiled.ok: _check(compiled.compiled_program_hash==f.compiled_program_hash,"Node/Godot parity")
	_ignite();_rhino();_evolution();_counter()
	print("REPORTS848: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func _tick(g: RefCounted, owner: int) -> void:
	g.state.turn+=2;g.state.active_player=owner;g._reset_budget();g._run_roots(g._scheduled_roots("turn_start",owner))
func _ignite() -> void:
	var g:=_game();var p:=_rich(g);var d:=_base("原目标");d.health=10
	var u:Dictionary=g._new_unit(1-p,_compile(d));var uid:int=u.uid;_play(g,fixtures[0].definition,uid);u=g._unit(uid)
	_check(u.hp==10 and g.state.scheduled.size()==1,"no initial hit; one repeat registered")
	_tick(g,1-p);_check(u.hp==10,"opponent turn not eligible")
	_tick(g,p);_check(u.hp==7 and not g.state.has("pending_choice"),"first turn retains original target without prompt")
	g._remove_from_line(u);u.row="front";g._position_unit(u)
	_tick(g,p);_check(u.hp==4,"target follows same instance across rows")
	g._leave_battlefield(u,true);var replacement:Dictionary=g._new_unit(1-p,_compile(d))
	_tick(g,p);_check(replacement.hp==10 and g.state.scheduled.is_empty(),"leaving cancels, same named reentry untouched")
	# A missed target does not cancel unrelated immediate results.
	g=_game();p=_rich(g);d=fixtures[0].definition.duplicate(true);d.abilities[0].effects.append({"op":"gain_hq_defense","player":"owner","amount":1})
	_play(g,d);_check(g.state.players[p].hp==21 and g.state.scheduled.is_empty(),"empty battlefield still resolves independent effect")
	# Multiple turn repetitions are finite when requested.
	var src:=_compile(_base());g._effect({"op":"schedule","trigger":"next_own_turn_start","repeat":"each_turn","times":2,"lifetime":"match","effects":[{"op":"gain_hq_defense","player":"owner","amount":1}]},g._context(p,-1,src))
	for i in 3:_tick(g,p)
	_check(g.state.players[p].hp==23 and g.state.scheduled.is_empty(),"fixed times stops exactly after 2")
func _rhino() -> void:
	var g:=_game();var p:=_rich(g);var u:Dictionary=g._new_unit(p,_compile(fixtures[1].definition))
	var ctx:Dictionary=g._context(1-p,-1,_compile(_base()),u.uid)
	g._effect({"op":"damage","target":"chosen","amount":5},ctx);g._checkpoint();g._drain_deaths()
	_check(g.stack_count(u,"heavy_armor")==0 and g.state.scheduled.size()==2,"damage 5 reserves 2 armor events, no immediate armor")
	_tick(g,1-p);_check(g.stack_count(u,"heavy_armor")==0,"wrong turn no armor")
	_tick(g,p);_check(g.stack_count(u,"heavy_armor")==2 and g.state.scheduled.is_empty(),"both reservations apply next own turn")
	g._effect({"op":"damage","target":"chosen","amount":1},ctx);g._checkpoint();g._drain_deaths()
	_check(g.state.scheduled.size()==1,"remaining one damage carries across healing/turns")
	g._leave_battlefield(u,true);var next:Dictionary=g._new_unit(p,_compile(fixtures[1].definition));_tick(g,p)
	_check(g.stack_count(next,"heavy_armor")==0 and g.state.scheduled.is_empty(),"source lifetime ends on leaving")
	# limit is lifetime count, not extra per-event repeats.
	g=_game();p=_rich(g);var limited:Dictionary=fixtures[1].definition.duplicate(true);limited.abilities[0].erase("damage_step");limited.abilities[0].limit=10;limited.abilities[0].effects=[{"op":"gain_hq_defense","player":"owner","amount":1}]
	u=g._new_unit(p,_compile(limited))
	for i in 12:g._queue_unit_event(u,"on_damaged",-1,{},1);g._drain_deaths()
	_check(g.state.players[p].hp==30,"ten accepted event triggers, no 9 cap or extra repeats")
func _evolution() -> void:
	for row in ["support","front"]:
		for inherit in ["none","permanent"]:
			var g:=_game();var p:=_rich(g);var left:Dictionary=g._new_unit(p,_compile(_base("左")))
			var d:Dictionary=fixtures[2].definition.duplicate(true);d.abilities[0].effects[0].effects[0].inherit=inherit
			var uid:=_play(g,d);left=g._unit(int(left.uid));var u:Dictionary=g._unit(uid);var right:Dictionary=g._new_unit(p,_compile(_base("右")))
			if row=="front":
				for unit in [left,u,right]:g._remove_from_line(unit);unit.row=row;g._position_unit(unit)
			var ctx:Dictionary=g._context(p,uid,u.card,uid)
			g._effect({"op":"modify_stats","target":"self","attack_delta":2,"health_delta":1,"duration":"match"},ctx)
			g._effect({"op":"modify_stats","target":"self","attack_delta":3,"health_delta":1,"duration":"battle"},ctx)
			u.damage_taken=2;g._recompute(u)
			var original:Array=g.line_order(p,row).duplicate()
			for i in 2:_tick(g,p)
			_check(not g._unit(uid).is_empty(),"no evolution until third own turn")
			_tick(g,p)
			var order:Array=g.line_order(p,row);var evolved:Dictionary=g.state.units.filter(func(v):return v.card.definition.name=="进化单位")[0]
			original[original.find(uid)]=evolved.uid
			_check(order==original,"original line and exact neighbor placement, including HQ")
			_check(evolved.uid!=uid and evolved.card.definition.name=="进化单位","new generated unit identity")
			_check(evolved.attack==(7 if inherit=="permanent" else 5) and evolved.hp==(8 if inherit=="permanent" else 7),"only explicitly inherited permanent buffs, no temporary or damage")
			_check(g.state.players[1-p].hp==20 and g.state.players[p].hp==21,"no old death trigger; new summon trigger runs")
			_check(g.state.discard.any(func(e):return e.get("source_uid")==uid) and not g._ready(evolved),"old card discarded; new unit obeys summoning sickness")
	# Leaving before the third turn cannot transform a returned copy.
	var g:=_game();var p:=_rich(g);var uid:=_play(g,fixtures[2].definition);g._leave_battlefield(g._unit(uid),true)
	for i in 3:_tick(g,p)
	_check(g.state.units.is_empty() and g.state.scheduled.is_empty(),"evolution canceled if original leaves")
func _counter() -> void:
	var g:=_game();var p:=_rich(g);var uid:=_play(g,fixtures[3].definition);g._leave_battlefield(g._unit(uid),true)
	var source:=_compile(fixtures[3].definition);g._effect({"op":"prepare_counter","duration":"match"},g._context(p,-1,source))
	var order:=_base("被取消指令","order");order.abilities=[{"trigger":"on_play","effects":[{"op":"gain_hq_defense","player":"owner","amount":3}]}]
	g.state.active_player=1-p;g.state.turn+=1
	for i in 2:
		_play(g,order);_check(g.state.players[1-p].hp==20 and g.state.players[1-p].credits==11,"order canceled before all effects, cost paid")
		_check(g.state.order_intercepts.size()==1-i,"only oldest single reservation consumed")
	_play(g,order);_check(g.state.players[1-p].hp==23,"third order works after reservations consumed")
	_check(not g.view_for(p).has("order_intercepts"),"internal pending effects absent from client snapshot")
