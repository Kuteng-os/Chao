extends "res://tests/test_engine.gd"

func _query(status: String = "printed", target: String = "chosen") -> Dictionary:
	return {"test":"unit_keyword","target":target,"keyword_id":"core.shock","state":status}

func _history(target: String = "chosen") -> Dictionary:
	return {"test":"unit_state","target":target,"state":"has_attacked"}

func _grant(id: String) -> Dictionary:
	return {"op":"grant_keyword","target":"chosen","keyword_id":id,"keyword_version":1,"duration":"battle"}

func _order() -> Dictionary:
	var c := _base("越冲越爽","order")
	c.play_target={"side":"ally","row":"any"}
	var buff := {"op":"modify_stats","target":"chosen","attack_delta":1,"health_delta":2,"duration":"battle"}
	c.abilities=[{"trigger":"on_play","premise":{"test":"all","items":[_query(),{"test":"not","item":_history()}]},"effects":[buff]},{"trigger":"on_play","premise":{"test":"all","items":[_query(),_history()]},"effects":[_grant("core.shock"),_grant("core.ambush"),buff]}]
	var model_path := OS.get_environment("FRONTLINE_STATE_MODEL_CARD")
	if not model_path.is_empty(): c=JSON.parse_string(FileAccess.get_file_as_string(model_path))
	return c

func _initialize() -> void:
	var g := _game();var seat := _rich(g)
	var native := _base("原生冲击");native.keywords=[{"id":"core.shock","version":1,"params":{}}]
	var uid := _play(g,native)
	var context:Dictionary=g._context(seat,-1,_compile(_order()),uid)
	_check(g._premise_met(_query(),context),"printed keyword from frozen definition")
	_play(g,_order(),uid)
	_check(g._unit(uid).attack==4 and g._unit(uid).max_hp==6,"unattacked native gets only +1/+2")
	_check(not g._has_keyword(g._unit(uid),"core.ambush"),"first branch doesn't grant second branch keywords")
	g._attack(uid,-1)
	_check(g._premise_met(_history(),context),"HQ attack records lifetime history")
	_check(g._premise_met(_query("consumed"),context) and not g._premise_met(_query("current"),context),"actual consumed keyword distinct from current")
	_play(g,_order(),uid)
	_check(g._unit(uid).attack==5 and g._unit(uid).max_hp==8,"attacked branch buffs exactly once")
	_check(g._has_keyword(g._unit(uid),"core.shock") and g._has_keyword(g._unit(uid),"core.ambush"),"attacked branch grants both keywords")
	_check(g._premise_met(_query("consumed"),context),"regrant preserves consumed history")
	g._end_turn();g._end_turn()
	_check(g._premise_met(_history(),context) and g._premise_met(_query("consumed"),context),"turn reset preserves history")
	g._effect({"op":"reset_operations","target":"chosen"},context)
	_check(g._premise_met(_history(),context),"reset operations is not a new battlefield lifetime")
	g._effect({"op":"pin","target":"chosen","turns":1},context)
	_check(g._premise_met(_history(),context) and g._premise_met(_query("current"),context),"pin preserves keywords and histories")
	g._suppress(g._unit(uid))
	_check(g._premise_met(_query(),context) and not g._premise_met(_query("current"),context),"suppress doesn't erase printed origin")
	_check(g._premise_met(_history(),context) and g._premise_met(_query("consumed"),context),"suppress doesn't invent or erase combat history")
	var plain := _play(g,_base("无原生冲击"))
	var pc:Dictionary=g._context(seat,-1,_compile(_order()),plain)
	g._consume_keyword(g._unit(plain),"core.shock")
	_check(not g._premise_met(_query("consumed"),pc),"absent keyword isn't falsely recorded as consumed")
	g._effect(_grant("core.shock"),pc)
	_check(g._premise_met(_query("current"),pc) and not g._premise_met(_query(),pc),"granted keyword isn't printed")
	g._attack(plain,-1)
	_play(g,_order(),plain)
	_check(g._unit(plain).attack==3 and g._unit(plain).max_hp==4 and not g._has_keyword(g._unit(plain),"core.ambush"),"no printed shock remains a no-op even after granted shock attacked")
	var old_card:Dictionary=g._unit(uid).card.duplicate(true)
	g._leave_battlefield(g._unit(uid),true)
	var returned:Dictionary=g._new_unit(seat,old_card)
	var rc:Dictionary=g._context(seat,-1,_compile(_order()),returned.uid)
	_check(not g._premise_met(_history(),rc) and not g._premise_met(_query("consumed"),rc) and g._premise_met(_query(),rc),"reentry resets histories while retaining printed keyword")
	var absent:Dictionary=g._context(seat,-1,_compile(_order()),99999)
	_check(not g._premise_met({"test":"not","item":_query()},absent),"missing target invalidates negative queries too")
	absent.chosen=-101-seat
	_check(not g._premise_met({"test":"not","item":_history()},absent),"HQ cannot satisfy a negative unit query")
	_snapshot_branches()
	_retaliation_and_combat()
	_canceled_attack()
	print("UNIT STATE PREMISES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _snapshot_branches() -> void:
	var g:=_game();var seat:=_rich(g);var id:=_play(g,_base())
	var c:=_base("先获得再检查","order");c.play_target={"side":"ally","row":"any"}
	c.abilities=[{"trigger":"on_play","premise":{"test":"not","item":_query("current")},"effects":[_grant("core.shock")]},{"trigger":"on_play","premise":_query("current"),"effects":[{"op":"modify_stats","target":"chosen","attack_delta":5,"health_delta":0,"duration":"battle"}]}]
	_play(g,c,id)
	_check(g._unit(id).attack==3 and g._has_keyword(g._unit(id),"core.shock"),"sibling branches cannot become true after first result")
	_play(g,c,id)
	_check(g._unit(id).attack==8,"a subsequent card play takes a fresh snapshot")
	var copy:=EngineClass.new();copy.state=JSON.parse_string(JSON.stringify(g.state))
	var ctx:Dictionary=copy._context(seat,-1,_compile(c),id)
	_check(copy._premise_met(_query("current"),ctx,false) and not copy._premise_met(_query(),ctx,false),"serialized snapshot retains distinct keyword origins")

func _retaliation_and_combat() -> void:
	var g:=_game();var seat:=_rich(g)
	var c:=_base();c.attack=1;c.health=20
	var attacker:Dictionary=g._new_unit(seat,_compile(c));var defender:Dictionary=g._new_unit(1-seat,_compile(c))
	g._resolve_combat(attacker,defender)
	_check(attacker.has_attacked_in_play and not defender.has_attacked_in_play,"retaliation isn't active attack history")
	var other:Dictionary=g._new_unit(seat,_compile(c))
	g._effect({"op":"fight","target":"chosen"},g._context(seat,other.uid,other.card,defender.uid))
	_check(other.has_attacked_in_play,"fight counts as active combat without spending attack allowance")

func _canceled_attack() -> void:
	var g:=_game();var seat:=_rich(g)
	var c:=_base();c.keywords=[{"id":"core.shock","version":1,"params":{}}]
	var unit:Dictionary=g._new_unit(seat,_compile(c))
	var counter:=_base("取消攻击","counter");counter.appearance.emblem="counter";counter["counter_trigger"]="enemy_hq_attacked";counter.abilities=[{"trigger":"on_reveal","effects":[{"op":"cancel_action"}]}]
	g.state.players[1-seat].credits=12
	g.state.players[1-seat].counters=[{"instance_id":"cancel-history-test","card":_compile(counter),"armed_turn":int(g.state.turn)-1}]
	g._attack(unit.uid,-1)
	_check(not unit.has_attacked_in_play and unit.consumed_keyword_history.is_empty() and g._has_keyword(unit,"core.shock"),"canceled attack doesn't fake resolved combat or keyword consumption")
