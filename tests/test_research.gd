extends "res://tests/test_engine.gd"

func _initialize() -> void:
	_discard_and_buffs()
	_empty_and_random()
	_research()
	_develop()
	_real_model()
	print("RESEARCH AND HAND CHOICES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _last_hatching(duration := "match") -> Dictionary:
	var d := _base("最后的孵化","order")
	d.abilities = [{"trigger":"on_play","effects":[{"op":"discard","player":"owner","amount":1,"selection":"chosen","filter":{"kind":"unit","name_contains":"集团军"}},{"op":"modify_cards","player":"owner","zones":["battlefield","hand","deck"],"filter":{"same_as_discarded":true},"attack_delta":2,"health_delta":2,"operation_cost_delta":-1,"duration":duration,"grant_abilities":[{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]}]}]
	return d

func _answer(g: RefCounted, owner: int, index: int) -> void:
	var choice: Dictionary = g.state.pending_choice
	_check(g.apply_action(owner,{"type":"choose_card","choice_id":choice.choice_id,"option_index":index}).is_empty(),"valid card choice resolves")

func _discard_and_buffs() -> void:
	for duration in ["match","battle"]:
		var g := _game();var seat := _rich(g)
		var a := _compile(_base("甲集团军"));var b := _compile(_base("乙集团军"))
		g.state.players[seat].hand=[]
		g._receive_card(seat,a,"test");g._receive_card(seat,a,"test");g._receive_card(seat,b,"test")
		g.state.players[seat].deck=[a.duplicate(true),b.duplicate(true)]
		var unit:Dictionary = g._new_unit(seat,a);var id:int=unit.uid
		g._new_unit(1-seat,a)
		_play(g,_last_hatching(duration))
		_check(g.state.pending_choice.kind=="discard" and g.state.pending_choice.options.size()==3,"filtered chosen discard waits")
		_check(not g.view_for(1-seat).pending_choice.has("options"),"opponent cannot read hand candidates")
		_check(g.view_for(seat).pending_choice.options.size()==3,"owner can read candidates")
		var snap := Runtime.sha(g.state)
		for bad in [{"type":"choose_card","choice_id":"bad","option_index":0},{"type":"choose_card","choice_id":g.state.pending_choice.choice_id,"option_index":3},{"type":"choose_target","choice_id":g.state.pending_choice.choice_id,"target_uid":id}]:
			_check(not g.apply_action(seat,bad).is_empty() and snap==Runtime.sha(g.state),"invalid answer atomic")
		_check(not g.apply_action(1-seat,{"type":"choose_card","choice_id":g.state.pending_choice.choice_id,"option_index":0}).is_empty(),"wrong seat cannot choose")
		var recovered := EngineClass.new();recovered.state=g.state.duplicate(true)
		_answer(g,seat,0);_answer(recovered,seat,0)
		_check(Runtime.sha(g.state)==Runtime.sha(recovered.state),"frozen choice survives authority restore")
		unit=g._unit(id)
		_check(unit.attack==5 and unit.max_hp==6 and unit.operation_cost==0,"battlefield same name buffed")
		_check(g.state.units.filter(func(u):return u.owner!=seat)[0].attack==3,"enemy unaffected")
		var remaining:Dictionary = g.state.players[seat].hand.filter(func(e):return e.card.definition.name==a.definition.name)[0]
		_check(Runtime.display_definition(remaining.card).attack==5,"hand reflects bonus before deployment")
		_check(Runtime.display_definition(g.state.players[seat].deck[0]).attack==5,"deck same name buffed")
		_check(Runtime.display_definition(g.state.players[seat].deck[1]).attack==3,"different name untouched")
		_check(a.definition.attack==3 and Runtime.sha(a.source)==a.definition_hash,"printed definition immutable")
		var before:int=g.state.players[seat].deck.size()
		_check(g.apply_action(seat,{"type":"play","hand_id":remaining.instance_id}).is_empty(),"buffed unit deployed")
		_check(g.state.players[seat].deck.size()==before-1,"gifted deployment draw occurs once")
		var deployed:Dictionary=g.state.units.back()
		g._leave_battlefield(deployed,true)
		var returned:Dictionary=g.state.players[seat].hand.back().card
		_check(Runtime.display_definition(returned).attack==(5 if duration=="match" else 3),"match vs battle duration after return")
		var again:Dictionary=g._new_unit(seat,returned)
		_check(again.attack==(5 if duration=="match" else 3),"reentry has no duplicate layers")
		_check(g._abilities(g._context(seat,again.uid,again.card),"on_play").size()==(1 if duration=="match" else 0),"gifted ability lifetime matches")
		g._suppress(unit)
		_check(unit.attack==3 and not unit.card.has("match_abilities"),"suppression clears granted data")
	_check(Runtime.rules_text(_compile(_last_hatching())).begins_with("使用时"),"order says use, not deploy")

func _empty_and_random() -> void:
	var g:=_game();var seat:=_rich(g);g.state.players[seat].hand=[]
	var unit:Dictionary=g._new_unit(seat,_compile(_base("集团军")))
	var d:=_last_hatching();d.abilities[0].effects.append({"op":"draw","player":"owner","amount":1})
	_play(g,d)
	_check(not g.state.has("pending_choice") and g._unit(unit.uid).attack==3 and g.state.players[seat].hand.size()==1,"no discard target skips dependent buff, independent draw still resolves")
	var clone := EngineClass.new();clone.state=g.state.duplicate(true)
	for engine in [g,clone]:
		engine._reset_budget();engine._effect({"op":"discard","player":"owner","amount":3},engine._context(seat,-1,_compile(d)))
	_check(Runtime.sha(g.state)==Runtime.sha(clone.state) and g.state.players[seat].hand.is_empty(),"legacy random discard deterministic, safely bounded by hand size")
	var enemy_order:=_base("敌方自选弃牌","order");enemy_order.abilities=[{"trigger":"on_play","effects":[{"op":"discard","player":"opponent","selection":"chosen","amount":1}]}]
	_play(g,enemy_order)
	_check(g.state.pending_choice.owner==1-seat and not g.view_for(seat).pending_choice.has("options"),"opponent chooses their own card privately")
	_answer(g,1-seat,0)

func _research_card() -> Dictionary:
	var d:=_base("初级研发","order");d.cost=3
	d.abilities=[{"trigger":"on_play","effects":[{"op":"research","token_ids":["reward_a","stage_2"]}]}]
	var tokens:=[]
	for id in ["reward_a","reward_b","reward_c","reward_d","stage_2","stage_3"]:
		var t:=_base(id,"order")
		for key in ["schema_version","ruleset_version","appearance","tokens"]:t.erase(key)
		t["token_id"]=str(id);t.cost=1;t.abilities=[{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]
		tokens.append(t)
	tokens[4].cost=6;tokens[4].abilities[0].effects=[{"op":"research","token_ids":["reward_b","stage_3"]}]
	tokens[5].cost=9;tokens[5].abilities[0].effects=[{"op":"research","token_ids":["reward_c","reward_d"]}]
	d.tokens=tokens
	return d

func _research() -> void:
	var g:=_game();var seat:=_rich(g);g.state.players[seat].hand=[]
	_play(g,_research_card())
	_check(g.state.pending_choice.options.size()==2 and g.state.players[seat].credits==9,"research offers reward or next stage, only current cost paid")
	_answer(g,seat,1)
	var next:Dictionary=g.state.players[seat].hand.back()
	_check(next.card.definition.name=="stage_2" and g.state.players[seat].hand.size()==1,"selected stage only added, not auto cast")
	_check(g.apply_action(seat,{"type":"play","hand_id":next.instance_id}).is_empty(),"second stage is playable")
	_answer(g,seat,1)
	next=g.state.players[seat].hand.back()
	_check(g.state.players[seat].credits==3 and next.card.definition.name=="stage_3","next stage has independent 6 cost")
	g.state.players[seat].credits=12
	_check(g.apply_action(seat,{"type":"play","hand_id":next.instance_id}).is_empty(),"third stage playable")
	_answer(g,seat,1)
	_check(g.state.players[seat].hand.back().card.definition.name=="reward_d" and g.state.players[seat].credits==3,"final choice awards selected reward")

func _develop() -> void:
	var d:=_research_card();d.tokens=d.tokens.slice(0,4);d.abilities[0].effects=[{"op":"develop","source":"tokens","token_ids":["reward_a","reward_b","reward_c","reward_d"]}]
	var g:=_game();var seat:=_rich(g)
	_play(g,d)
	_check(g.state.pending_choice.options.size()==3,"develop draws three candidates without replacement")
	var names:Dictionary={}
	for card in g.state.pending_choice.options: names[card.definition.name]=true
	_check(names.size()==3,"all options unique")
	var picked:String=g.state.pending_choice.options[2].definition.name
	_answer(g,seat,2)
	_check(g.state.players[seat].hand.back().card.definition.name==picked,"selected development card awarded")
	d.tokens=[];d.abilities[0].effects=[{"op":"develop","source":"starting_deck","filter":{"name_contains":"不存在"}}]
	_play(g,d);_check(not g.state.has("pending_choice"),"empty pool resolves without choice")
	d.abilities[0].effects[0].filter={"kind":"unit"}
	var deck_size:int=g.state.players[seat].deck.size();_play(g,d)
	_check(g.state.pending_choice.options.size()==3,"starting deck development")
	_answer(g,seat,0)
	_check(g.state.players[seat].deck.size()==deck_size,"development copies frozen pool without consuming deck")

func _real_model() -> void:
	var path:=OS.get_environment("FRONTLINE_RESEARCH_MODEL")
	if path.is_empty(): return
	var records:Array=JSON.parse_string(FileAccess.get_file_as_string(path))
	for row in records:
		if not row.has("compiled"): continue
		var c:=_compile(row.compiled.definition)
		_check(c.definition_hash==row.compiled.definition_hash and c.compiled_program_hash==row.compiled.compiled_program_hash,"real model Node/Godot hashes agree")
		var g:=_game();var seat:=_rich(g);g.state.players[seat].hand=[]
		if row.card_name=="最后的孵化":
			var unit:=_compile(_base("测试集团军"));g._receive_card(seat,unit,"test");g._new_unit(seat,unit)
		_play(g,row.compiled.definition)
		_check(g.state.has("pending_choice"),"real model opens legal choice")
		if row.card_name=="最后的孵化":
			_answer(g,seat,0)
			_check(g.state.units[0].attack==5 and g.state.units[0].ability_layers.size()==1,"real model discard and enhancement executes")
		else:
			for i in 3:
				_answer(g,seat,1)
				if i<2:
					g.state.players[seat].credits=12
					_check(g.apply_action(seat,{"type":"play","hand_id":g.state.players[seat].hand.back().instance_id}).is_empty(),"real model next stage plays")
			_check(not g.state.has("pending_choice") and g.state.players[seat].hand.size()==1,"real model three stage chain finishes")
