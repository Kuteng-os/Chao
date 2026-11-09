extends "res://tests/test_engine.gd"

func _initialize() -> void:
	for owner in [0,1]: _field_lifecycle(owner)
	_contract()
	_generated_media()
	print("FIELD TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _field(abilities: Array = []) -> Dictionary:
	var spec:=_base("测试场地","field")
	spec.appearance.emblem="field"
	spec.abilities=abilities
	return spec

func _aura(target: String, attack: int, health: int) -> Dictionary:
	return {"trigger":"while_active","effects":[{"op":"modify_stats","target":target,"attack_delta":attack,"health_delta":health,"duration":"battle"}]}

func _field_lifecycle(owner: int) -> void:
	var game:=_game()
	game.state.active_player=owner
	var ally:Dictionary=game._new_unit(owner,_compile(_base()))
	var enemy:Dictionary=game._new_unit(1-owner,_compile(_base()))
	var base_attack:int=ally.attack
	var original_hp:int=ally.hp
	var spec:=_field([_aura("all_friendly_units",2,2),{"trigger":"own_turn_start","effects":[{"op":"heal","target":"own_hq","amount":2}]},{"trigger":"opponent_turn_end","effects":[{"op":"damage","target":"enemy_hq","amount":1}]}])
	_play(game,spec)
	ally=game._unit(ally.uid)
	enemy=game._unit(enemy.uid)
	_check(game.state.field.owner==owner,"field has controller")
	_check(game.state.units.size()==2,"field occupies no unit slot")
	_check(ally.attack==base_attack+2 and ally.hp==original_hp+2,"existing friendly units gain field aura")
	_check(enemy.attack==base_attack,"opponent unaffected by friendly aura")
	var later:Dictionary=game._new_unit(owner,_compile(_base("后来者")))
	_check(later.attack==base_attack+2,"later deployment gains continuous aura")
	ally.damage_taken=1
	game._checkpoint()
	game._checkpoint()
	_check(ally.attack==base_attack+2 and ally.hp==original_hp+1,"checkpoints do not stack or heal aura")
	game.state.players[owner].hp=10
	_check(game.apply_action(owner,{"type":"end_turn"}).is_empty(),"end field owner turn")
	var hp:int=game.state.players[1-owner].hp
	_check(game.apply_action(1-owner,{"type":"end_turn"}).is_empty(),"opponent end triggers field")
	_check(game.state.players[owner].hp==12 and game.state.players[1-owner].hp==hp-1,"both turn directions use field controller")
	var view:Dictionary=game.view_for(1-owner)
	_check(view.field.card.definition==spec,"field public to both seats")
	game.state.active_player=1-owner
	var next:=_field([_aura("all_enemy_units",-1,0)])
	next.name="替换场地"
	_play(game,next)
	ally=game._unit(ally.uid)
	enemy=game._unit(enemy.uid)
	_check(game.state.field.card.definition.name=="替换场地","single global field replaced by opponent")
	_check(ally.attack==base_attack-1 and ally.hp==original_hp-1,"old aura removed, damage remains")
	_check(game.state.discard.any(func(e):return e.card.definition.name==spec.name),"old field discarded")
	_check(not game.state.discard.any(func(e):return e.card.definition.name==next.name),"current field not discarded")
	_play(game,_field())
	ally=game._unit(ally.uid)
	enemy=game._unit(enemy.uid)
	_check(ally.attack==base_attack and ally.hp==original_hp-1,"cosmetic field also replaces and removes aura")
	var layers:=_field([{"trigger":"while_active","effects":[{"op":"modify_stacks","target":"all_friendly_units","stack":"heavy_armor","amount":2,"duration":"battle"},{"op":"modify_operation_cost","target":"all_friendly_units","cost_delta":-1,"duration":"battle"}]}])
	_play(game,layers)
	enemy=game._unit(enemy.uid)
	_check(game.stack_count(enemy,"heavy_armor")==2 and enemy.operation_cost==0,"armor and operation aura applied")
	_play(game,_field())
	ally=game._unit(ally.uid)
	enemy=game._unit(enemy.uid)
	_check(game.stack_count(enemy,"heavy_armor")==0 and enemy.operation_cost==1,"all aura types clean up")

func _contract() -> void:
	var spec:=_field([_aura("all_friendly_units",1,0)])
	_check(_compile(spec).ok,"field aura compiles")
	for trigger in ["on_death","on_summon","on_reveal"]:
		var bad:=_field([{ "trigger":trigger,"effects":[{"op":"draw","player":"owner","amount":1}]}])
		_check(not Runtime.compile_card(bad,Runtime.builtin_keywords()).ok,"field rejects unit/counter lifecycle")
	for effect in [{"op":"draw","player":"owner","amount":1},{"op":"damage","target":"all_enemy_units","amount":1},{"op":"modify_stats","target":"self","attack_delta":1,"health_delta":0,"duration":"battle"},{"op":"modify_stats","target":"all_friendly_units","attack_delta":{"stat":"enemy_unit_count"},"health_delta":0,"duration":"battle"}]:
		var bad:=_field([{"trigger":"while_active","effects":[effect]}])
		_check(not Runtime.compile_card(bad,Runtime.builtin_keywords()).ok,"invalid continuous operations rejected")
	var unit:=_base()
	unit.abilities=spec.abilities
	_check(Runtime.compile_card(unit,Runtime.builtin_keywords()).ok,"units support fixed group auras")
	spec["media"]={"sounds":{"play":"a".repeat(64)},"background":"b".repeat(64),"music":"c".repeat(64)}
	_check(_compile(spec).ok,"media is versioned with card")
	unit["media"]=spec.media
	_check(not Runtime.compile_card(unit,Runtime.builtin_keywords()).ok,"only field controls background/music")

func _generated_media() -> void:
	var spec:=_base("场地制造者")
	var token:=_field([_aura("all_friendly_units",1,0)])
	for key in ["schema_version","ruleset_version","tokens","appearance"]:token.erase(key)
	token["token_id"]="field_token"
	token["media"]={"sounds":{"play":"a".repeat(64)},"music":"b".repeat(64)}
	spec.tokens=[token]
	spec.abilities=[{"trigger":"on_play","effects":[{"op":"create_card","player":"owner","token_id":"field_token","amount":1}]}]
	var compiled:=_compile(spec)
	if not compiled.ok:return
	var game:=_game()
	var generated:Dictionary=game._generated_card(compiled,"field_token")
	_check(generated.definition.kind=="field" and generated.definition.media==token.media,"generated field preserves its own media")
	var owner:=_rich(game)
	game.state.players[owner].hand.append({"instance_id":"generated-field","card":generated})
	_check(game.apply_action(owner,{"type":"play","hand_id":"generated-field"}).is_empty(),"generated field can be played")
	_check(game.state.field.card.definition.media==token.media,"generated field media reaches public state")
