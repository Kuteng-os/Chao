extends "res://tests/test_engine.gd"
var records:Array
const SWORD:="408c3c32-19c5-49ce-9a9d-055c38d516ba"
func _initialize() -> void:
	records=JSON.parse_string(FileAccess.get_file_as_string("res://tests/latest841.json")).cards
	for r in records:
		var c:=_compile(r.definition)
		_check(c.definition_hash==r.definition_hash and c.compiled_program_hash==r.compiled_program_hash,"latest reports cross-runtime hashes")
		_check(not "[object" in Runtime.rules_text(c),"readable latest rules")
	_draws()
	_previous()
	_delayed()
	_equipment()
	print("LATEST841: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func _cost_card(cost: int, kind: String) -> Dictionary:
	var c:=_base("牌"+str(cost),kind);c.cost=cost
	if cost==0:c["deck_building"]="generated_only"
	if kind!="unit": c.abilities=[{"trigger":"on_play","effects":[{"op":"noop"}]}]
	var result:=_compile(c)
	if not result.ok:print("BAD_FIXTURE ",cost," ",kind)
	return result

func _draws() -> void:
	for costs in [[1,3],[2,3],[0,1],[2,4]]:
		for full in [false,true]:
			var g:=_game();var p:=_rich(g);g.state.players[p].hand=[]
			g.state.players[p].deck=[_cost_card(9,"unit"),_cost_card(costs[1],"order"),_cost_card(7,"field"),_cost_card(costs[0],"unit")]
			if full:
				for n in 10:g._receive_card(p,_cost_card(1,"unit"),"test")
			_play(g,records[0].definition)
			var bonus:=5 if costs[0]%2==0 or costs[1]%2==0 else 0
			_check(g.state.players[p].hp==20+bonus and g.state.players[p].max_hp==20+bonus,"parity matches actual draws once incl 0 and burn")
			_check(g.state.players[p].deck.size()==2 and g.state.players[p].deck[0].definition.cost==9 and g.state.players[p].deck[1].definition.kind=="field","skips other cards preserving order")
			_check(g.state.players[p].fatigue==0,"filtered draw no fatigue")
	var g:=_game();var p:=_rich(g);g.state.players[p].deck=[]
	_play(g,records[0].definition)
	_check(g.state.players[p].hp==20 and g.state.players[p].fatigue==0,"no matching draw does not trigger parity or fatigue")
	g.state.players[p].deck=[_cost_card(2,"unit")]
	_play(g,records[0].definition)
	_check(g.state.players[p].hp==25,"one actual matching card sufficient for any")
	g.state.players[p].deck=[];_play(g,records[0].definition)
	_check(g.state.players[p].hp==25,"draw results cannot leak between actions")
	# Generic draw still fatigues.
	g._draw(p);_check(g.state.players[p].hp==24 and g.state.players[p].fatigue==1,"normal draw fatigue unchanged")

func _previous() -> void:
	for previous in ["","unit","order","field"]:
		var g:=_game();var p:=_rich(g);g.state.players[p].hand=[];g.state.players[p].deck=[]
		if not previous.is_empty():_play(g,_cost_card(1,previous).definition)
		_play(g,records[1].definition)
		_check(g.state.players[p].credits==(9 if previous=="order" else 7),"previous kind before current card, first play false")
		_check(g.state.players[p].last_played_kind=="order","new card becomes next predecessor")
		var restored:=EngineClass.new();restored.state=g.state.duplicate(true);restored._reset_budget();g=restored
		_play(g,records[1].definition)
		_check(g.state.players[p].credits==9,"previous play survives rehydrate")

func _delayed() -> void:
	var g:=_game();var p:=_rich(g);g.state.players[p].hand=[]
	_play(g,records[2].definition)
	_check(g.state.players[p].hand.size()==2 and g.state.scheduled.size()==1,"immediate draw and schedule")
	var initial_turn:int=g.state.turn
	for n in 3:
		g.state.turn=initial_turn+2*(n+1);g.state.active_player=p
		var restored:=EngineClass.new();restored.state=g.state.duplicate(true);restored._reset_budget();g=restored
		var before:int=g.state.players[p].hand.size()
		g._run_roots(g._scheduled_roots("turn_start",p))
		_check(g.state.players[p].hand.size()==before+(1 if n==1 else 0),"second matching own turn only")
	_check(g.state.scheduled.is_empty(),"scheduled group consumed once")

func _equipment() -> void:
	var g:=_game();var p:=_rich(g);var unit:Dictionary=g._new_unit(p,_compile(records[3].definition))
	var base_attack:int=unit.card.definition.attack
	for faction in [SWORD,"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",SWORD]:
		var source:=_base("同名装备","order");source["faction_id"]=str(faction);source.abilities=[{"trigger":"on_play","effects":[{"op":"noop"}]}]
		g._effect({"op":"equip","target":"chosen","tag":"装备","amount":1},g._context(p,-1,_compile(source),unit.uid));g._checkpoint()
	_check(unit.attack==base_attack+4,"only matching faction equipment contributes, same tag distinct factions")
	g._effect({"op":"unequip","target":"chosen","tag":"装备","amount":1},g._context(p,-1,_compile(_base()),unit.uid));g._checkpoint()
	_check(unit.attack==base_attack+2,"remove oldest matching tag updates faction count")
	g._suppress(unit);g._checkpoint()
	_check(unit.equipment_sources.is_empty() and unit.attack==base_attack,"suppression clears equipment and bonus")
