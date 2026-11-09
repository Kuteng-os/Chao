extends "res://tests/test_combat_keywords.gd"

func _initialize() -> void:
	_mobilize_alpine()
	_suppress_and_pin()
	_salvage()
	_relocate()
	_intel_and_common()
	_contracts()
	print("KEYWORD ACTIONS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _effect_order(game: RefCounted, effect: Dictionary, target: int = -1, side: String = "enemy") -> void:
	var spec := _base("基础操作","order")
	if effect.get("target") == "chosen": spec.play_target = {"side":side,"row":"any"}
	spec.abilities = [{"trigger":"on_play","effects":[effect]}]
	_play(game,spec,target)

func _mobilize_alpine() -> void:
	var game := _board()
	var unit := _soldier(game,0,["mobilize"],1,3)
	_round(game)
	unit = game._unit(unit.uid)
	_check(unit.attack==2 and unit.hp==4,"Mobilize grants stats at own turn start")
	_buff(game,unit.uid,{"op":"set_stacks","stack":"heavy_armor","amount":3,"target":"chosen","duration":"battle"})
	var enemy := _soldier(game,1,[],2,20)
	_hit(game,unit.uid,enemy.uid)
	unit = game._unit(unit.uid)
	_check(unit.hp==4 and game._has_keyword(unit,"core.mobilize"),"Fully armored damage does not consume Mobilize")
	_effect_order(game,{"op":"damage","target":"chosen","amount":1},unit.uid,"ally")
	unit = game._unit(unit.uid)
	_check(unit.hp==3 and not game._has_keyword(unit,"core.mobilize"),"Actual ability damage consumes Mobilize despite armor")
	_round(game)
	unit = game._unit(unit.uid)
	_check(unit.attack==2 and unit.max_hp==4,"Mobilize never removes earned stats nor regenerates")
	game = _board()
	var a := _soldier(game,0,["alpine"],2,2)
	var b := _soldier(game,0,["alpine"],2,2)
	var c := _soldier(game,0,["alpine"],2,2)
	_check(a.attack==2 and b.attack==3 and c.attack==4,"Alpine counts other current friendly Alpine at entry")
	_effect_order(game,{"op":"remove","target":"chosen"},b.uid,"ally")
	_check(game._unit(c.uid).attack==4,"Alpine bonus persists when another Alpine leaves")
	_effect_order(game,{"op":"suppress","target":"chosen"},a.uid,"ally")
	var d := _soldier(game,0,["alpine"],2,2)
	_check(d.attack==3,"Suppressed Alpine does not count for new Alpine")

func _suppress_and_pin() -> void:
	var game := _board()
	var spec := _base("被抑制的阵亡效果")
	spec.keywords = [{"id":"core.guard","version":2,"params":{}}]
	spec.abilities = [{"trigger":"on_death","effects":[{"op":"damage","target":"enemy_hq","amount":3}]}]
	var unit: Dictionary = game._new_unit(1,_compile(spec))
	unit.born_turn = -1
	_effect_order(game,{"op":"damage","target":"chosen","amount":2},unit.uid)
	_effect_order(game,{"op":"modify_stats","target":"chosen","attack_delta":3,"health_delta":3,"duration":"battle"},unit.uid)
	_effect_order(game,{"op":"suppress","target":"chosen"},unit.uid)
	unit = game._unit(unit.uid)
	_check(unit.attack==3 and unit.hp==4 and not game._has_keyword(unit,"core.guard"),"Suppress resets printed stats, heals and removes innate keywords")
	_effect_order(game,{"op":"grant_keyword","target":"chosen","keyword_id":"core.fury","keyword_version":1,"duration":"battle"},unit.uid)
	_check(game.attack_limit(game._unit(unit.uid))==2,"Suppressed unit can gain a fresh keyword")
	var hp: int = game.state.players[0].hp
	_effect_order(game,{"op":"destroy","target":"chosen"},unit.uid)
	_check(game.state.players[0].hp==hp,"Suppression removes destruction effects")
	game = _board()
	unit = _soldier(game,1,[],3,12,"tank")
	_effect_order(game,{"op":"pin","target":"chosen","turns":1},unit.uid)
	_check(game.apply_action(0,{"type":"end_turn"}).is_empty(),"Pinned enemy enters own turn")
	_check(not game.can_move(unit.uid) and game.legal_targets(1,{"type":"attack","uid":unit.uid}).is_empty(),"Pin forbids operations throughout next controller turn")
	_check(game.apply_action(1,{"type":"end_turn"}).is_empty(),"Pinned next controller turn ends")
	_check(not game._pinned(game._unit(unit.uid)),"Pin expires after next controller turn")
	unit = _soldier(game,0,[],3,12,"tank")
	_effect_order(game,{"op":"pin","target":"chosen","turns":1},unit.uid,"ally")
	_round(game)
	_check(game._pinned(game._unit(unit.uid)),"Pin on active player's own turn survives until their next turn ends")
	game = _board()
	unit = _soldier(game,1,[],3,12)
	_effect_order(game,{"op":"pin","target":"chosen","turns":1},unit.uid)
	var attacker := _soldier(game,0,[],1,10)
	_hit(game,attacker.uid,unit.uid)
	_check(game._unit(attacker.uid).hp==7,"Pinned unit still retaliates")
	game = _board()
	unit = _soldier(game,1,["guard"],3,12)
	_effect_order(game,{"op":"pin","target":"chosen","turns":1},unit.uid)
	_check(game._has_keyword(game._unit(unit.uid),"core.guard"),"Pin preserves Guard and all innate abilities")
	_effect_order(game,{"op":"suppress","target":"chosen"},unit.uid)
	unit = game._unit(unit.uid)
	_check(game._pinned(unit) and unit.suppressed and not game._has_keyword(unit,"core.guard"),"Pin and Suppress coexist; suppression neither removes nor substitutes pin")
	var display := _base("两个状态","order")
	display.play_target = {"side":"enemy","row":"any"}
	display.abilities = [{"trigger":"on_play","effects":[{"op":"pin","target":"chosen","turns":1},{"op":"suppress","target":"chosen"}]}]
	var text := Runtime.rules_text(_compile(display).definition)
	_check(text.contains("压制") and text.contains("抑制") and not text.contains("钉住"),"Chinese Pin and Suppress labels are distinct")

func _salvage() -> void:
	var game := _board()
	var attacker := _soldier(game,0,["salvage"],9,12)
	var spec := _base("缴获目标")
	spec.cost = 9
	spec.health = 2
	spec.abilities = [{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]
	var enemy: Dictionary = game._new_unit(1,_compile(spec))
	var original: String = Runtime.sha(enemy.card)
	_hit(game,attacker.uid,enemy.uid)
	var copy: Dictionary = game.state.players[0].hand.back().card
	_check(copy.definition.attack==1 and copy.definition.health==1 and copy.definition.cost==3,"Salvage copy is 1/1 with deployment capped at 3")
	_check(copy.definition.abilities==spec.abilities,"Salvage retains frozen abilities")
	_check(Runtime.sha(enemy.card)==original,"Salvage never edits immutable source card")
	_check(copy.generated_origin.definition_hash==enemy.card.definition_hash,"Salvage analytics retain source version identity")
	_check(Runtime.sha(copy.source)==copy.definition_hash,"Runtime variant has valid source hash")
	game = _board()
	attacker = _soldier(game,0,[],2,10)
	enemy = _soldier(game,1,["salvage"],10,10)
	var count: int = game.state.players[1].hand.size()
	_hit(game,attacker.uid,enemy.uid)
	_check(game.state.players[1].hand.size()==count,"Salvage cannot trigger on opponent's turn")
	game = _board()
	attacker = _soldier(game,0,["salvage"],10,1)
	enemy = _soldier(game,1,[],10,1)
	count = game.state.players[0].hand.size()
	_hit(game,attacker.uid,enemy.uid)
	_check(game.state.players[0].hand.size()==count+1,"Simultaneously destroyed Salvage source still awards copy")

func _relocate() -> void:
	var game := _board()
	var unit := _soldier(game,0,["guard"],3,8,"tank")
	_check(game.apply_action(0,{"type":"move","uid":unit.uid}).is_empty(),"Retreat test moves to front")
	_effect_order(game,{"op":"retreat","target":"chosen"},unit.uid,"ally")
	_check(game._unit(unit.uid).row=="support","Retreat sends frontline unit to support")
	_effect_order(game,{"op":"suppress","target":"chosen"},unit.uid,"ally")
	_effect_order(game,{"op":"retreat","target":"chosen"},unit.uid,"ally")
	_check(game._unit(unit.uid).is_empty(),"Support-line retreat returns to hand")
	var entry: Dictionary = game.state.players[0].hand.back()
	_check(entry.get("revealed",false),"Returned card is public Intel")
	var id: int = game.state.next_uid
	_check(game.apply_action(0,{"type":"play","hand_id":entry.instance_id}).is_empty(),"Returned unit can be replayed")
	_check(game._has_keyword(game._unit(id),"core.guard") and not game._unit(id).get("suppressed",false),"Returning clears suppression")
	game = _board()
	var spec := _base("移除没有阵亡")
	spec.abilities = [{"trigger":"on_death","effects":[{"op":"damage","target":"enemy_hq","amount":5}]}]
	unit = game._new_unit(1,_compile(spec))
	var hp: int = game.state.players[0].hp
	_effect_order(game,{"op":"remove","target":"chosen"},unit.uid)
	_check(game.state.players[0].hp==hp and game.state.discard.size()==1,"Remove does not destroy or add unit to discard pile")

func _intel_and_common() -> void:
	var game := _board()
	_effect_order(game,{"op":"intel","amount":2})
	var view: Dictionary = game.view_for(0)
	_check(view.players[1].hand.is_empty() and view.players[1].revealed_hand.size()==2,"Intel exposes only authorized cards, hidden hand stays empty")
	_effect_order(game,{"op":"intel","amount":9})
	view = game.view_for(0)
	_check(view.players[1].revealed_hand.size()==game.state.players[1].hand.size(),"Intel is cumulative and does not select known cards twice")
	var unit := _soldier(game,1,["immune"],3,4)
	_effect_order(game,{"op":"damage","target":"chosen","amount":10},unit.uid)
	_check(game._unit(unit.uid).hp==4,"Immune blocks effect damage")
	_effect_order(game,{"op":"modify_stats","target":"chosen","attack_delta":0,"health_delta":-4,"duration":"battle"},unit.uid)
	_check(game._unit(unit.uid).is_empty(),"Immune does not prevent zero-defense death")
	_effect_order(game,{"op":"gain_hq_defense","player":"owner","amount":5})
	_check(game.state.players[0].hp==25 and game.state.players[0].max_hp==25,"HQ defense can exceed printed 20")
	var count: int = game.state.players[1].hand.size()
	_effect_order(game,{"op":"discard","player":"opponent","amount":2})
	_check(game.state.players[1].hand.size()==count-2,"Discard removes hand cards deterministically")
	_effect_order(game,{"op":"modify_kredit_slots","player":"opponent","amount":-3})
	_check(game.state.players[1].max_credits==0 and game.state.players[1].credits==0,"Kredit slot reduction clamps current resources")
	game = _board()
	unit = _soldier(game,1,[],3,8,"infantry")
	var spec := _base("部署交战")
	spec.play_target = {"side":"enemy","row":"any"}
	spec.abilities = [{"trigger":"on_play","effects":[{"op":"fight","target":"chosen"}]}]
	var id := _play(game,spec,unit.uid)
	_check(game._unit(unit.uid).hp==5 and game._unit(id).hp==1,"Fight resolves combat without requiring deployment readiness")
	_check(game._unit(id).attacks_used==0,"Effect combat does not consume ordinary attacks")

func _contracts() -> void:
	var spec := _base("无来源战斗","order")
	spec.abilities = [{"trigger":"on_play","effects":[{"op":"fight","target":"random_enemy_unit"}]}]
	_check(not Runtime.compile_card(spec,Runtime.builtin_keywords()).ok,"Orders cannot use implicit self Fight")
	var keyword: Dictionary = _read("keywords/example_fight.json")
	keyword.implementation.abilities[0].effects = [{"op":"intel","amount":{"param":"n"}}]
	keyword.parameters = {"n":{"type":"integer","minimum":1,"maximum":9}}
	_check(Runtime.validate_keyword(keyword).is_empty(),"Intel numeric template accepts full range")
	keyword.parameters.n.maximum = 10
	_check(not Runtime.validate_keyword(keyword).is_empty(),"Intel rejects unsupported parameter range")
