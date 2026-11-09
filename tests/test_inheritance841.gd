extends "res://tests/test_copy836.gd"
const HATCH := "06c0ce91-5cf3-4ff9-97ff-d2f1fe341371"
const OTHER := "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
const Controller = preload("res://scripts/network/match_controller.gd")
var fixtures: Array
func _initialize() -> void:
	fixtures=JSON.parse_string(FileAccess.get_file_as_string("res://tests/inheritance841_cards.json"))
	for record in fixtures:
		if record.card_id==HATCH: continue
		for times in [0,1,2]:
			for before in [true,false]: _inherit(record,times,before)
	_identity_transport()
	_custom_sources()
	print("INHERITANCE841: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func _compiled(record: Dictionary) -> Dictionary:
	var card:=_compile(record.definition)
	card["telemetry_ref"]={"card_id":record.card_id,"revision":record.revision}
	return card

func _hatch(g: RefCounted, seat: int, card: Dictionary) -> void:
	g._receive_card(seat,card,"test")
	var h: Dictionary=fixtures.filter(func(r):return r.card_id==HATCH)[0]
	g._receive_card(seat,_compiled(h),"test")
	g.state.players[seat].credits=12
	_check(g.apply_action(seat,{"type":"play","hand_id":g.state.players[seat].hand.back().instance_id}).is_empty(),"cast actual hatching")
	_check(not g.state.pending_choice.is_empty(),"hatching chooses discarded unit")
	_check(g.apply_action(seat,{"type":"choose_card","choice_id":g.state.pending_choice.choice_id,"option_index":0}).is_empty(),"resolve hatching")
	g.state.players[seat].hand=[]

func _other_layers(g: RefCounted, seat: int, unit: Dictionary) -> void:
	var other:=_compile(_base("最后的孵化"));other["telemetry_ref"]={"card_id":OTHER,"revision":1}
	var context:Dictionary=g._context(seat,-1,other,unit.uid)
	g._effect({"op":"modify_stats","target":"chosen","attack_delta":7,"health_delta":6,"duration":"match"},context)
	g._effect({"op":"modify_operation_cost","target":"chosen","cost_delta":2,"duration":"match"},context)
	g._effect({"op":"modify_stacks","target":"chosen","stack":"heavy_armor","amount":3,"duration":"match"},context)
	g._effect({"op":"grant_keyword","target":"chosen","keyword_id":"core.fury","duration":"match"},context)
	g._effect({"op":"modify_cards","zones":["battlefield"],"player":"owner","filter":{},"duration":"match","grant_abilities":[{"trigger":"on_play","effects":[{"op":"gain_kredits","amount":1}]}]},context)
	g._effect({"op":"modify_stats","target":"chosen","attack_delta":1,"health_delta":1,"duration":"battle"},context)

func _inherit(record: Dictionary, times: int, before: bool) -> void:
	var fixed:Dictionary=record.duplicate(true)
	for ability in fixed.definition.abilities:
		for effect in ability.effects:
			if effect.op=="transfer_card": effect["inherit_from"]=[{"card_id":HATCH,"name":"最后的孵化"}]
	var card:=_compiled(fixed);var g:=_game();var seat:=_rich(g)
	g.state.players[seat].hand=[];g.state.players[seat].deck=[]
	var unit:Dictionary=g._new_unit(seat,card)
	if before: _other_layers(g,seat,unit)
	for n in times: _hatch(g,seat,card)
	unit=g._unit(unit.uid)
	if not before: _other_layers(g,seat,unit)
	_check(unit.attack==int(card.definition.attack)+times*2+8,"other buffs still work while alive")
	# Returning the same card preserves all permanent effects; only copying filters sources.
	g._leave_battlefield(unit,true)
	var returned:Dictionary=g.state.players[seat].hand.pop_back().card
	unit=g._new_unit(seat,returned)
	_check(unit.attack==int(card.definition.attack)+times*2+7,"return retains other permanent effects without temporary buff")
	for generation in 3:
		var restored:=EngineClass.new();restored.state=g.state.duplicate(true);restored._reset_budget();g=restored
		_kill(g,seat,unit.uid)
		_check(g.state.players[seat].deck.size()==1,"exactly one death copy")
		var copy:Dictionary=g.state.players[seat].deck.pop_back()
		var d:Dictionary=Runtime.display_definition(copy)
		_check(d.attack==int(card.definition.attack)+times*2 and d.health==int(card.definition.health)+times*2,"only hatching stats survive")
		_check(d.operation_cost==maxi(0,int(card.definition.operation_cost)-times),"only hatching cost changes survive")
		_check(copy.match_abilities.size()==times and copy.match_ability_sources.all(func(id):return id==HATCH),"only hatching granted abilities survive once each")
		_check(copy.definition==card.definition and copy.definition_hash==card.definition_hash,"immutable base unaffected")
		unit=g._new_unit(seat,copy)
		_check(g.stack_count(unit,"heavy_armor")==0 and not g._has_keyword(unit,"core.fury"),"other permanent stacks and keywords removed")
		_check(unit.attack==d.attack and unit.hp==d.health,"fresh healthy copy has correct stats")

func _identity_transport() -> void:
	var ctl:=Controller.new();var deck:=[]
	# Current deck rules require a nominal main/secondary sin even for neutral cards.
	ctl.main_sin="wrath";ctl.ally_sin="gloom"
	for n in 10:
		var card:=_compile(_base("来源校验"+str(n)));card["telemetry_ref"]={"card_id":HATCH,"revision":4}
		for count in 4:deck.append(card)
	var local:Dictionary=ctl._prepare_deck(deck,[])
	_check(local.ok and local.cards[0].telemetry_ref.card_id==HATCH,"practice source retained: "+str(local.get("error","")))
	if not local.ok: ctl.free();return
	var lan:Dictionary=ctl._prepare_deck(local.sources,[])
	_check(lan.ok and lan.cards[0].telemetry_ref.card_id==HATCH,"LAN source retained")
	deck[0].telemetry_ref={"card_id":"not-a-uuid","revision":1}
	_check(not ctl._prepare_deck(deck,[]).ok,"invalid source rejected")
	ctl.free()

func _custom_sources() -> void:
	var g:=_game();var seat:=_rich(g);var unit:Dictionary=g._new_unit(seat,_compile(_base()))
	for id in [HATCH,OTHER,HATCH]:
		var source:=_compile(_base());source["telemetry_ref"]={"card_id":id,"revision":1}
		g._effect({"op":"modify_stacks","target":"chosen","stack":"custom.test","amount":1,"duration":"match"},g._context(seat,-1,source,unit.uid))
	var copied:Dictionary=unit.card.duplicate(true)
	g._filter_inherited_layers(copied,[{"card_id":HATCH,"name":"最后的孵化"}])
	_check(g.stack_count(g._new_unit(seat,copied),"custom.test")==2,"custom stack compaction keeps source boundaries")
