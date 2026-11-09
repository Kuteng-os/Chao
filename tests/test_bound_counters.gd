extends "res://tests/test_engine.gd"

func _initialize() -> void:
	_test_bound_target()
	_test_lost_target()
	_test_periodic()
	_test_counter_privacy()
	_test_expiry_capacity()
	_test_counter_budget()
	_test_public_order()
	print("BOUND TARGETS AND COUNTERS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _salvo(trigger: String = "on_death") -> Dictionary:
	var card:=_base("玉兽")
	card.abilities=[{"trigger":trigger,"target":{"side":"enemy","row":"any"},"effects":[{"op":"damage","target":"chosen","amount":{"stat":"source_base_health"}},{"op":"draw","player":"owner","amount":1}]}]
	return card

func _choose(game: RefCounted, uid: int) -> String:
	return game.apply_action(game.state.pending_choice.owner,{"type":"choose_target","choice_id":game.state.pending_choice.choice_id,"target_uid":uid})

func _enemy(game: RefCounted) -> int:
	var spec:=_base("敌军")
	spec.health=20
	return game._new_unit(1-int(game.state.active_player),_compile(spec)).uid

func _kill(game: RefCounted, uid: int) -> void:
	var card:=_base("消灭","order")
	card.play_target={"side":"ally" if game._unit(uid).owner==game.state.active_player else "enemy","row":"any"}
	card.abilities=[{"trigger":"on_play","effects":[{"op":"destroy","target":"chosen"}]}]
	_play(game,card,uid)

func _test_bound_target() -> void:
	var game:=_game()
	var owner:=_rich(game)
	var a:=_enemy(game)
	var b:=_enemy(game)
	var source:=_play(game,_salvo())
	_check(game.state.has("pending_choice") and game.state.pending_choice.selection_timing=="deploy","deployment immediately asks for delayed target")
	_check(game.state.pending_choice.targets==[a,b],"deployment offers eligible enemies only")
	var prefix: Array=game.state.telemetry.duplicate(true)
	var paid: int=game.state.players[owner].credits
	_check(_choose(game,b).is_empty(),"choose deployment target")
	_check(game.state.players[owner].credits==paid,"choice replay does not pay twice")
	_check(game.state.telemetry.slice(0,prefix.size())==prefix,"choice replay preserves telemetry prefix")
	game._unit(b).row="front"
	game._unit(source).modifiers.append({"attack_delta":0,"health_delta":5,"expires_turn":-1})
	game._recompute(game._unit(source))
	_kill(game,source)
	_check(not game.state.has("pending_choice"),"death never asks again")
	_check(game._unit(a).hp==20 and game._unit(b).hp==16,"bound target follows row change and damage uses printed health")
	_check("部署时选定" in Runtime.rules_text(_compile(_salvo())),"preview explains deployment choice")

func _test_lost_target() -> void:
	var game:=_game()
	var owner:=_rich(game)
	var target:=_enemy(game)
	var source:=_play(game,_salvo())
	_check(_choose(game,target).is_empty(),"bind departing target")
	var frozen: Dictionary=game._unit(target).card
	game._leave_battlefield(game._unit(target),false)
	var replacement: Dictionary=game._new_unit(1-owner,frozen)
	var before: int=game.state.players[owner].hand.size()
	_kill(game,source)
	_check(replacement.hp==20 and not game.state.has("pending_choice"),"same card replay has a new identity; lost target fizzles")
	_check(game.state.players[owner].hand.size()==before+1,"unrelated draw still resolves")
	game=_game()
	source=_play(game,_salvo())
	_check(not game.state.has("pending_choice"),"empty deployment candidates do not deadlock")
	target=_enemy(game)
	_kill(game,source)
	_check(game._unit(target).hp==20 and not game.state.has("pending_choice"),"later arrivals are never auto selected")

func _test_periodic() -> void:
	var game:=_game()
	var owner:=_rich(game)
	var target:=_enemy(game)
	_play(game,_salvo("own_turn_end"))
	_check(_choose(game,target).is_empty(),"periodic effect binds at deployment")
	_check(game.apply_action(owner,{"type":"end_turn"}).is_empty(),"end turn resolves bound periodic effect")
	_check(game._unit(target).hp==16 and not game.state.has("pending_choice"),"periodic effect hits stored target without prompt")

func _counter(cost: int = 1) -> Dictionary:
	var card:=_base("秘密反制","counter")
	card.cost=cost
	card.appearance.emblem="counter"
	card["counter_trigger"]="enemy_order_played"
	card.abilities=[{"trigger":"on_reveal","effects":[{"op":"cancel_action"}]}]
	return card

func _give(game: RefCounted, owner: int, spec: Dictionary) -> String:
	var id:="h"+str(game.state.next_hand_id)
	game.state.next_hand_id+=1
	game.state.players[owner].hand.append({"instance_id":id,"card":_compile(spec)})
	return id

func _order() -> Dictionary:
	var card:=_base("炮击指令","order")
	card.abilities=[{"trigger":"on_play","effects":[{"op":"damage","target":"enemy_hq","amount":2}]}]
	return card

func _test_counter_privacy() -> void:
	var game:=_game()
	var owner: int=game.state.active_player
	game.state.players[owner].credits=2
	var id:=_give(game,owner,_counter())
	var before: Dictionary=game.view_for(1-owner)
	_check(game.apply_action(owner,{"type":"play","hand_id":id}).is_empty(),"arm with enough kredits")
	var after: Dictionary=game.view_for(1-owner)
	before.erase("state_seq")
	after.erase("state_seq")
	_check(before==after,"opponent snapshot unchanged except protocol sequence: no count, log, name or animation leak")
	_check(game.state.players[owner].credits==2,"arming does not spend")
	_check(game.view_for(owner).players[owner].counters.size()==1,"owner sees own armed counter")
	game.apply_action(owner,{"type":"end_turn"})
	_play(game,_order())
	_check(game.state.players[owner].credits==1 and game.state.players[owner].hp==20,"trigger pays once and cancels order")
	_check(game.state.players[owner].counters.is_empty(),"revealed counter consumed once")
	var events: Array=game.view_for(owner).presentation_events
	var reveals: Array=events.filter(func(e): return e.kind=="counter_reveal")
	_check(reveals.size()==1 and reveals[0].display_card.definition.name=="秘密反制","counter face public only when revealed")
	game=_game()
	owner=game.state.active_player
	game.state.players[owner].credits=0
	id=_give(game,owner,_counter())
	var hash:=Runtime.sha(game.state)
	_check(not game.apply_action(owner,{"type":"play","hand_id":id}).is_empty() and Runtime.sha(game.state)==hash,"cannot arm without required credits")

func _test_expiry_capacity() -> void:
	var game:=_game()
	var owner:=_rich(game)
	game.state.players[owner].hand=[]
	var id:=_give(game,owner,_counter())
	game._hand(owner,id)["revealed"]=true
	var before: Dictionary=game.view_for(1-owner)
	game.apply_action(owner,{"type":"play","hand_id":id})
	var after: Dictionary=game.view_for(1-owner)
	_check(before.players[owner].revealed_hand==after.players[owner].revealed_hand,"previous intel cannot reveal arming through position or disappearance")
	for i in 9: game._receive_card(owner,_compile(_base("补牌"+str(i))),"draw")
	_check(game._held_cards(owner).size()==10,"armed card reserves its hand slot")
	game._receive_card(owner,_compile(_base()),"draw")
	_check(game.state.players[owner].burned.size()==1,"hand limit includes hidden armed card")
	game.apply_action(owner,{"type":"end_turn"})
	game.apply_action(1-owner,{"type":"end_turn"})
	_check(game.state.players[owner].counters.is_empty() and not game._hand(owner,id).is_empty(),"untriggered counter returns same card next own turn")
	_check(game.state.players[owner].hand.size()==10,"return does not burn or duplicate original counter")
	_check(game.state.players[owner].burned.size()==2,"normal turn draw obeys full hand after return")
	_check(game.state.telemetry.filter(func(e): return e.kind=="deployment_spent").is_empty(),"untriggered counter never pays")

func _test_counter_budget() -> void:
	var game:=_game()
	var owner:=_rich(game)
	game.state.players[owner].credits=1
	for i in 2:
		var id:=_give(game,owner,_counter())
		_check(game.apply_action(owner,{"type":"play","hand_id":id}).is_empty(),"multiple counters can arm against currently available credit")
	game.apply_action(owner,{"type":"end_turn"})
	_play(game,_order())
	_play(game,_order())
	_check(game.state.players[owner].credits==0 and game.state.players[owner].hp==18,"only payable counter triggers; next order resolves")
	_check(game.state.players[owner].counters.size()==1,"unpayable counter remains hidden until expiry")
	game.apply_action(1-owner,{"type":"end_turn"})
	_check(game.state.players[owner].counters.is_empty(),"unpayable counter returns next turn")

func _test_public_order() -> void:
	var game:=_game()
	_play(game,_order())
	var left: Array=game.view_for(0).presentation_events
	var right: Array=game.view_for(1).presentation_events
	_check(left==right,"both players receive same public order reveal")
	var played: Array=left.filter(func(e): return e.kind=="play")
	_check(played.back().display_card.definition.kind=="order","played order includes frozen card face")
	_check(not JSON.stringify(left).contains('"source"'),"presentation excludes compiler source and private state")
