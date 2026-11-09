extends "res://tests/test_engine.gd"

func _initialize() -> void:
	_counts_and_targets()
	_permanent()
	_adjacent()
	_text()
	_combined_target()
	_model_cards()
	print("COMPOSITION827: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _count(side: String, classes: Array, amount: int, row: String = "any") -> Dictionary:
	return {"test":"compare","left":{"count_units":{"side":side,"row":row,"unit_classes":classes}},"cmp":"eq","right":amount}

func _counts_and_targets() -> void:
	var g:=_game();var seat:=_rich(g)
	var chosen: Dictionary = {}
	for side in [seat,1-seat]:
		for type in ["infantry","tank","artillery","fighter","bomber"]:
			var c:=_base(type);c.unit_class=type;c.appearance.emblem=type
			var u: Dictionary=g._new_unit(side,_compile(c));chosen[str(side)+type]=u.uid
	var context:Dictionary=g._context(seat,-1,_compile(_base()))
	for side in ["ally","enemy"]:
		for type in ["infantry","tank","artillery","fighter","bomber"]:
			_check(g._premise_met(_count(side,[type],1),context),side+type+" count")
		_check(g._premise_met(_count(side,["fighter","bomber"],2),context),side+" air count")
		_check(g._premise_met(_count(side,["infantry","tank","artillery"],3),context),side+" ground count")
	_check(g._premise_met(_count("any",["tank"],2),context),"both tank counts")
	_check(g._premise_met(_count("ally",["tank"],0,"front"),context),"row is intersection")
	var c:=_base("指定空军","order");c.play_target={"side":"enemy","row":"any","unit_classes":["fighter","bomber"]};c.abilities=[{"trigger":"on_play","premise":_count("ally",["tank"],1),"effects":[{"op":"damage","target":"chosen","amount":1}]}]
	var compiled:=_compile(c);g.state.players[seat].hand=[{"instance_id":"typed","card":compiled}]
	var legal: Array=g.legal_targets(seat,{"type":"play","hand_id":"typed"})
	_check(legal.size()==2 and chosen[str(1-seat)+"fighter"] in legal and chosen[str(1-seat)+"bomber"] in legal,"typed order exposes only enemy air")
	var before:=JSON.stringify(g.state)
	_check(not g.apply_action(seat,{"type":"play","hand_id":"typed","target_uid":chosen[str(1-seat)+"tank"]}).is_empty(),"server rejects wrong class target")
	_check(JSON.stringify(g.state)==before,"rejection is atomic")
	_check(g.apply_action(seat,{"type":"play","hand_id":"typed","target_uid":chosen[str(1-seat)+"bomber"]}).is_empty(),"valid air target executes")
	_check(g._unit(chosen[str(1-seat)+"bomber"]).hp==3,"targeted order damage")
	c.play_target["include_hq"]=true
	_check(not Runtime.compile_card(c,Runtime.builtin_keywords()).ok,"class filtered HQ rejected")

func _permanent() -> void:
	var g:=_game();var seat:=_rich(g);var original:=_compile(_base());var unit:Dictionary=g._new_unit(seat,original)
	var context:Dictionary=g._context(seat,unit.uid,unit.card,unit.uid)
	var layers: Array=[{"op":"modify_stats","target":"chosen","attack_delta":2,"health_delta":3,"duration":"match"},{"op":"grant_keyword","target":"chosen","keyword_id":"core.ambush","keyword_version":1,"duration":"match"},{"op":"modify_stacks","target":"chosen","stack":"heavy_armor","amount":2,"duration":"match"},{"op":"set_attack_limit","target":"chosen","attacks":3,"duration":"match"},{"op":"modify_operation_cost","target":"chosen","cost_delta":-1,"duration":"match"},{"op":"set_combat_damage_multiplier","target":"chosen","multiplier":2,"against":"any","applies_to":"both","duration":"match"}]
	for e in layers:
		var order:=_base("永久指令","order");order.play_target={"side":"ally","row":"any"};order.abilities=[{"trigger":"on_play","effects":[e]}];_compile(order)
		g._effect(e,context)
	g._effect({"op":"modify_stats","target":"chosen","attack_delta":1,"health_delta":1,"duration":"battle"},context)
	g._effect({"op":"modify_stats","target":"chosen","attack_delta":1,"health_delta":1,"duration":"end_of_turn"},context)
	var saved:Dictionary=unit.card.duplicate(true)
	_check(saved.match_layers.size()==6,"all permanent layers stored once")
	_check(Runtime.sha(saved.source)==original.definition_hash and saved.definition==original.definition,"frozen definition remains unchanged")
	g._leave_battlefield(unit,true)
	var returned:Dictionary=g.state.players[seat].hand.back().card
	var display:=Runtime.display_definition(returned)
	_check(display.attack==5 and display.health==7 and display.operation_cost==0,"hand displays permanent values")
	var next:Dictionary=g._new_unit(seat,returned)
	_check(next.attack==5 and next.max_hp==7 and next.hp==7,"reentry retains permanent stats only, fully healed")
	_check(g._has_keyword(next,"core.ambush") and g.stack_count(next,"heavy_armor")==2 and g.attack_limit(next)==3 and g._operation_cost(next)==0,"reentry retains other permanent layers")
	_check(next.combat_damage_rules.size()==1,"damage modifier retained")
	var same:Dictionary=g._new_unit(seat,original)
	_check(same.attack==3 and same.max_hp==4,"other copies unaffected")
	g._effect({"op":"destroy","target":"chosen"},g._context(seat,-1,original,next.uid));g._checkpoint()
	g._transfer_card({"op":"transfer_card","source":"discard","destination":"support","mode":"move","selection":"top","amount":1},context)
	var revived:Dictionary=g.state.units.back()
	_check(revived.attack==5 and revived.max_hp==7,"discard resurrection retains layers")
	g._transfer_card({"op":"transfer_card","source":"self","destination":"hand","mode":"copy","selection":"top","amount":1},g._context(seat,revived.uid,revived.card))
	_check(g.state.players[seat].hand.back().card.get("match_layers",[]).size()==6,"copy inherits permanent layers once")
	g._suppress(revived);g._leave_battlefield(revived,true)
	var cleared:Dictionary=g._new_unit(seat,g.state.players[seat].hand.back().card)
	_check(cleared.attack==3 and not cleared.card.has("match_layers"),"suppression actively removes permanent bonus")
	var deck:=_deck();for card in deck:card["match_layers"]=saved.match_layers.duplicate(true)
	var fresh:=EngineClass.new();_check(fresh.setup(deck,deck,55).is_empty(),"new match can initialize")
	_check(not fresh.state.players[0].hand[0].card.has("match_layers") and not fresh.state.starting_decks[0][0].has("match_layers"),"match layers never leak across matches")

func _adjacent() -> void:
	var g:=_game();var seat:=_rich(g);var card:=_compile(_base());var a:Dictionary=g._new_unit(seat,card);var b:Dictionary=g._new_unit(seat,card);var c:Dictionary=g._new_unit(seat,card)
	# Explicit positions make HQ interruption test deterministic.
	g._write_line(seat,"support",[a.uid,b.uid,c.uid,-1])
	var ctx:Dictionary=g._context(seat,b.uid,b.card,b.uid)
	_check(g._targets("adjacent_to_chosen",ctx)==[a.uid,c.uid],"both neighbours, excluding chosen center")
	g._effect({"op":"modify_stats","target":"adjacent_to_chosen","attack_delta":1,"health_delta":0,"duration":"battle"},ctx)
	_check(a.attack==4 and b.attack==3 and c.attack==4,"adjacent result affects neighbours only")
	g._write_line(seat,"support",[a.uid,b.uid,-1,c.uid])
	_check(g._targets("adjacent_to_self",ctx)==[a.uid],"HQ breaks adjacency")
	g._leave_battlefield(b,true)
	_check(g._targets("adjacent_to_chosen",ctx).is_empty(),"departed selected center is not replaced")
	var aura:=_base("相邻光环");aura.abilities=[{"trigger":"while_active","effects":[{"op":"modify_stats","target":"adjacent_to_self","attack_delta":2,"health_delta":1,"duration":"battle"}]}]
	var source:Dictionary=g._new_unit(seat,_compile(aura));g._write_line(seat,"support",[a.uid,source.uid,c.uid,-1]);g._checkpoint()
	_check(a.attack==6 and c.attack==6 and source.attack==3,"neighbour aura applies without self stacking")
	g._leave_battlefield(source,true);g._checkpoint()
	_check(a.attack==4 and c.attack==4,"source leaving removes adjacent aura")
	var order:=_base("邻接指令","order");order.play_target={"side":"enemy","row":"any","unit_classes":["tank"]};order.abilities=[{"trigger":"on_play","effects":[{"op":"damage","target":"adjacent_to_chosen","amount":2}]}];_compile(order)

func _text() -> void:
	var c:=_base("长".repeat(64));var r:=_compile(c);_check(r.definition.name.length()==64,"64 unicode name accepted")
	c.name+="多";_check(not Runtime.compile_card(c,Runtime.builtin_keywords()).ok,"65 chars rejected")
	c=_base();c.abilities=[{"trigger":"on_play","effects":[{"op":"pin","target":"all_friendly_units","turns":1},{"op":"pin","target":"all_enemy_units","turns":1},{"op":"suppress","target":"all_friendly_units"},{"op":"suppress","target":"all_enemy_units"}]}]
	var text:=Runtime.rules_text(_compile(c));_check(text.contains("压制所有单位") and text.contains("抑制所有单位"),"same type effects compacted")

func _combined_target() -> void:
	var g:=_game();var seat:=_rich(g);var small:=_base();small.health=1
	var a:Dictionary=g._new_unit(seat,_compile(small));var b:Dictionary=g._new_unit(seat,_compile(small));var c:Dictionary=g._new_unit(seat,_compile(small))
	g._write_line(seat,"support",[a.uid,b.uid,c.uid,-1])
	var spell:=_base("共同减益","order");spell.play_target={"side":"ally","row":"any","unit_classes":["tank"]};spell.abilities=[{"trigger":"on_play","effects":[{"op":"modify_stats","target":"chosen_and_adjacent","attack_delta":-1,"health_delta":-1,"duration":"match"}]}]
	_play(g,spell,b.uid)
	_check(g.state.units.is_empty(),"one combined operation affects neighbours even when center is killed")
	_check(g.state.discard.filter(func(e):return e.card.definition.kind=="unit" and e.card.has("match_layers")).size()==3,"same permanent operation follows each affected instance")

func _model_cards() -> void:
	var path:=OS.get_environment("FRONTLINE_COMPOSITION_MODELS")
	if path.is_empty():return
	var rows: Array=JSON.parse_string(FileAccess.get_file_as_string(path))
	for row in rows:
		if row.get("kind")!="card" or not row.get("pass",false):continue
		var card:=_compile(row.compiled.definition)
		_check(card.compiled_program_hash==row.compiled.compiled_program_hash,"real model card compiles identically on both runtimes")

		var g:=_game();var seat:=_rich(g)
		if card.definition.kind=="order":
			var tank:=_compile(_base());var a:Dictionary=g._new_unit(1-seat,tank);var b:Dictionary=g._new_unit(1-seat,tank);var c:Dictionary=g._new_unit(1-seat,tank)
			g._write_line(1-seat,"support",[a.uid,b.uid,c.uid,-1])
			_play(g,card.definition,b.uid)
			a=g._unit(a.uid);b=g._unit(b.uid);c=g._unit(c.uid)
			_check(a.attack==3 and b.attack==3 and c.attack==3,"real model: no allied air means no debuff")
			var air:=_base();air.unit_class="fighter";air.appearance.emblem="fighter";g._new_unit(seat,_compile(air))
			_play(g,card.definition,b.uid)
			a=g._unit(a.uid);b=g._unit(b.uid);c=g._unit(c.uid)
			_check(a.attack==2 and b.attack==2 and c.attack==2 and a.max_hp==3,"real model: air premise enables center and adjacent debuff")
			g._leave_battlefield(b,true);var returned:Dictionary=g._new_unit(1-seat,g.state.players[1-seat].hand.back().card)
			_check(returned.attack==2 and returned.max_hp==3,"real model: permanent debuff survives reentry")
		else:
			var plain:=_compile(_base());var a:Dictionary=g._new_unit(seat,plain);var source:Dictionary=g._new_unit(seat,card);var b:Dictionary=g._new_unit(seat,plain)
			g._write_line(seat,"support",[a.uid,source.uid,b.uid,-1]);g._checkpoint()
			_check(a.attack==4 and b.attack==4 and a.max_hp==5,"real model: adjacent aura applies")
			g._leave_battlefield(source,true);g._checkpoint()
			_check(a.attack==3 and b.attack==3 and a.max_hp==4,"real model: adjacent aura expires on source departure")
