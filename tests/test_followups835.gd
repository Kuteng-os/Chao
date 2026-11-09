extends "res://tests/test_engine.gd"
func _initialize() -> void:
	_no_target()
	_movement()
	print("FOLLOWUPS 835: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _no_target() -> void:
	for kind in ["order","unit"]:
		var g:=_game();var p:=_rich(g)
		var c:=_base("定向伤害兼抽牌",kind)
		c.play_target={"side":"enemy","row":"any"}
		c.abilities=[{"trigger":"on_play","effects":[{"op":"damage","target":"chosen","amount":1},{"op":"draw","player":"owner","amount":1}]},{"trigger":"on_play","effects":[{"op":"gain_kredits","amount":2}]}]
		g.state.players[p].hand=[{"instance_id":"optional","card":_compile(c)}]
		_check(g.legal_targets(p,{"type":"play","hand_id":"optional"})==[-1],"empty target set still playable")
		_check(g.apply_action(p,{"type":"play","hand_id":"optional"}).is_empty(),"play without target")
		_check(g.state.players[p].hand.size()==1 and g.state.players[p].credits==12,"other effects and groups still resolve")
		_check(g.state.players[1-p].hp==20,"skip never damages headquarters")
		var enemy:Dictionary=g._new_unit(1-p,_compile(_base("目标")))
		g.state.players[p].hand=[{"instance_id":"required","card":_compile(c)}]
		_check(not -1 in g.legal_targets(p,{"type":"play","hand_id":"required"}),"available target mandatory")
		var before:=Runtime.sha(g.state)
		_check(not g.apply_action(p,{"type":"play","hand_id":"required"}).is_empty() and Runtime.sha(g.state)==before,"cannot voluntarily skip valid target")
		_check(g.apply_action(p,{"type":"play","hand_id":"required","target_uid":enemy.uid}).is_empty(),"choose valid target")
		_check(g._unit(enemy.uid).hp==3,"one damage applied")
	# No matching type counts as no target even when other unit types are present.
	var g:=_game();var p:=_rich(g);var u:=_base("仅空军指令","order")
	u.play_target={"side":"enemy","row":"any","unit_classes":["fighter","bomber"]}
	u.abilities=[{"trigger":"on_play","effects":[{"op":"damage","target":"chosen","amount":1},{"op":"draw","player":"owner","amount":1}]}]
	g._new_unit(1-p,_compile(_base("坦克")))
	g.state.players[p].hand=[{"instance_id":"filtered","card":_compile(u)}]
	_check(g.legal_targets(p,{"type":"play","hand_id":"filtered"})==[-1],"type filter empty skips")

func _movement() -> void:
	for kind in ["infantry","tank","artillery","fighter","bomber"]:
		var g:=_game();var p:=_rich(g);var c:=_base(kind);c.unit_class=kind;c.appearance.emblem=kind
		var unit:Dictionary=g._new_unit(p,_compile(c))
		_check(not g.can_move(unit.uid),"deployment wait remains "+kind)
		unit.born_turn=-1
		_check(g.can_move(unit.uid),"all unit classes can advance "+kind)
		g.state.players[p].credits=0
		_check(not g.can_move(unit.uid),"moving needs operation cost")
		g.state.players[p].credits=12
		_check(g.apply_action(p,{"type":"move","uid":unit.uid,"position":0}).is_empty(),"move commits "+kind)
		_check(g._unit(unit.uid).row=="front" and g.state.players[p].credits==11,"front position and cost "+kind)
		_check(not g.can_move(unit.uid),"no duplicate move")
