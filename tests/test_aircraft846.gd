extends "res://tests/test_engine.gd"

func _initialize() -> void:
	for seat in [0,1]:
		for kind in ["fighter","bomber"]:
			for blitz in [false,true]:
				for first in ["move","attack"]:
					_sequence(seat,kind,blitz,first)
				_refresh_exception(seat,kind,blitz)
		_other_classes(seat)
	print("AIRCRAFT846: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _aircraft(g: RefCounted, seat: int, kind: String, blitz: bool) -> int:
	var d:=_base(kind);d.unit_class=kind;d.appearance.emblem=kind
	if blitz:d.keywords=[{"id":"core.blitz","version":1,"params":{}}]
	var u:Dictionary=g._new_unit(seat,_compile(d));u.born_turn=-1
	return int(u.uid)

func _sequence(seat: int, kind: String, blitz: bool, first: String) -> void:
	var g:=_game();g.state.active_player=seat;_rich(g)
	var uid:=_aircraft(g,seat,kind,blitz)
	var a:={"type":first,"uid":uid}
	if first=="attack":a.target_uid=-1
	_check(g.apply_action(seat,a).is_empty(),kind+" first action succeeds")
	var second:={"type":"attack" if first=="move" else "move","uid":uid}
	if first=="move":second.target_uid=-1
	_check((not g.legal_targets(seat,second).is_empty() if first=="move" else g.can_move(uid))==blitz,kind+" legal actions agree with Blitz exception")
	if first=="move":_check(g._unit(uid).attacked==not blitz,"exhaustion matches attack availability")
	var before:=Runtime.sha(g.state)
	_check(g.apply_action(seat,second).is_empty()==blitz,"authority rejects illegal second action")
	if not blitz:
		_check(Runtime.sha(g.state)==before,"rejection does not consume resources or change state")
		var u:Dictionary=g._unit(uid)
		g._effect({"op":"set_attack_limit","target":"self","attacks":2,"duration":"battle"},g._context(seat,uid,u.card))
		_check((g.legal_targets(seat,second).is_empty() if first=="move" else not g.can_move(uid)),"Fury/extra attack is not an extra move permission")
		var restored:=EngineClass.new();restored.state=Runtime._normalized(JSON.parse_string(JSON.stringify(g.state)));restored._reset_budget();g=restored
		_check(not g.apply_action(seat,second).is_empty(),"reconnect cannot bypass the lock")
		var ai:Dictionary=g.ai_action(seat)
		_check(not(ai.get("type")==second.type and ai.get("uid")==uid),"practice AI does not select the forbidden operation")
		_check(g.apply_action(seat,{"type":"end_turn"}).is_empty(),"end turn")
		_check(g.apply_action(1-seat,{"type":"end_turn"}).is_empty(),"opponent end turn")
		_check(g.apply_action(seat,second).is_empty(),"new turn clears restriction")

func _refresh_exception(seat: int, kind: String, blitz: bool) -> void:
	var g:=_game();g.state.active_player=seat;_rich(g)
	var uid:=_aircraft(g,seat,kind,blitz)
	g.apply_action(seat,{"type":"move","uid":uid})
	var u:Dictionary=g._unit(uid)
	g._effect({"op":"reset_operations","target":"self"},g._context(seat,uid,u.card))
	_check(not g.legal_targets(seat,{"type":"attack","uid":uid}).is_empty(),"explicit operation reset restores attack")
	# Evaluate the current keyword, consistently with the attack-then-move rule.
	u.moved=true
	if not blitz:g._effect({"op":"grant_keyword","target":"self","keyword_id":"core.blitz","duration":"battle"},g._context(seat,uid,u.card))
	_check(not g.legal_targets(seat,{"type":"attack","uid":uid}).is_empty(),"gained Blitz enables remaining attack")
	g._suppress(u)
	_check(g.legal_targets(seat,{"type":"attack","uid":uid}).is_empty(),"removed Blitz no longer bypasses movement")

func _other_classes(seat: int) -> void:
	for kind in ["infantry","tank","artillery"]:
		var g:=_game();g.state.active_player=seat;_rich(g)
		var uid:=_aircraft(g,seat,kind,true)
		var u:Dictionary=g._unit(uid)
		g._effect({"op":"grant_unit_class","target":"self","unit_class":"fighter","duration":"match"},g._context(seat,uid,u.card))
		g.apply_action(seat,{"type":"move","uid":uid})
		_check(g.legal_targets(seat,{"type":"attack","uid":uid}).is_empty()==(kind!="tank"),"secondary fighter identity does not change primary class movement")
