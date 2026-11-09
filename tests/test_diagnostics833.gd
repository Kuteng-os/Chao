extends "res://tests/test_engine.gd"
var records: Array
func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("CHAO_833_FIXTURE") if not OS.get_environment("CHAO_833_FIXTURE").is_empty() else "res://tests/fixtures833.json"))
	records=data.cards
	for row in records:
		var c:=_compile(row.definition)
		_check(c.definition_hash==row.definition_hash and c.compiled_program_hash==row.compiled_program_hash,"Node and Godot agree: "+row.definition.name)
		_check(not "未知" in Runtime.rules_text(c),"new rules text is readable")
	_named_counts()
	_choices()
	_next_deployment()
	_name_filters()
	print("DIAGNOSTICS 833: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _named_counts() -> void:
	var g:=_game();var seat:=_rich(g)
	for name in ["甲集团军","甲集团军","乙集团军","其他"]:g._new_unit(seat,_compile(_base(name)))
	g.state.units[2].row="front"
	g._new_unit(1-seat,_compile(_base("丙集团军")))
	_play(g,records[0].definition)
	for u in g.state.units:
		_check(u.attack==(5 if u.owner==seat else 3),"two unique friendly names, both rows, all friendly buffed")
	var uid:int=g.state.units[0].uid
	g._leave_battlefield(g._unit(uid),true)
	var returned:Dictionary=g.state.players[seat].hand.back()
	_check(g.apply_action(seat,{"type":"play","hand_id":returned.instance_id}).is_empty(),"permanent counted buff returns")
	_check(g.state.units.back().attack==5,"return and redeploy preserves +2 only once")
	var new_unit:Dictionary=g._new_unit(seat,_compile(_base("新集团军")))
	_check(new_unit.attack==3,"later units do not inherit snapshot buff")
	var c:=_compile(records[0].definition)
	_check(g._effect_value({"count_units":{"side":"ally","name_contains":"集团军","distinct_by":"name"}},g._context(seat,-1,c))==3,"counter counts new battlefield state")
	_check(g._effect_value({"count_units":{"side":"enemy","card_name":"丙集团军"}},g._context(seat,-1,c))==1,"exact enemy name count")
	_check(g._effect_value({"count_units":{"side":"any","name_contains":"不存在"}},g._context(seat,-1,c))==0,"zero count supported")

func _choices() -> void:
	for index in [0,1]:
		var g:=_game();var seat:=_rich(g);g.state.players[seat].hand=[]
		var ally:Dictionary=g._new_unit(seat,_compile(_base("友军")));var aid:int=ally.uid
		var target:=_base("敌军");target.health=9
		var enemy:Dictionary=g._new_unit(1-seat,_compile(target));var eid:int=enemy.uid
		var before:int=g.state.players[seat].deck.size()
		_play(g,records[1].definition,aid)
		_check(g.state.has("pending_choice") and g.state.pending_choice.kind=="effect","choice pending")
		_check(not g.view_for(1-seat).pending_choice.has("options"),"opponent cannot choose private options")
		_check(g._unit(aid).hp==4,"no branch executes before choice")
		var snap:=Runtime.sha(g.state);var choice:Dictionary=g.state.pending_choice
		_check(not g.apply_action(1-seat,{"type":"choose_card","choice_id":choice.choice_id,"option_index":index}).is_empty() and snap==Runtime.sha(g.state),"wrong seat rejected atomically")
		_check(not g.apply_action(seat,{"type":"choose_card","choice_id":choice.choice_id,"option_index":9}).is_empty() and snap==Runtime.sha(g.state),"invalid branch rejected")
		var restored:=EngineClass.new();restored.state=g.state.duplicate(true)
		var action:Dictionary={"type":"choose_card","choice_id":choice.choice_id,"option_index":index}
		_check(g.apply_action(seat,action).is_empty() and restored.apply_action(seat,action).is_empty(),"choice resolves after restore")
		_check(Runtime.sha(g.state)==Runtime.sha(restored.state),"choice replay deterministic")
		_check(g._unit(aid).hp==2,"friendly damage happens exactly once")
		_check(g._unit(eid).hp==(9 if index==0 else 4),"enemy damaged only by second branch")
		_check(g.state.players[seat].deck.size()==before-(2 if index==0 else 0),"draw only in first branch")
		_check(g.state.players[seat].credits==9,"cost paid once across choice replay")
		_check(not g.state.has("pending_choice"),"choice clears")
		_check(not g.apply_action(seat,action).is_empty(),"duplicate answer rejected")

func _next_deployment() -> void:
	var g:=_game();var seat:=_rich(g)
	var enemy:Dictionary=g._new_unit(1-seat,_compile(_base("目标")))
	_play(g,records[2].definition,enemy.uid)
	_check(g.state.get("scheduled",[]).size()==1,"next deployment registered")
	var summoned:Dictionary=g._new_unit(seat,_compile(_base("直接召唤")))
	g._initialize_summoned_unit(summoned)
	_check(not g._has_keyword(summoned,"core.blitz") and g.state.scheduled.size()==1,"summoning does not consume next deployment")
	g.state.active_player=1-seat
	_play(g,_base("敌方部署"))
	_check(g.state.scheduled.size()==1,"opponent cannot consume friendly next deployment")
	g.state.active_player=seat
	var uid:=_play(g,_base("获得闪击"))
	_check(g._has_keyword(g._unit(uid),"core.blitz") and g.state.scheduled.is_empty(),"next friendly deployed unit gains blitz once")
	var second:=_play(g,_base("后续"))
	_check(not g._has_keyword(g._unit(second),"core.blitz"),"subsequent unit gets no repeated bonus")

func _name_filters() -> void:
	var g:=_game();var seat:=_rich(g)
	var ids:Array=[]
	for name in ["第4集团军犀牛","第4集团军犀牛","其他集团军","路人"]:ids.append(g._new_unit(seat,_compile(_base(name))).uid)
	var enemy:Dictionary=g._new_unit(1-seat,_compile(_base("第4集团军犀牛")))
	_play(g,records[3].definition)
	for i in ids.size():
		var u:Dictionary=g._unit(ids[i])
		_check(g.stack_count(u,"heavy_armor")== (1 if i<3 else 0),"name contains filter grants armor")
		_check(g._has_keyword(u,"core.immune")== (i<2),"exact names alone gain immunity")
	_check(g.stack_count(g._unit(enemy.uid),"heavy_armor")==0,"side restriction remains")
	var ctx:Dictionary=g._context(seat,-1,_compile(records[3].definition))
	for i in 8:_check(g._targets("random_friendly_unit",ctx,{"card_name":"路人"})==[ids[3]],"random selection follows filter")
	_check(g._targets("all_friendly_units",ctx,{"name_contains":"不存在"}).is_empty(),"no matching target is a no-op")
	g.apply_action(seat,{"type":"end_turn"})
	_check(not g._has_keyword(g._unit(ids[0]),"core.immune"),"named turn-only immunity expires")
