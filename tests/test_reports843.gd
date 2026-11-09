extends "res://tests/test_engine.gd"
var fixtures: Array
const FACTION="a1b80fcd-cf3e-4f1d-8759-207773c93b8c"
func _initialize() -> void:
	fixtures=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("REPORTS843_FIXTURES") if not OS.get_environment("REPORTS843_FIXTURES").is_empty() else "res://tests/reports843.json")).cards
	for f in fixtures:
		var c:=_compile(f.definition)
		_check(c.definition_hash==f.definition_hash and c.compiled_program_hash==f.compiled_program_hash,"Node/Godot parity")
		_check(not "undefined" in Runtime.rules_text(c),"readable text")
	_return_top()
	_bonuses()
	_kill_counts()
	_cost_choices()
	_deck_choices()
	print("REPORTS843: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func _kill_source(g: RefCounted, uid: int) -> void:
	var d:=_base("杀死来源","order");d.play_target={"side":"any","row":"any"};d.abilities=[{"trigger":"on_play","effects":[{"op":"damage","target":"chosen","amount":10}]}]
	_play(g,d,uid)

func _return_top() -> void:
	for full in [false,true]:
		var g:=_game();var p:=_rich(g);g.state.players[p].hand=[]
		var card:=_compile(fixtures[0].definition);var u:Dictionary=g._new_unit(p,card);var ctx:Dictionary=g._context(p,u.uid,u.card,u.uid)
		g._effect({"op":"modify_stats","target":"chosen","attack_delta":2,"health_delta":0,"duration":"match"},ctx)
		if full:
			for n in 10:g._receive_card(p,_compile(_base(str(n))),"test")
		var before:int=g.state.players[p].deck.size()
		u.destroyed=true;g._checkpoint();g._drain_deaths()
		_check(g._fault.is_empty(),"return resolves")
		_check(g.state.players[p].deck.size()==before+(1 if full else 0),"overflow increments physical deck")
		_check(g.state.players[p].hand.size()==(10 if full else 1),"normal return vs overflow")
		var result:Dictionary=g.state.players[p].deck.back() if full else g.state.players[p].hand.back().card
		_check(result.definition.name==card.definition.name and result.match_layers.size()==1,"exact permanent-enhanced original returns to top")
		_check(g.state.discard.filter(func(e):return e.get("source_uid")==u.uid).is_empty(),"original removed only once")
		if full:
			g.state.players[p].hand=[];g._draw(p)
			_check(g.state.players[p].hand.back().card.definition.name==card.definition.name,"top card is next draw")

func _bonuses() -> void:
	for variant in [1,2]:
		var g:=_game();var p:=_rich(g)
		var d:=_base("有守护步兵");d.unit_class="infantry";d.appearance.emblem="infantry";d.health=8;d.keywords=[{"id":"core.guard","version":1,"params":{}}]
		var a:Dictionary=g._new_unit(1-p,_compile(d));d.name="普通坦克";d.unit_class="tank";d.appearance.emblem="tank";d.keywords=[]
		var b:Dictionary=g._new_unit(1-p,_compile(d));var ctx:Dictionary=g._context(p,-1,_compile(_base()),a.uid)
		g._effect({"op":"modify_incoming_damage","target":"chosen","damage_kind":"effect","amount":-1,"duration":"battle"},ctx)
		_play(g,fixtures[variant].definition)
		_check(g._unit(a.uid).hp==5 and g._unit(b.uid).hp==6,"single packet 4 minus armor 1; plain target 2")
		if variant==1:
			g._suppress(g._unit(a.uid));g._effect({"op":"damage","target":"chosen","amount":2},g._context(p,-1,_compile(fixtures[1].definition),a.uid))
			_check(g._unit(a.uid).hp==6,"suppressed guard no bonus")

func _kill_counts() -> void:
	for variant in [3,4]:
		var g:=_game();var p:=_rich(g)
		for owner in [p,1-p]:
			var d:=_base("脆弱单位");d.health=1;g._new_unit(owner,_compile(d))
		var d:=_base("幸存");d.health=3;var survivor:Dictionary=g._new_unit(1-p,_compile(d))
		var hp:int=g.state.players[p].hp
		_play(g,fixtures[variant].definition)
		_check(g._fault.is_empty(),"group damage settles")
		_check(g.state.players[1-p].hp==20 and g.state.players[p].hp==hp+(2 if variant==3 else 0),"only two direct kills rewarded; HQ not damaged")
		_check(g._unit(survivor.uid).hp==2,"survivor hit once")
		if variant==4:
			var spawned:Array=g.state.units.filter(func(u):return u.owner==p)
			_check(spawned.size()==2 and spawned.all(func(u):return u.hp==1 and u.row=="support"),"two newborns on our support, not in damage snapshot")
	# A chained death from loss of adjacent health must not count as a direct kill.
	var g:=_game();var p:=_rich(g);var d:=_base("光环");d.health=1
	d.abilities=[{"trigger":"while_active","effects":[{"op":"modify_stats","target":"adjacent_to_self","attack_delta":0,"health_delta":1,"duration":"battle"}]}]
	var aura:Dictionary=g._new_unit(1-p,_compile(d));d=_base("连锁");d.health=1
	var neighbour:Dictionary=g._new_unit(1-p,_compile(d));g._recompute(neighbour);neighbour.damage_taken=1;g._recompute(neighbour)
	var c:Dictionary=g._context(p,-1,_compile(fixtures[3].definition),aura.uid)
	g._effect({"op":"damage","target":"chosen","amount":1},c);g._checkpoint();g._drain_deaths()
	_check(c.last_damage_kill_count==1,"indirect death excluded")
	g._effect({"op":"damage","target":"chosen","amount":1},c)
	_check(c.last_damage_kill_count==0,"fizzled later damage clears count")

func _cost_choices() -> void:
	for kind in ["unit","order","counter","field"]:
		var g:=_game();var p:=_rich(g);var owner:=1-p;g.state.players[owner].hand=[]
		var src:Dictionary=g._new_unit(owner,_compile(fixtures[5].definition))
		var d:=_base("需要减费",kind);d.cost=3;d["faction_id"]=FACTION;d.appearance.emblem=kind if kind!="unit" else "tank"
		if kind=="order":d.abilities=[{"trigger":"on_play","effects":[{"op":"noop"}]}]
		if kind=="counter":d["counter_trigger"]="enemy_order_played";d.abilities=[{"trigger":"on_reveal","effects":[{"op":"draw","player":"owner","amount":1}]}]
		if kind=="field":d.abilities=[{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":1}]}]
		g._receive_card(owner,_compile(d),"test");g._receive_card(owner,_compile(_base("其他阵营")),"test")
		_kill_source(g,src.uid)
		_check(g.state.get("pending_choice",{}).get("kind")=="hand_cost","death prompts owner, even outside their turn")
		if not g.state.has("pending_choice"):continue
		_check(g.state.pending_choice.options.size()==1,"only correct faction in options")
		_check(not g.view_for(p).pending_choice.has("options"),"enemy cannot see hand options")
		var choice:Dictionary=g.state.pending_choice
		_check(not g._action_error(p,{"type":"choose_card","choice_id":choice.choice_id,"option_index":0}).is_empty(),"wrong player cannot choose")
		var restored:=EngineClass.new();restored.state=g.state.duplicate(true)
		for engine in [g,restored]:_check(engine.apply_action(owner,{"type":"choose_card","choice_id":choice.choice_id,"option_index":0}).is_empty(),"valid choice resumes full action")
		_check(Runtime.sha(g.state)==Runtime.sha(restored.state),"choice replay deterministic after reload")
		var held:Dictionary=g.state.players[owner].hand[0].card
		_check(g.play_cost(owner,held)==2 and held.definition.cost==3,"runtime cost changes, frozen card untouched")
		var effect:Dictionary=fixtures[5].definition.abilities[0].effects[0].duplicate(true);effect.selection="all"
		var ctx:Dictionary=g._context(owner,-1,_compile(fixtures[5].definition))
		for n in 4:g._effect(effect,ctx)
		_check(g.play_cost(owner,held)==0,"discount stacks with zero floor")
		g.state.active_player=owner;g.state.players[owner].credits=12;g.state.players[owner].max_credits=12
		var hand_id:String=g.state.players[owner].hand[0].instance_id
		_check(g.apply_action(owner,{"type":"play","hand_id":hand_id}).is_empty(),"zero cost card can be played")
		if kind=="counter":
			_check(g.play_cost(owner,g.state.players[owner].counters[0].card)==0,"armed counter remains hidden hand")
		else:
			_check(g.state.players[owner].credits==12,"actual payment uses discount")
			if kind=="unit":
				var unit:Dictionary=g.state.units.filter(func(u):return u.owner==owner)[0]
				g._leave_battlefield(unit,true)
				_check(g.play_cost(owner,g.state.players[owner].hand.back().card)==3,"hand-only discount gone on reentry")
	# Expiring and permanent costs are distinct; permanent copy honors inheritance source.
	var g:=_game();var p:=_rich(g);g.state.players[p].hand=[];g._receive_card(p,_compile(_base()),"test")
	var ctx:Dictionary=g._context(p,-1,_compile(_base()))
	g._effect({"op":"modify_hand_cost","selection":"all","cost_delta":-1,"duration":"end_of_turn"},ctx)
	var card:Dictionary=g.state.players[p].hand[0].card
	_check(g.play_cost(p,card)==0,"turn discount applies");g.state.turn+=1
	_check(g.play_cost(p,card)==1,"turn discount expires")
	g._effect({"op":"modify_hand_cost","selection":"all","cost_delta":-1,"duration":"match"},ctx)
	card.erase("hand_cost_layers");g._receive_card(p,card.duplicate(true),"return")
	_check(g.play_cost(p,g.state.players[p].hand.back().card)==0,"permanent cost survives reentry")
	g._filter_inherited_layers(card,[]);_check(g.play_cost(p,card)==1,"restricted copies exclude unapproved permanent cost")

func _deck_choices() -> void:
	for crowded in [false,true]:
		var g:=_game();var p:=_rich(g);var owner:=1-p
		var source:Dictionary=g._new_unit(owner,_compile(fixtures[6].definition))
		# For a full post-death row the source starts on the front line.
		if crowded:
			g._remove_from_line(source);source.row="front";g._position_unit(source)
			for n in 4:g._new_unit(owner,_compile(_base(str(n))))
		var d:=_base("玉石一");d["faction_id"]=fixtures[6].definition.abilities[0].effects[0].filter.faction_id
		var first:=_compile(d);d.name="玉石二";var second:=_compile(d)
		g.state.players[owner].deck=[first,_compile(_base("其他阵营")),second]
		_kill_source(g,source.uid)
		if crowded:
			_check(not g.state.has("pending_choice") and g.state.players[owner].deck.size()==3,"full support does not choose or consume deck")
			continue
		_check(g.state.pending_choice.kind=="search" and g.state.pending_choice.options.size()==2,"deck selection uses matching faction units")
		_check(not g.view_for(p).pending_choice.has("options"),"deck candidates private")
		var choice:Dictionary=g.state.pending_choice
		_check(g.apply_action(owner,{"type":"choose_card","choice_id":choice.choice_id,"option_index":1}).is_empty(),"choose exact second candidate")
		_check(g.state.players[owner].deck.size()==2 and g.state.players[owner].deck[0].definition.name=="玉石一","only chosen card removed, other order intact")
		_check(g.state.units.any(func(u):return u.owner==owner and u.card.definition.name=="玉石二"),"chosen unit summoned to owner support")
