extends "res://tests/test_engine.gd"

func _initialize() -> void:
	for seat in [0,1]:
		for kind in ["infantry","tank","artillery","fighter","bomber"]:
			for blitz in [false,true]:
				for first in ["move","attack"]: sequence(seat,kind,blitz,first)
		smoke(seat)
	print("RULES901: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func unit(g:RefCounted,seat:int,kind:String,keywords:Array=[]) -> Dictionary:
	var d:=_base(kind);d.unit_class=kind;d.health=12;d.operation_cost=0;d.keywords=keywords
	var u:Dictionary=g._new_unit(seat,_compile(d));u.born_turn=-1;return u

func sequence(seat:int,kind:String,blitz:bool,first:String) -> void:
	var g:=_game();g.state.active_player=seat;g.state.players[seat].credits=12
	var u:=unit(g,seat,kind,[{"id":"core.blitz","version":1,"params":{}}] if blitz else [])
	var action:={"type":first,"uid":u.uid}
	if first=="attack":
		if kind in ["infantry","tank"]:
			var target:=unit(g,1-seat,"infantry");target.row="front";target.hp=1;target.damage_taken=11
			g._position_unit(target);action.target_uid=target.uid
		else:action.target_uid=-1
	_check(g.apply_action(seat,action).is_empty(),kind+" first action legal")
	var second:={"type":"attack" if first=="move" else "move","uid":u.uid}
	if first=="move":second.target_uid=-1
	var allowed:=kind=="tank" or kind in ["fighter","bomber"] and blitz
	_check((not g.legal_targets(seat,second).is_empty() if first=="move" else g.can_move(u.uid))==allowed,kind+" second action advertised correctly")
	var before:=Runtime.sha(g.state)
	_check(g.apply_action(seat,second).is_empty()==allowed,kind+" authority matches legality")
	if not allowed:
		_check(Runtime.sha(g.state)==before,"Rejected action changes nothing")
		var reconnected:=EngineClass.new();reconnected.state=Runtime._normalized(JSON.parse_string(JSON.stringify(g.state)));reconnected._reset_budget()
		_check(not reconnected.apply_action(seat,second).is_empty(),"Reconnect preserves operation restriction")
		g._effect({"op":"reset_operations","target":"self"},g._context(seat,u.uid,u.card))
		_check(g.apply_action(seat,second).is_empty(),"Explicit reset still restores action")

func smoke(seat:int) -> void:
	var g:=_game();g.state.active_player=seat;g.state.players[seat].credits=12
	var attacker:=unit(g,seat,"fighter")
	var guard:=unit(g,1-seat,"infantry",[{"id":"core.guard","version":1,"params":{}},{"id":"core.smokescreen","version":1,"params":{}}])
	g._position_unit(guard,1)
	var ally:=unit(g,1-seat,"infantry");g._position_unit(ally,2)
	var attack:={"type":"attack","uid":attacker.uid}
	var legal:Array=g.legal_targets(seat,attack)
	_check(g.smokescreen_active(guard) and not g.guard_active(guard),"Support smoke disables guard")
	_check(not guard.uid in legal and ally.uid in legal and -1 in legal,"Hidden guard protects neither neighbor nor HQ")
	g._consume_keyword(guard,"core.smokescreen")
	legal=g.legal_targets(seat,attack)
	_check(g.guard_active(guard) and guard.uid in legal and not ally.uid in legal and not -1 in legal,"Guard resumes after smoke loss")
	g._effect({"op":"grant_keyword","target":"self","keyword_id":"core.smokescreen","duration":"end_of_turn"},g._context(guard.owner,guard.uid,guard.card))
	_check(not g.guard_active(guard),"Granted smoke also disables guard")
	g._remove_from_line(guard);guard.row="front";g._position_unit(guard)
	g._remove_from_line(ally);ally.row="front";g._position_unit(ally)
	var history:Dictionary=guard.get("consumed_keyword_history",{}).duplicate(true)
	_check(g._has_keyword(guard,"core.smokescreen") and not g.smokescreen_active(guard) and g.guard_active(guard),"Frontline smoke is inactive; guard operates")
	legal=g.legal_targets(seat,attack)
	_check(guard.uid in legal and not ally.uid in legal,"Frontline smoked guard is attackable and guards its neighbor")
	_check(guard.get("consumed_keyword_history",{})==history,"Reading inactive smoke does not consume keyword or raise loss event")
	g._suppress(guard)
	_check(not g.guard_active(guard) and ally.uid in g.legal_targets(seat,attack),"Suppression removes guard normally")
