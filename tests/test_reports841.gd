extends "res://tests/test_engine.gd"
var records: Array
func _initialize() -> void:
	records=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures841.json")).cards
	for r in records:
		var c:=_compile(r.definition)
		_check(c.definition_hash==r.definition_hash and c.compiled_program_hash==r.compiled_program_hash,"Node/Godot parity")
		_check(not "[object" in Runtime.rules_text(c),"readable rules")
	_noop()
	_turns()
	_gap()
	print("REPORTS841: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func _noop() -> void:
	var g:=_game();var p:=_rich(g)
	var listener:=_base("指令观察者");listener.abilities=[{"trigger":"own_order_played","effects":[{"op":"heal","target":"own_hq","amount":1}]}]
	g._new_unit(p,_compile(listener));g.state.players[p].hp=15
	var hand:int=g.state.players[p].hand.size();var discard:int=g.state.discard.size();var deck:int=g.state.players[p].deck.size()
	_play(g,records[0].definition)
	_check(g.state.players[p].credits==9 and g.state.players[p].hand.size()==hand,"noop pays exactly 3 and leaves hand")
	_check(g.state.discard.size()==discard+1 and g.state.players[p].deck.size()==deck,"noop discards without draw")
	_check(g.state.players[p].hp==16,"noop still triggers order played")

func _turns() -> void:
	for side in ["owner","opponent"]:
		for active_own in [true,false]:
			var g:=_game();var p:=_rich(g)
			var spec:Dictionary=records[1].definition.duplicate(true);spec.abilities[0].premise.side=side
			g._new_unit(p,_compile(spec));var victim:Dictionary=g._new_unit(p,_compile(_base("阵亡者")))
			g.state.active_player=p if active_own else 1-p;g.state.players[p].credits=3
			var hand:int=g.state.players[p].hand.size()
			victim.destroyed=true;g._checkpoint();g._drain_deaths()
			var should:bool=active_own==(side=="owner")
			_check(g.state.players[p].hand.size()==hand+(1 if should else 0),"death draw respects current turn")
			_check(g.state.players[p].credits==3+(1 if should else 0),"death resource gain same condition")
			var context:Dictionary=g._context(p,-1,_compile(_base()))
			var condition:Dictionary={"test":"turn_owner","side":side}
			_check(g._premise_met({"test":"all","items":[condition,{"test":"not","item":{"test":"turn_owner","side":"opponent" if side=="owner" else "owner"}}]},context)==should,"nested turn condition")

func _gap() -> void:
	for reduction in [1,2]:
		var g:=_game();var p:=_rich(g)
		var spec:Dictionary=records[2].definition.duplicate(true);spec.abilities[0].effects[0].amount.attack_gap.reduction=reduction
		var uid:=_play(g,spec);var defender:Dictionary=g._unit(uid)
		var attacker:Dictionary=g._new_unit(1-p,_compile(_base("敌人")))
		_check(g._fault.is_empty() and defender.extra_rules.size()==1,"live formula initialized on deployment")
		for atk in [1,2,3,6,7,9]:
			attacker.attack=atk
			var expected:int=maxi(0,atk-(maxi(0,7-atk)/2)*reduction)
			_check(g._combat_damage(attacker,defender,"attack")==expected,"positive gap floors per hit")
			_check(g._incoming_damage(defender,4,"effect",attacker)==4,"combat-only excludes effects")
		_check(g._incoming_damage(defender,5,"combat")==5,"no unit source means no difference")
		attacker.attack=3;defender.attack=9
		_check(g._incoming_damage(defender,5,"combat",attacker)==maxi(0,5-3*reduction),"attack changes are live")
		var restored:=EngineClass.new();restored.state=g.state.duplicate(true);restored._reset_budget()
		_check(restored._incoming_damage(restored._unit(defender.uid),5,"combat",restored._unit(attacker.uid))==maxi(0,5-3*reduction),"formula survives authority reload")
		var summoned:Dictionary=g._new_unit(p,_compile(spec));g._initialize_summoned_unit(summoned)
		_check(g._incoming_damage(summoned,5,"combat",attacker)==maxi(0,5-2*reduction),"summoned passive initialized")
		g._effect({"op":"suppress","target":"chosen"},g._context(p,-1,_compile(_base()),defender.uid))
		_check(g._incoming_damage(defender,5,"combat",attacker)==5,"suppression removes damage rule")
