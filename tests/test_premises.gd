extends "res://tests/test_engine.gd"

func _initialize() -> void:
	for seat in [0,1]: _comparisons(seat)
	_damage_rules()
	_contract()
	_counter_condition()
	print("PREMISES AND DAMAGE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _comparison() -> Dictionary:
	return {"test":"compare","left":{"stat":"enemy_unit_count"},"cmp":"gt","right":{"stat":"friendly_unit_count"}}

func _conditional(p: Dictionary) -> Dictionary:
	var spec := _base("以寡敌众", "order")
	spec.abilities=[{"trigger":"on_play","premise":p,"effects":[{"op":"draw","player":"owner","amount":2}]}]
	return spec

func _comparisons(seat: int) -> void:
	var game := _game()
	game.state.active_player=seat
	var before: int = game.state.players[seat].hand.size()
	_play(game,_conditional(_comparison()))
	_check(game.state.players[seat].hand.size()==before,"equal zero counts do not draw")
	game._new_unit(1-seat,_compile(_base()))
	_play(game,_conditional(_comparison()))
	_check(game.state.players[seat].hand.size()==before+2,"more enemy units draw two from either seat")
	game._new_unit(seat,_compile(_base()))
	before=game.state.players[seat].hand.size()
	_play(game,_conditional(_comparison()))
	_check(game.state.players[seat].hand.size()==before,"equal counts do not draw")
	var nested := {"test":"all","items":[{"test":"not","item":_comparison()},{"test":"any","items":[{"test":"compare","left":{"stat":"friendly_unit_count"},"cmp":"eq","right":1},_comparison()]}]}
	_play(game,_conditional(nested))
	_check(game.state.players[seat].hand.size()==before+2,"nested all any not combinations resolve")
	var order := _conditional({"test":"compare","left":{"stat":"enemy_unit_count"},"cmp":"gte","right":1})
	order.abilities[0].effects=[{"op":"destroy","target":"all_enemy_units"},{"op":"draw","player":"owner","amount":1}]
	before=game.state.players[seat].hand.size()
	_play(game,order)
	_check(game.state.players[seat].hand.size()==before+1,"group condition snapshots once before all effects")
	game.state.players[seat].hand=[]
	var unit := _base()
	unit.abilities=_conditional({"test":"compare","left":{"stat":"friendly_unit_count"},"cmp":"eq","right":2}).abilities
	before=game.state.players[seat].hand.size()
	_play(game,unit)
	_check(game.state.players[seat].hand.size()==before+2,"deployment condition includes source")
	var choice:=_conditional(_comparison())
	choice.abilities[0].effects=[{"op":"damage","target":"chosen","amount":1}]
	choice.abilities[0]["target"]={"side":"enemy","row":"any","timing":"trigger"}
	_play(game,choice)
	_check(game.state.get("pending_choice",{}).is_empty(),"false condition never asks for trigger-time target")
	_check("若敌方在场单位更多" in Runtime.rules_text(_compile(_conditional(_comparison()))),"client renders premise")

func _ratio(rounding: String, ignore_armor: bool) -> Dictionary:
	return {"op":"set_combat_damage_multiplier","target":"self","against":"any","applies_to":"both","multiplier":1,"divisor":2,"rounding":rounding,"ignore_armor":ignore_armor,"duration":"battle"}

func _damage_rules() -> void:
	var game := _game()
	var owner: int=game.state.active_player
	var armor := _base("重甲")
	armor.keywords=[{"id":"standard.heavy_armor","version":1,"params":{"x":2}}]
	game.state.active_player=1-owner
	var defender := _play(game,armor)
	game.state.active_player=owner
	for rounding in ["ceil","floor"]:
		var spec := _base("破甲")
		spec.abilities=[{"trigger":"on_play","effects":[_ratio(rounding,true)]}]
		var attacker := _play(game,spec)
		var u: Dictionary=game._unit(attacker)
		var d: Dictionary=game._unit(defender)
		for phase in ["attack","retaliation"]:
			_check(game._combat_damage(u,d,phase)==(2 if rounding=="ceil" else 1),"half odd attack respects rounding and bypass in both phases")
		_check(game.stack_count(d,"heavy_armor")==2,"penetration does not consume armor stacks")
		_check(game._combat_damage(u,{},"attack")== (2 if rounding=="ceil" else 1),"HQ also receives fractional combat damage")
		u.combat_damage_rules[-1].ignore_armor=false
		_check(game._combat_damage(u,d,"attack")==0,"normal armor applies after rounding")
		u.combat_damage_rules[-1].ignore_armor=true
		u.combat_damage_rules[-1].applies_to="attack"
		_check(game._combat_damage(u,d,"retaliation")==1,"attack-only rule leaves retaliation normal")
		u.attack=0
		_check(game._combat_damage(u,d,"attack")==0,"zero remains zero")
		u.attack=4
		_check(game._combat_damage(u,d,"attack")==2,"even attack halves exactly")
		game._leave_battlefield(u,false)
	_check("无视重甲" in Runtime.rules_text(_compile({"schema_version":"1.0.0", "ruleset_version":"frontline-1", "name":"甲", "flavor_text":"", "kind":"unit", "unit_class":"tank", "cost":1,"operation_cost":1,"attack":3,"health":4,"keywords":[],"play_target":null,"abilities":[{"trigger":"on_play","effects":[_ratio("ceil",true)]}],"tokens":[],"appearance":{"emblem":"tank"}})),"damage text includes bypass")

func _contract() -> void:
	var p := _comparison()
	for i in 4:p={"test":"not","item":p}
	_check(not Runtime.compile_card(_conditional(p),Runtime.builtin_keywords()).ok,"reject deeply nested premise")
	var bad:=_conditional(_comparison())
	bad.abilities[0].premise.left={"stat":"eval"}
	_check(not Runtime.compile_card(bad,Runtime.builtin_keywords()).ok,"reject unknown condition stat")
	var effect:=_ratio("ceil",true)
	effect.erase("rounding")
	var spec:=_base()
	spec.abilities=[{"trigger":"on_play","effects":[effect]}]
	_check(not Runtime.compile_card(spec,Runtime.builtin_keywords()).ok,"fractional damage requires explicit rounding")
	var kw:Dictionary=_read("keywords/standard_heavy_armor.json")
	kw.id="custom.premise";kw.parameters={};kw.implementation.abilities=_conditional(_comparison()).abilities
	_check(Runtime.validate_keyword(kw).is_empty(),"conditional keyword template validates")

func _counter_condition() -> void:
	var game:=_game()
	var owner: int=game.state.active_player
	var c:=_base("条件反制","counter")
	c.appearance.emblem="counter";c["counter_trigger"]="enemy_order_played"
	c.abilities=[{"trigger":"on_reveal","premise":_comparison(),"effects":[{"op":"draw","player":"owner","amount":2}]}]
	_play(game,c)
	var credits: int=game.state.players[owner].credits
	game.apply_action(owner,{"type":"end_turn"})
	_play(game,_conditional(_comparison()))
	_check(game.state.players[owner].counters.size()==1 and game.state.players[owner].credits==credits,"failed premise keeps counter hidden and unpaid")
	game._new_unit(1-owner,_compile(_base()))
	_play(game,_conditional(_comparison()))
	_check(game.state.players[owner].counters.is_empty() and game.state.players[owner].credits==credits-1,"satisfied premise reveals and pays counter")
