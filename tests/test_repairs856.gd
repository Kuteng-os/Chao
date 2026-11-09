extends "res://tests/test_engine.gd"
var f: Dictionary
func _initialize() -> void:
 f=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/repairs856.json"))
 var parity: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/parity856.json"))
 for key in f:
  var c:=_compile(f[key]);if c.ok:_check(c.compiled_program_hash==parity[key].compiled_program_hash,"Node/native parity "+key)
 if failures:quit(1);return
 _received()
 for mode in ["combat","end"]:_lifetimes(mode)
 _stacks()
 _start_death()
 _off_turn()
 print("REPAIRS 856: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)

func _received() -> void:
 var g:=_game();var me:=_rich(g);var unit:=_base();unit.health=20
 var target: Dictionary=g._new_unit(1-me,_compile(unit));var tank: Dictionary=g._new_unit(me,_compile(unit))
 unit.unit_class="infantry";var infantry: Dictionary=g._new_unit(me,_compile(unit))
 _play(g,f.tank,target.uid)
 target=g._unit(target.uid);tank=g._unit(tank.uid);infantry=g._unit(infantry.uid)
 _check(target.attack==0,"selected enemy attack set to zero")
 _check(g._incoming_damage(target,3,"combat",tank)==6,"tank combat damage doubles")
 _check(g._incoming_damage(target,3,"combat",infantry)==3,"infantry not doubled")
 _check(g._incoming_damage(target,3,"effect",{},tank.card)==6,"departed tank's effect damage uses source card identity")
 _check(g._incoming_damage(target,3,"effect",{},_compile(f.tank))==3,"ordinary order has no tank identity")
 g._effect({"op":"grant_unit_class","target":"self","unit_class":"tank","duration":"battle"},g._context(me,infantry.uid,infantry.card))
 _check(g._incoming_damage(target,3,"effect",infantry)==6,"additional tank identity matches source filter")
 _check(g._incoming_damage(target,0,"combat",tank)==0,"zero damage stays zero")
 var before: int=target.hp;g._resolve_combat(tank,target)
 _check(target.hp==before-6,"combat multiplier applies exactly once")
 before=target.hp;g._unit_damage(target,3,g._context(me,tank.uid,tank.card))
 _check(target.hp==before-6,"actual effect packet applies multiplier exactly once")
 g._effect({"op":"grant_keyword","target":"self","keyword_id":"core.immune","duration":"battle"},g._context(1-me,target.uid,target.card))
 before=target.hp;g._unit_damage(target,3,g._context(me,tank.uid,tank.card))
 _check(target.hp==before,"immunity overrides vulnerability")
 var hq: Dictionary=g.state.players[1-me]
 g._effect({"op":"modify_incoming_damage","target":"enemy_hq","amount":0,"multiplier":2,"source_unit_classes":["tank"],"damage_kind":"both","duration":"next_own_turn_start"},g._context(me,-1,_compile(f.tank)))
 before=hq.hp;g._effect({"op":"damage","target":"enemy_hq","amount":2},g._context(me,tank.uid,tank.card))
 _check(hq.hp==before-4,"HQ effect receives source-filtered multiplier")

func _lifetimes(mode: String) -> void:
 var g:=_game();var me:=_rich(g);var target: Dictionary=g._new_unit(1-me,_compile(_base()))
 var ctx: Dictionary=g._context(1-me,target.uid,target.card)
 g._effect({"op":"modify_stats","target":"self","attack_delta":2,"health_delta":0,"duration":"battle"},ctx)
 _play(g,f[mode],target.uid)
 target=g._unit(target.uid)
 _check(target.attack==0 and g._incoming_damage(target,2,"combat")==3,"debuff active immediately "+mode)
 _check(g._incoming_damage(target,2,"effect")==2,"combat-only bonus excludes effects")
 _check(g.apply_action(me,{"type":"end_turn"}).is_empty(),"advance enemy turn "+mode)
 target=g._unit(target.uid)
 _check(target.attack==0 and g._incoming_damage(target,2,"combat")==3,"not expired at caster end "+mode)
 # Timing is owned by the original caster, not the current target controller.
 g._effect({"op":"take_control","target":"chosen","duration":"battle"},g._context(me,-1,_compile(f[mode]),target.uid))
 _check(g.apply_action(1-me,{"type":"end_turn"}).is_empty(),"advance own turn "+mode)
 target=g._unit(target.uid)
 _check(target.attack==5 and g._incoming_damage(target,2,"combat")==2,"expires on requested boundary preserving other buff "+mode)
 _check(target.card.get("match_layers",[]).is_empty(),"temporary debuff never becomes permanent")

func _stacks() -> void:
 var g:=_game();var me:=_rich(g);var unit: Dictionary=g._new_unit(me,_compile(_base()))
 var ctx: Dictionary=g._context(me,unit.uid,unit.card)
 g._effect({"op":"modify_stacks","target":"self","stack":"counter","amount":3,"duration":"battle"},ctx)
 g._effect({"op":"modify_stacks","target":"self","stack":"counter","amount":2,"duration":"next_own_turn_start"},ctx)
 g._effect({"op":"modify_stacks","target":"self","stack":"heavy_armor","amount":2,"duration":"next_opponent_turn_end"},ctx)
 _check(g.stack_count(unit,"counter")==5 and g.stack_count(unit,"heavy_armor")==2,"custom and armor layers apply")
 g.apply_action(me,{"type":"end_turn"});unit=g._unit(unit.uid);_check(g.stack_count(unit,"counter")==5,"custom layer survives own end")
 g.apply_action(1-me,{"type":"end_turn"});unit=g._unit(unit.uid)
 _check(g.stack_count(unit,"counter")==3 and g.stack_count(unit,"heavy_armor")==0,"each stack layer expires without deleting permanent stack")

func _start_death() -> void:
 var g:=_game();var me:=_rich(g);var unit: Dictionary=g._new_unit(me,_compile(_base()))
 g._effect({"op":"modify_stats","target":"self","attack_delta":0,"health_delta":3,"duration":"next_own_turn_start"},g._context(me,unit.uid,unit.card))
 unit.damage_taken=5;g._checkpoint();_check(not g._unit(unit.uid).is_empty(),"temporary defense keeps wounded unit alive")
 g.apply_action(me,{"type":"end_turn"});g.apply_action(1-me,{"type":"end_turn"})
 _check(g._unit(unit.uid).is_empty(),"expiration recomputes lethal defense loss before start triggers")

func _off_turn() -> void:
 var g:=_game();var active:=_rich(g);var owner:=1-active
 var unit: Dictionary=g._new_unit(owner,_compile(_base()));var ctx: Dictionary=g._context(owner,unit.uid,unit.card)
 g._effect({"op":"modify_stats","target":"self","attack_delta":2,"health_delta":0,"duration":"next_own_turn_start"},ctx)
 g._effect({"op":"modify_operation_cost","target":"self","cost_delta":2,"duration":"next_opponent_turn_end"},ctx)
 _check(unit.attack==5,"off-turn effect applies")
 g.apply_action(active,{"type":"end_turn"});unit=g._unit(unit.uid)
 _check(unit.attack==3 and unit.operation_costs.size()==1,"off-turn next own start expires; opponent-next-end skips current enemy turn")
 g.apply_action(owner,{"type":"end_turn"});unit=g._unit(unit.uid);_check(unit.operation_costs.size()==1,"next enemy turn includes its actions")
 g.apply_action(active,{"type":"end_turn"});unit=g._unit(unit.uid);_check(unit.operation_costs.is_empty(),"off-turn next enemy end expires")
