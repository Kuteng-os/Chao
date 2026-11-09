extends "res://tests/test_copy836.gd"

func _initialize() -> void:
	registered=JSON.parse_string(FileAccess.get_file_as_string("res://tests/copy836_cards.json"))
	_inherited_layers()
	_fighter_movement()
	print("FOLLOWUPS837: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _inherited_layers() -> void:
	for row in registered.slice(0,2):
		for seat in [0,1]:
			var g:=_game();g.state.active_player=seat;_rich(g)
			var c:=_compile(row.definition)
			g.state.players[seat].hand=[]
			g.state.players[seat].deck=[c.duplicate(true)]
			var uid:int=g._new_unit(seat,c).uid
			for repeat in 2:
				g.state.players[seat].hand=[]
				g._receive_card(seat,c.duplicate(true),"test")
				_play(g,registered[2].definition)
				_check(g.state.pending_choice.kind=="discard","second hatching still asks for discard")
				_check(g.apply_action(seat,{"type":"choose_card","choice_id":g.state.pending_choice.choice_id,"option_index":0}).is_empty(),"repeat hatching resolves")
			var unit:Dictionary=g._unit(uid)
			_check(unit.attack==int(c.definition.attack)+4 and unit.max_hp==int(c.definition.health)+4,"two hatching permanent stat layers stack")
			_check(unit.ability_layers.size()==2 and unit.operation_cost==maxi(0,int(c.definition.operation_cost)-2),"two granted draw layers and cost reductions stack")
			g._leave_battlefield(unit,true)
			var returned:Dictionary=g.state.players[seat].hand.back().card
			_check(returned.match_abilities.size()==2,"return keeps both permanent granted abilities")
			g.state.players[seat].deck=[]
			for index in 5:g.state.players[seat].deck.append(_compile(_base("验证抽牌"+str(index))))
			g.state.players[seat].credits=12
			_check(g.apply_action(seat,{"type":"play","hand_id":g.state.players[seat].hand.back().instance_id}).is_empty(),"enhanced returned unit redeploys")
			_check(g.state.players[seat].deck.size()==3,"both inherited deployment draw abilities execute once each")
			uid=g.state.units.back().uid
			# Rehydrate as an authoritative server/reconnect would.
			var restored:=EngineClass.new();restored.state=Runtime._normalized(JSON.parse_string(JSON.stringify(g.state)));restored._reset_budget();g=restored
			for generation in 3:
				var before:int=g.state.players[seat].deck.size()
				_kill(g,seat,uid)
				_check(g.state.players[seat].deck.size()==before+1,"each enhanced death adds a real deck card")
				var copies:Array=g.state.players[seat].deck.filter(func(card):return card.definition.name==c.definition.name)
				_check(copies.size()==1,"one distinct generated copy")
				var copy:Dictionary=copies[0]
				_check(copy.match_abilities.size()==2 and copy.match_layers.size()==4,"copies retain each permanent layer exactly once across generations")
				_check(copy.definition_hash==c.definition_hash,"no mutation of public card version")
				g.state.players[seat].deck.erase(copy)
				unit=g._new_unit(seat,copy);uid=unit.uid
				_check(unit.attack==int(c.definition.attack)+4 and unit.hp==int(c.definition.health)+4,"all generations retain both stat buffs")
				_check(g._abilities(g._context(seat,uid,unit.card),"on_play").size()==2,"all generations retain both deployment abilities")
			g._suppress(unit)
			_check(unit.ability_layers.is_empty() and not unit.card.has("match_layers"),"suppression removes attached effects explicitly")

func _fighter_movement() -> void:
	for seat in [0,1]:
		for blitz in [false,true]:
			var g:=_game();g.state.active_player=seat;_rich(g)
			var d:=_base("战斗机");d.unit_class="fighter";d.appearance.emblem="fighter"
			if blitz:d.keywords=[{"id":"core.blitz","version":1,"params":{}}]
			var u:Dictionary=g._new_unit(seat,_compile(d));u.born_turn=-1
			_check(g.can_move(u.uid),"fighter can move before attack")
			_check(g.apply_action(seat,{"type":"attack","uid":u.uid,"target_uid":-1}).is_empty(),"actual HQ attack succeeds")
			_check(g.can_move(u.uid)==blitz,"after attack only blitz fighter can advance")
			var snap:=Runtime.sha(g.state)
			var error:String=g.apply_action(seat,{"type":"move","uid":u.uid,"position":0})
			_check(error.is_empty()==blitz,"authority enforces movement rule")
			if not blitz:
				_check(Runtime.sha(g.state)==snap,"rejected movement changes neither fee nor position")
				g._effect({"op":"set_attack_limit","target":"self","attacks":2,"duration":"battle"},g._context(seat,u.uid,u.card))
				_check(not g.can_move(u.uid),"remaining extra attack does not bypass restriction")
				g.apply_action(seat,{"type":"end_turn"});g.apply_action(1-seat,{"type":"end_turn"})
				_check(g.can_move(u.uid),"next turn resets attack restriction")
			else:
				_check(g._unit(u.uid).row=="front","blitz advance commits")
		# Merely counting as a fighter does not change the printed class movement.
		var g:=_game();g.state.active_player=seat;_rich(g)
		var u:Dictionary=g._new_unit(seat,_compile(_base("坦克兼战斗机")));u.born_turn=-1;u.attacks_used=1
		g._effect({"op":"grant_unit_class","target":"self","unit_class":"fighter","duration":"match"},g._context(seat,u.uid,u.card))
		_check(g.can_move(u.uid),"additional fighter identity leaves tank movement unchanged")
