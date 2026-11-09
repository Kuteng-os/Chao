extends "res://tests/test_engine.gd"
var headquarters: Array
func _initialize() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures835.json"))
	headquarters=data.cards
	for row in headquarters:
		var c:=_compile(row.definition)
		_check(c.definition_hash==row.definition_hash and c.compiled_program_hash==row.compiled_program_hash,"HQ compiler parity")
	_health_draw_aura()
	_events()
	_selection()
	_rejections()
	print("HEADQUARTERS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _hq_game(index: int=0) -> RefCounted:
	var g:=EngineClass.new();var d:=_deck()
	_check(g.setup(d,d,42,[_compile(headquarters[index].definition),{}]).is_empty(),"HQ setup")
	return g

func _health_draw_aura() -> void:
	var g:=_hq_game()
	_check(g.state.players[0].hp==35 and g.state.players[0].max_hp==35,"custom defense")
	_check(g.state.players[1].hp==20 and g.turn_draw_count(1)==1,"default HQ compatibility")
	_check(g.state.units.is_empty(),"HQ is not a unit")
	for p in 2:
		_check((g.state.players[p].deck+g.state.players[p].hand.map(func(e):return e.card)).size()==40,"HQ excluded from draw pile and hand")
	var u:Dictionary=g._new_unit(0,_compile(_base("友方")))
	var enemy:Dictionary=g._new_unit(1,_compile(_base("敌方")))
	_check(u.attack==4 and u.max_hp==5 and enemy.attack==3,"owner aura only")
	_check(g.turn_draw_count(0)==1,"equal counts base draw")
	g._new_unit(1,_compile(_base("敌方二")))
	_check(g.turn_draw_count(0)==2,"conditional draw when outnumbered")
	g.state.active_player=1
	g.state.players[0].hp=30
	var before:int=g.state.players[0].hand.size()
	_check(g.apply_action(1,{"type":"end_turn"}).is_empty(),"HQ turn advances")
	_check(g.state.players[0].hand.size()==before+2 and g.state.players[0].hp==31,"conditional draws and recurring heal")
	var field:=_base("场地","field");field.appearance.emblem="field"
	_play(g,field)
	_check(g.state.players[0].headquarters.definition.health==35 and u.attack==4,"field does not replace HQ")
	var view:Dictionary=g.view_for(1)
	_check(view.players[0].headquarters.definition.name=="后勤总部" and not view.players[0].has("hq_event_counts"),"HQ visible without private event counters")
	var spec:Dictionary=headquarters[0].definition.duplicate(true);spec.draw_rule={"base":0,"adjustments":[{"premise":{"test":"compare","left":1,"cmp":"eq","right":1},"delta":-5}]};g.state.players[0].headquarters=_compile(spec)
	_check(g.turn_draw_count(0)==0,"draw lower clamp")
	spec.draw_rule={"base":5,"adjustments":[{"premise":{"test":"compare","left":1,"cmp":"eq","right":1},"delta":5},{"premise":{"test":"compare","left":1,"cmp":"eq","right":1},"delta":5}]};g.state.players[0].headquarters=_compile(spec)
	_check(g.turn_draw_count(0)==10,"draw upper clamp")

func _events() -> void:
	var g:=_hq_game(1);g.state.active_player=0
	for i in 3:
		_play(g,_base("部署"+str(i)))
		_check(g.state.players[0].credits==(12 if i<2 else 11),"HQ deployment reward respects match limit")
	_check(int(g.state.players[0].hq_event_counts.get("0",0))==2,"HQ event quota")

func _selection() -> void:
	var g:=_hq_game(2)
	if g.state.has("pending_choice"):
		_check(g.state.has("_resolution"),"opening HQ choice has replay origin")
		_check(g.apply_action(0,{"type":"choose_target","choice_id":g.state.pending_choice.choice_id,"target_uid":-101}).is_empty(),"opening HQ choice resolves")
	g.state.active_player=1
	g.state.players[0].hp=25
	var before:int=g.state.players[0].hand.size()
	_check(g.apply_action(1,{"type":"end_turn"}).is_empty(),"HQ turn choice begins")
	_check(g.state.get("pending_choice",{}).get("owner")==0,"HQ chooses for controller")
	_check(g.apply_action(0,{"type":"choose_target","choice_id":g.state.pending_choice.choice_id,"target_uid":-101}).is_empty(),"HQ target resolves")
	_check(g.state.players[0].hp==26 and g.state.players[0].hand.size()==before+1,"replay does not duplicate draw")

func _rejections() -> void:
	var h:Dictionary=headquarters[0].definition.duplicate(true)
	for patch in [{"health":0},{"health":101},{"cost":1},{"attack":1},{"draw_rule":{"base":6}}]:
		_check(not Runtime.compile_card(h.merged(patch,true),Runtime.builtin_keywords()).ok,"invalid HQ rejected")
	var d:=_deck();d[0]=_compile(h)
	_check(not EngineClass.new().setup(d,_deck()).is_empty(),"HQ cannot be mixed into 40 cards")
