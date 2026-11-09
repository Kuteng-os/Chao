extends "res://tests/test_engine.gd"
var fixtures: Dictionary
func _initialize() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/repairs863.json"))
	fixtures=data.fixtures
	for key in fixtures:
		var c:=_compile(fixtures[key]);_check(c.get("compiled_program_hash")==data.hashes[key],"Node/native parity "+key)
	if failures: quit(1);return
	_test_overflow()
	_test_sin_aura()
	_test_immunity()
	_test_play_events()
	_test_hand_choices()
	_test_history()
	print("REPAIRS 863: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func _test_overflow() -> void:
	var g:=_game();var me:=_rich(g);var c:=_compile(fixtures.overflow);var ctx: Dictionary=g._context(me,-1,c)
	g.state.players[me].max_credits=5;g.state.players[me].credits=5
	g._effect({"op":"gain_kredits","amount":1,"allow_overflow":true},ctx)
	_check(g.state.players[me].credits==6 and g.state.players[me].max_credits==5,"overflow does not create slots")
	g._effect({"op":"gain_kredits","amount":1},ctx);_check(g.state.players[me].credits==6,"normal gain never destroys overflow")
	g.state.players[me].credits=4;g._effect({"op":"gain_kredits","amount":2},ctx);_check(g.state.players[me].credits==5,"normal cap retained")
	g.state.players[me].credits=10
	_check(g.apply_action(me,{"type":"end_turn"}).is_empty(),"first end turn")
	_check(g.apply_action(1-me,{"type":"end_turn"}).is_empty(),"second end turn")
	_check(g.state.players[me].credits==g.state.players[me].max_credits,"overflow resets next own turn")

func _test_sin_aura() -> void:
	var g:=_game();var me:=_rich(g)
	var a: Dictionary=_base("左邻");a["sin"]="envy"
	var left: Dictionary=g._new_unit(me,_compile(a),"",false,0);var source: Dictionary=g._new_unit(me,_compile(fixtures.aura),"",false,1);var right: Dictionary=g._new_unit(me,_compile(_base("右邻")),"",false,2);g._checkpoint()
	_check(left.attack==3 and source.attack==3 and right.attack==5,"adjacent aura excludes envy but includes unset sin")
	_check(g._matches_unit_filter(right,{"sin":null}) and not g._matches_unit_filter(left,{"sin":null}),"explicit sin null")
	_check(g._matches_unit_filter(left,{"sins":["envy",null]}) and not g._matches_unit_filter(left,{"exclude_sins":["envy"]}),"sin inclusion exclusion")
	g._effect({"op":"suppress","target":"self"},g._context(me,source.uid,source.card));g._checkpoint();_check(right.attack==3,"suppression removes adjacent aura")

func _test_immunity() -> void:
	var g:=_game();var me:=_rich(g);var id:=_play(g,fixtures.immune);var u: Dictionary=g._unit(id)
	var enemy: Dictionary=g._new_unit(1-me,_compile(_base("攻击方")))
	_check(g._incoming_damage(u,999,"combat",enemy)==0,"combat immunity handles arbitrary damage")
	_check(g._incoming_damage(u,3,"effect",enemy)==3,"skill damage retained")
	_check(g._combat_damage(enemy,u,"attack")==0 and g._combat_damage(enemy,u,"retaliation")==0,"both attack and retaliation damage blocked")
	g._effect({"op":"suppress","target":"self"},g._context(me,u.uid,u.card));_check(g._incoming_damage(u,3,"combat",enemy)==3,"suppression removes immunity")

func _test_play_events() -> void:
	var g:=_game();var me:=_rich(g);g.state.players[me].max_credits=20;g.state.players[me].credits=20
	var listener: Dictionary=g._new_unit(me,_compile(fixtures.listener));var before: int=g.state.players[1-me].hp
	var c: Dictionary=fixtures.chain.duplicate(true);c.name="普通指令";c.abilities=[{"trigger":"on_play","effects":[{"op":"gain_kredits","amount":1}]}];c.tokens=[];c["sin"]="gloom"
	_play(g,c);_check(g.state.players[1-me].hp==before-1,"sin-filtered order fires listener")
	c["sin"]="envy";_play(g,c);_check(g.state.players[1-me].hp==before-1,"envy order excluded")
	c["sin"]=null;_play(g,c);_check(g.state.players[1-me].hp==before-1,"unset sin excluded from six-value list")
	c.kind="field";c.appearance.emblem="field";c["sin"]="pride";_play(g,c);_check(g.state.players[1-me].hp==before-2,"field play fires universal event")
	c=_base("暴怒单位");c["sin"]="wrath";_play(g,c);_check(g.state.players[1-me].hp==before-3,"unit deployment fires universal event once")
	c={"schema_version":"1.0.0","ruleset_version":"frontline-1","name":"隐蔽反制","flavor_text":"","kind":"counter","counter_trigger":"enemy_order_played","unit_class":null,"cost":0,"operation_cost":0,"attack":0,"health":0,"keywords":[],"play_target":null,"abilities":[{"trigger":"on_reveal","effects":[{"op":"gain_kredits","amount":1}]}],"tokens":[],"appearance":{"emblem":"counter"},"sin":"wrath"}
	_play(g,c);_check(g.state.players[1-me].hp==before-3,"arming counter stays secret and does not emit event")
	_check(not g._premise_met({"test":"hand_contains","player":"owner","filter":{"card_name":"隐蔽反制"}},g._context(me,listener.uid,listener.card)),"armed counter is not in actual hand")
	var summoned: Dictionary=g._new_unit(me,_compile({"schema_version":"1.0.0","ruleset_version":"frontline-1","name":"牌库部署","flavor_text":"","kind":"unit","unit_class":"infantry","cost":0,"operation_cost":0,"attack":1,"health":1,"keywords":[],"play_target":null,"abilities":[],"tokens":[],"appearance":{"emblem":"infantry"},"sin":"wrath"}))
	g._initialize_deployed_unit(summoned);g._checkpoint()
	_check(g.state.players[1-me].hp==before-3,"effect deployment is not a card play")
	_check(g.apply_action(me,{"type":"end_turn"}).is_empty(),"counter turn passes")
	var other: Dictionary=fixtures.chain.duplicate(true);other.abilities=[{"trigger":"on_play","effects":[{"op":"gain_kredits","amount":1}]}];other.tokens=[]
	_play(g,other);_check(g.state.players[1-me].hp==before-4,"revealed counter emits once on owner side")

func _test_hand_choices() -> void:
	for both in [false,true]:
		var g:=_game();var me:=_rich(g)
		g.state.players[me].hand=[]
		if both:
			for name in ["苍","赫"]:
				var c: Dictionary=fixtures.chain.duplicate(true);c.name=name;g.state.players[me].hand.append({"instance_id":name,"card":_compile(c)})
		_play(g,fixtures.choices)
		_check(g.state.has("pending_choice"),"conditional choice opens")
		_check(g.state.pending_choice.options.size()==(3 if both else 2),"only valid options are offered")
		var choice: Dictionary=g.state.pending_choice
		_check(g.apply_action(me,{"type":"choose_card","choice_id":choice.choice_id,"option_index":2 if both else 1}).is_empty(),"conditional choice resolves")
		_check(g.state.players[me].hand.back().card.definition.name==("茈" if both else "赫"),"filtered index selects correct branch")

func _test_history() -> void:
	var g:=_game();var me:=_rich(g);g.state.players[me].hand=[]
	var red: Dictionary=fixtures.chain.duplicate(true);red.name="赫";red.abilities=[{"trigger":"on_play","effects":[{"op":"gain_kredits","amount":1}]}];red.tokens=[]
	_play(g,red);_play(g,fixtures.chain)
	_check(g.state.players[me].hand.size()==1 and g.state.players[me].hand[0].card.definition.name=="茈","previous card sees previous name, not itself")
	_play(g,fixtures.history);_check(g.state.players[me].hand.size()==2,"both named cards used this turn")
	_check(g.apply_action(me,{"type":"end_turn"}).is_empty(),"history end turn")
	_check(g.apply_action(1-me,{"type":"end_turn"}).is_empty(),"history next turn")
	g.state.players[me].hand=[];_play(g,fixtures.chain);_check(g.state.players[me].hand.is_empty(),"previous card from old turn rejected")
	_play(g,fixtures.history);_check(g.state.players[me].hand.is_empty(),"per-turn history does not include prior turn red")
