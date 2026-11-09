extends "res://tests/test_engine.gd"
var fixtures: Dictionary
func _initialize() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/repairs861.json"))
	fixtures=data.fixtures
	for key in fixtures:
		var c:=_compile(fixtures[key])
		_check(c.get("compiled_program_hash")==data.hashes[key],"Node/native parity "+key)
	if failures: quit(1);return
	_test_auras()
	_test_events()
	_test_develop()
	_test_suspend()
	_test_once()
	_test_kills()
	_test_hand_costs()
	_test_target_rules()
	_test_return_end()
	print("REPAIRS 861: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)

func unit(g: RefCounted,owner: int,key: String="") -> Dictionary:
	return g._new_unit(owner,_compile(fixtures[key] if fixtures.has(key) else _base(key if not key.is_empty() else "普通单位")))
func _test_auras() -> void:
	var g:=_game();var me:=_rich(g)
	var aura:=unit(g,me,"otherAura");var friend:=unit(g,me);var foe:=unit(g,1-me)
	g._checkpoint()
	_check(aura.attack==3 and friend.attack==4 and foe.attack==3,"other-friendly excludes source and enemies")
	g._suppress(aura);g._checkpoint();_check(friend.attack==3,"suppression removes aura")
	var v:=unit(g,me,"vulnerability");g._checkpoint()
	_check(g._incoming_damage(foe,1,"effect")==4,"enemy ground takes +3")
	_check(g._incoming_damage(g.state.players[1-me],1,"effect")==3,"enemy headquarters takes +2")
	_check(g._incoming_damage(g.state.players[me],1,"effect")==1,"own headquarters unaffected")
	_check(g._incoming_damage(foe,0,"effect")==0,"aura does not turn zero into damage")
	g._leave_battlefield(v,true);g._checkpoint()
	_check(g._incoming_damage(foe,1,"effect")==1,"aura disappears on departure")
	var oa:=unit(g,me,"orderAura");g._checkpoint()
	var order:=_base("指令","order");order.abilities=[{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]
	var source:=_compile(order);source["damage_owner"]=me
	_check(g._incoming_damage(foe,1,"effect",{},source)==3,"friendly order boosted")
	source.damage_owner=1-me
	_check(g._incoming_damage(foe,1,"effect",{},source)==1,"enemy order not boosted")
	_check(g._incoming_damage(foe,1,"combat",friend)==1,"combat not boosted by order aura")
	_check(not oa.is_empty(),"aura source exists")

func _test_events() -> void:
	var g:=_game();var me:=_rich(g);var healer:=unit(g,me,"attacked");var foe:=unit(g,1-me)
	foe.attack=0;healer.damage_taken=2;g._recompute(healer)
	g._resolve_combat(foe,healer);g._checkpoint();g._drain_deaths()
	_check(healer.hp==3,"after-attacked fires even zero damage")
	var mover:=unit(g,me,"move");var ally:=unit(g,me)
	g._emit_unit_event(me,"unit_moved",ally.uid,ally.card);g._drain_deaths()
	_check(mover.hp==5 and ally.hp==5,"movement grants both units once")
	g._emit_unit_event(me,"unit_moved",mover.uid,mover.card);g._drain_deaths()
	_check(mover.hp==6,"self movement does not double grant")
	var eq:=unit(g,me,"equalAttack");g._initialize_deployed_unit(eq);g._drain_deaths()
	foe.attack=7
	_check(g._combat_damage(eq,foe,"attack")==7 and g._combat_damage(eq,foe,"retaliation")==7,"opponent attack used both ways")
	_check(eq.attack==3 and g._combat_damage(eq,{},"attack")==3,"base attack and HQ attacks unchanged")
	var gap:=_compile(fixtures.headquartersGap);g.state.players[me].hp=28
	_check(g._premise_met(gap.definition.abilities[0].premise,g._context(me,-1,gap)),"HQ difference includes exactly eight")
	g.state.players[me].hp=27
	_check(not g._premise_met(gap.definition.abilities[0].premise,g._context(me,-1,gap)),"HQ difference below eight false")

func _test_develop() -> void:
	var g:=_game();var me:=_rich(g);g.state.players[me].hand=[]
	var original:=_compile(_base("剩余牌"));g.state.players[me].deck=[original]
	var source:=_compile(fixtures.developDeck);g.state.players[me].hand=[{"instance_id":"dev","card":source}]
	_check(g.apply_action(me,{"type":"play","hand_id":"dev"}).is_empty(),"develop suspends for choice")
	_check(g.state.has("pending_choice"),"develop offers candidates")
	if not g.state.has("pending_choice"):return
	var choice: Dictionary=g.state.pending_choice
	_check(g.apply_action(me,{"type":"choose_card","choice_id":choice.choice_id,"option_index":0}).is_empty(),"develop choice resolves")
	_check(g.state.players[me].deck.is_empty() and g.state.players[me].hand.size()==1,"only selected actual card leaves deck")
	_check(g.state.players[me].hand[0].card.definition.name=="剩余牌","correct card received")

func _test_suspend() -> void:
	var g:=_game();var me:=_rich(g);var u:=unit(g,me)
	var context: Dictionary=g._context(me,u.uid,u.card)
	g._effect({"op":"modify_stats","target":"self","attack_delta":2,"health_delta":2,"duration":"match"},context)
	g._effect({"op":"modify_stats","target":"self","attack_delta":3,"health_delta":3,"duration":"battle"},context)
	u.damage_taken=1;u.attacks_used=1
	var original_turn: int=g.state.turn
	g._suspend_unit(u,fixtures.suspend.abilities[0].effects[0],context)
	_check(g.state.units.is_empty(),"temporarily removed")
	g.state.turn=original_turn+1;g._release_suspended("turn_start")
	_check(g.state.units.is_empty(),"does not return on first enemy turn")
	g.state.turn=original_turn+3;g._release_suspended("turn_start")
	_check(g.state.units.size()==1,"returns on second enemy turn")
	if g.state.units.is_empty():return
	u=g.state.units[0]
	_check(u.attack==5 and u.hp==5 and u.attacks_used==1,"temporary layers clear, permanent layers damage actions persist")

func _test_once() -> void:
	var g:=_game();var me:=_rich(g);var source:=_compile(fixtures.once)
	g._effect(fixtures.once.abilities[0].effects[0],g._context(me,-1,source))
	var tank:=unit(g,me);g._initialize_deployed_unit(tank);g._drain_deaths()
	_check(tank.hp==5,"first deployment receives permanent bonus")
	var card: Dictionary=tank.card.duplicate(true);g._leave_battlefield(tank,true)
	var again: Dictionary=g._new_unit(me,card);g._initialize_deployed_unit(again);g._drain_deaths()
	_check(again.hp==5,"return and redeploy keeps bonus without duplicating")
	g._effect(fixtures.once.abilities[0].effects[0],g._context(me,-1,source))
	var fresh:=unit(g,me);g._initialize_deployed_unit(fresh);g._drain_deaths()
	_check(fresh.hp==5,"two matching global listeners still grant once")

func _test_kills() -> void:
	for key in ["killCopy","killForm"]:
		var g:=_game();var me:=_rich(g);g.state.players[me].hand=[]
		var killer:=unit(g,me,key);var victim:=unit(g,1-me,"被消灭的单位")
		var context: Dictionary=g._context(me,killer.uid,killer.card)
		context["chosen"]=victim.uid
		g._effect({"op":"damage","target":"chosen","amount":10},context)
		g._checkpoint();g._drain_deaths()
		_check(g._fault.is_empty(),key+" resolves without fault")
		if key=="killCopy":
			_check(g.state.players[me].hand.size()==1,"kill adds victim copy to hand")
			if not g.state.players[me].hand.is_empty(): _check(g.state.players[me].hand[0].card.definition.name=="被消灭的单位","kill copies victim instead of killer")
		else:
			_check(g.state.units.size()==1 and g.state.units[0].card.definition.name=="被消灭的单位","killer transforms to victim")
			_check(g.state.units[0].owner==me,"transform remains friendly")

func _test_hand_costs() -> void:
	var g:=_game();var me:=_rich(g);var held:=_compile(fixtures.handCost)
	g.state.players[me].hand=[{"instance_id":"listener","card":held}]
	var field_listener:=unit(g,me,"handCost");var victim:=unit(g,1-me)
	victim.destroyed=true;g._checkpoint();g._drain_deaths()
	_check(g.play_cost(me,held)==5,"hand death listener reduces only this card")
	_check(g._operation_cost(field_listener)==0,"battlefield listener changes operation cost")
	var dynamic:=_compile(fixtures.zeroCost)
	_check(g.play_cost(me,dynamic)==0,"enemy death enables zero play cost")
	g.state.turn+=1
	_check(g.play_cost(me,dynamic)==8,"death query expires on turn transition")
	var counter:=_base("反制","counter");counter.unit_class=null;counter.attack=0;counter.health=0;counter.operation_cost=0;counter.cost=2
	counter["counter_trigger"]="enemy_unit_deployed";counter.abilities=[{"trigger":"on_reveal","effects":[{"op":"draw","player":"owner","amount":1}]}]
	var c:=_compile(counter);var old:=c.duplicate(true)
	g.state.players[me].hand=[{"instance_id":"old","card":old}];g.state.players[me].deck=[c.duplicate(true),c.duplicate(true)]
	var source:=_compile(fixtures.drawCost);var ctx: Dictionary=g._context(me,-1,source)
	for effect in fixtures.drawCost.abilities[0].effects:g._effect(effect,ctx)
	_check(g.state.players[me].hand.size()==3,"typed draw receives two counters")
	_check(g.play_cost(me,old)==2,"preexisting hand card unaffected")
	for entry in g.state.players[me].hand:
		if entry.instance_id!="old":_check(g.play_cost(me,entry.card)==1,"only drawn instances discounted")
	_check(g._fault.is_empty(),"hand listeners and drawn cost no fault")

func _test_target_rules() -> void:
	var g:=_game();var me:=_rich(g);var protected:=unit(g,1-me,"orderImmune")
	var order:=_base("指令","order");order.abilities=[{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]
	_check(g._explicit_target_blocked(protected,_compile(order)),"order-only protection blocks order selection")
	_check(not g._explicit_target_blocked(protected,_compile(_base("单位技能"))),"order-only protection allows unit skill")
	var bomber:=unit(g,me,"bomberBypass");var normal:=unit(g,me);normal.card.definition.unit_class="bomber"
	var fighter:=unit(g,1-me);fighter.card.definition.unit_class="fighter"
	_check(not g._fighter_cover_allows(normal,"support",-1),"normal bomber cannot bypass fighter cover for HQ")
	_check(g._fighter_cover_allows(normal,"support",fighter.uid),"fighter itself remains attackable")
	_check(g._fighter_cover_allows(bomber,"support",-1),"special bomber bypasses cover")
	var allied:=unit(g,me,"salvageGain");var captured:=unit(g,me);captured.card["generated_token_id"]="salvage"
	g._emit_card_event(me,captured.card,captured.uid,[allied.uid]);g._drain_deaths()
	_check(allied.attack==4 and captured.attack==4,"salvaged deployment buffs self and trigger")

func _test_return_end() -> void:
	var g:=_game();var me:=_rich(g);var u:=unit(g,me);var turn: int=g.state.turn
	g._suspend_unit(u,fixtures.endSuspend.abilities[0].effects[0],g._context(me,u.uid,u.card))
	g._release_suspended("turn_end");_check(g.state.units.is_empty(),"enemy-end return skips own turn end")
	g.state.turn=turn+1;g._release_suspended("turn_start");_check(g.state.units.is_empty(),"enemy-end return skips turn start")
	g._release_suspended("turn_end");_check(g.state.units.size()==1,"returns on intended enemy turn end")
