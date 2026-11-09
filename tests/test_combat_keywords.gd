extends "res://tests/test_mechanics.gd"

func _initialize() -> void:
	_catalog()
	_ambush()
	_bomber_retaliation()
	_shock_and_fury()
	_smokescreen()
	print("COMBAT KEYWORDS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _board() -> RefCounted:
	var engine := _game()
	engine.state.active_player = 0
	engine.state.players[0].credits = 12
	return engine

func _soldier(game: RefCounted, owner: int, keywords: Array, attack: int, health: int, type: String = "fighter") -> Dictionary:
	var source := _base("组合词条测试")
	source.unit_class = type
	source.appearance.emblem = type
	source.attack = attack
	source.health = health
	for key in keywords: source.keywords.append({"id":"core."+key,"version":1,"params":{}})
	var unit: Dictionary = game._new_unit(owner,_compile(source))
	unit.born_turn = -1
	return unit

func _hit(game: RefCounted, attacker: int, defender: int) -> void:
	_check(game.apply_action(game.state.active_player,{"type":"attack","uid":attacker,"target_uid":defender}).is_empty(),"Combat keyword attack resolves")

func _catalog() -> void:
	for key in ["ambush","fury","smokescreen","shock"]:
		var spec := _base(key)
		spec.keywords = [{"id":"core."+key,"version":1,"params":{}}]
		var compiled := _compile(spec)
		_check(Runtime.keyword_name("core."+key) in Runtime.rules_text(compiled),"New keyword has its own visible name")
		_check(compiled.definition.keywords==spec.keywords,"Builtin remains an exact versioned reference")
	for key in ["guard","blitz"]:
		var spec := _base(key)
		spec.keywords = [{"id":"core."+key,"version":2,"params":{}}]
		_check(_compile(spec).ok,"Corrected naming/description preserves versioned builtin")
	var old: Dictionary = _read("keywords/core_guard.json")
	_check(Runtime.validate_keyword(old).is_empty(),"Old immutable guard definition remains valid")
	old.version = 3
	_check(not Runtime.validate_keyword(old).is_empty(),"Undeclared builtin version is rejected")

func _ambush() -> void:
	var game := _board()
	var attacker := _soldier(game,0,[],4,2)
	var defender := _soldier(game,1,["ambush"],2,9)
	_hit(game,attacker.uid,defender.uid)
	_check(game._unit(attacker.uid).is_empty(),"Lethal ambush destroys attacker first")
	_check(game._unit(defender.uid).hp==9,"Attacker killed by ambush deals no damage")
	var second := _soldier(game,0,[],4,2)
	_hit(game,second.uid,defender.uid)
	_check(game._unit(second.uid).is_empty() and game._unit(defender.uid).hp==5,"Ambush only triggers once in same turn")
	_round(game)
	var third := _soldier(game,0,[],4,2)
	_hit(game,third.uid,defender.uid)
	_check(game._unit(third.uid).is_empty() and game._unit(defender.uid).hp==5,"Ambush is ready again next turn")
	for type in ["artillery","bomber"]:
		game = _board()
		attacker = _soldier(game,0,[],3,2,type)
		defender = _soldier(game,1,["ambush"],9,9,"infantry")
		_hit(game,attacker.uid,defender.uid)
		_check(game._unit(attacker.uid).hp==2 and game._unit(defender.uid).hp==6,"Ambush never invents retaliation against ranged immunity")
	game = _board()
	attacker = _soldier(game,0,[],3,2,"bomber")
	defender = _soldier(game,1,["ambush"],3,9,"fighter")
	_hit(game,attacker.uid,defender.uid)
	_check(game._unit(attacker.uid).is_empty() and game._unit(defender.uid).hp==9,"Fighter ambush can intercept a bomber")

func _shock_and_fury() -> void:
	var game := _board()
	var attacker := _soldier(game,0,["shock","fury"],4,3)
	var defender := _soldier(game,1,["ambush"],10,20)
	var credits: int = game.state.players[0].credits
	_hit(game,attacker.uid,defender.uid)
	_check(game._unit(attacker.uid).hp==3 and game._unit(defender.uid).hp==16,"Shock prevents Ambush damage on first strike")
	_check(not game._has_keyword(game._unit(attacker.uid),"core.shock"),"Shock is consumed")
	_check(game.state.players[0].credits==credits-1,"First Fury attack pays operation cost")
	_hit(game,attacker.uid,defender.uid)
	_check(game._unit(attacker.uid).is_empty() and game._unit(defender.uid).hp==12,"Second Fury attack has normal retaliation")
	_check(game.state.players[0].credits==credits-2,"Second Fury attack pays separately")
	game = _board()
	attacker = _soldier(game,0,["fury"],1,20)
	defender = _soldier(game,1,[],1,20)
	_hit(game,attacker.uid,defender.uid)
	_hit(game,attacker.uid,defender.uid)
	_check(not game.apply_action(0,{"type":"attack","uid":attacker.uid,"target_uid":defender.uid}).is_empty(),"Fury never permits a third attack")
	_round(game)
	_check(not game.legal_targets(0,{"type":"attack","uid":attacker.uid}).is_empty(),"Fury refreshes attacks next own turn")
	game = _board()
	attacker = _soldier(game,0,["shock"],1,20)
	defender = _soldier(game,1,[],2,20)
	_hit(game,attacker.uid,defender.uid)
	_round(game)
	_check(not game._has_keyword(game._unit(attacker.uid),"core.shock"),"Shock does not regenerate on turn changes")
	_buff(game,attacker.uid,{"op":"grant_keyword","target":"chosen","keyword_id":"core.shock","keyword_version":1,"duration":"battle"})
	_check(game._has_keyword(game._unit(attacker.uid),"core.shock"),"A new grant can restore spent Shock")
	_hit(game,attacker.uid,defender.uid)
	_check(game._unit(attacker.uid).hp==20,"Newly granted Shock prevents retaliation once more")

func _smokescreen() -> void:
	var game := _board()
	var smoke := _soldier(game,1,["smokescreen"],1,9,"tank")
	for type in ["fighter","bomber","artillery"]:
		var attacker := _soldier(game,0,[],1,9,type)
		_check(smoke.uid not in game.legal_targets(0,{"type":"attack","uid":attacker.uid}),"Smoke blocks all ordinary unit attacks")
	var spell := _base("烟幕不能挡指令","order")
	spell.play_target = {"side":"enemy","row":"any"}
	spell.abilities = [{"trigger":"on_play","effects":[{"op":"damage","target":"chosen","amount":2}]}]
	_play(game,spell,smoke.uid)
	_check(game._unit(smoke.uid).hp==7,"Order can select and damage Smokescreen")
	game.state.active_player = 1
	game.state.players[1].credits = 12
	_check(game.apply_action(1,{"type":"move","uid":smoke.uid,"position":0}).is_empty(),"Smokescreen unit moves normally")
	_check(not game._has_keyword(game._unit(smoke.uid),"core.smokescreen"),"Moving consumes Smoke")
	_round(game)
	_check(not game._has_keyword(game._unit(smoke.uid),"core.smokescreen"),"Smoke never returns merely by waiting a turn")

func _bomber_retaliation() -> void:
	for type in ["infantry", "tank", "artillery", "fighter", "bomber"]:
		for ambush in [false, true]:
			var game := _board()
			var attacker := _soldier(game, 0, [], 3, 20, type)
			var defender := _soldier(game, 1, ["ambush"] if ambush else [], 10, 20, "bomber")
			attacker.row = "front"
			_hit(game, attacker.uid, defender.uid)
			_check(game._unit(attacker.uid).hp == 20 and game._unit(defender.uid).hp == 17, "Bombers never retaliate, including Ambush and bomber attackers")
	var game := _board()
	var bomber := _soldier(game, 0, [], 3, 20, "bomber")
	var fighter := _soldier(game, 1, [], 4, 20, "fighter")
	_hit(game, bomber.uid, fighter.uid)
	_check(game._unit(bomber.uid).hp == 16 and game._unit(fighter.uid).hp == 17, "Fighters still retaliate against attacking bombers")
