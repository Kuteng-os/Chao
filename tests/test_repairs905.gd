extends "res://tests/test_engine.gd"
var fixtures: Dictionary
func _initialize() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/repairs905.json"))
	fixtures=data.fixtures
	for key in fixtures:
		var c:=_compile(fixtures[key]);_check(c.get("compiled_program_hash")==data.hashes[key],"Node/native parity "+key)
	if failures: quit(1);return
	_test_activation()
	_test_guards()
	_test_protocol()
	print("REPAIRS 905: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func _test_activation() -> void:
	var g:=_game();var me:=_rich(g)
	var source:=_play(g,fixtures.dragon)
	var target:=_play(g,fixtures.jade)
	var plain:=_play(g,fixtures.plain)
	var command: Dictionary={"type":"activate","uid":source,"ability_index":0}
	var before: int=g.state.players[me].credits
	_check(g.state.scheduled.size()==1,"own evolution scheduled")
	_check(g.view_for(me).unit_activations[str(source)][0].error.is_empty(),"authoritative available status")
	_check(not g.view_for(1-me).unit_activations.has(str(source)),"only owner's activation controls exported")
	_check(g.apply_action(me,command).is_empty(),"activate opens selection")
	_check(g.state.pending_choice.targets==[target],"only own faction evolvable target allowed")
	_check(not g.apply_action(me,command).is_empty(),"cannot double activate while choosing")
	_check(not g.apply_action(me,{"type":"choose_target","choice_id":g.state.pending_choice.choice_id,"target_uid":plain}).is_empty(),"non-evolving target rejected")
	_check(g.apply_action(me,{"type":"choose_target","choice_id":g.state.pending_choice.choice_id,"target_uid":target}).is_empty(),"choice resumes frozen activation")
	_check(not g.state.has("pending_choice") and g._unit(target).is_empty(),"evolution completes without blocking")
	var dragon: Dictionary=g.state.units.back()
	_check(dragon.card.definition.name=="玉黄龙" and dragon.attack==5 and dragon.hp==7,"uses target's form")
	_check(g.state.scheduled.is_empty(),"old countdown consumed exactly once")
	_check(g.state.players[me].credits==before and g.attacks_used(g._unit(source))==0 and not g._unit(source).moved,"free activation independent of combat actions")
	_check(not g.apply_action(me,command).is_empty(),"same turn reuse rejected")
	var form_abilities: Array=g.view_for(me).unit_activations.get(str(dragon.uid),[])
	_check(form_abilities.size()==1,"generated dragon retains its active ability")
	g.state.turn+=2
	_check(g.activation_error(me,source,0)=="没有合法目标","no target does not burn use")
	g._leave_battlefield(g._unit(plain),false)
	var second:=_play(g,fixtures.jade)
	_check(g.activation_error(me,source,0).is_empty(),"next turn refreshed with new valid target")
	_check(g.apply_action(me,command).is_empty(),"next turn activation")
	_check(g.apply_action(me,{"type":"choose_target","choice_id":g.state.pending_choice.choice_id,"target_uid":second}).is_empty(),"second own evolution")

func _test_guards() -> void:
	var g:=_game();var me:=_rich(g);var uid:=_play(g,fixtures.gift)
	var command: Dictionary={"type":"activate","uid":uid,"ability_index":0}
	var before: int=g.state.players[me].hand.size()
	_check(not g.apply_action(1-me,command).is_empty(),"opponent cannot activate")
	_check(not g.apply_action(me,{"type":"activate","uid":uid,"ability_index":1}).is_empty(),"invalid index")
	g._unit(uid)["suppressed"]=true
	_check(not g.apply_action(me,command).is_empty(),"suppression prevents activation")
	g._unit(uid)["suppressed"]=false
	_check(g.apply_action(me,command).is_empty(),"no-target ability resolves immediately")
	_check(g.state.players[me].hand.size()==before+1,"draw exactly once")
	_check(not g.apply_action(me,command).is_empty(),"no-target ability once each turn")
	g.state.turn+=2
	_check(g.apply_action(me,command).is_empty(),"next turn no-target ability resets")
	g._leave_battlefield(g._unit(uid),false)
	_check(not g.apply_action(me,command).is_empty(),"departed source invalid")
	var no_target:=_play(g,fixtures.dragon)
	_check(not g.apply_action(me,{"type":"activate","uid":no_target,"ability_index":0}).is_empty(),"no evolution target rejected without pending choice")
	_check(g._unit(no_target).get("activation_counts",{}).is_empty() and not g.state.has("pending_choice"),"failed use never locks turn")

func _test_protocol() -> void:
	var controller=load("res://scripts/network/match_controller.gd").new()
	_check(not controller._normalize_action({"type":"activate","uid":1,"ability_index":0}).is_empty(),"LAN active command")
	_check(controller._normalize_action({"type":"activate","uid":1,"ability_index":0,"target_uid":2}).is_empty(),"LAN rejects extra fields")
	controller.free()
