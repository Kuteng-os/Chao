extends SceneTree
const Runtime = preload("res://scripts/core/card_runtime.gd")
const EngineClass = preload("res://scripts/core/battle_engine.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	if not OS.get_environment("FRONTLINE_PARITY_INPUT").is_empty():
		_test_backend_parity(OS.get_environment("FRONTLINE_PARITY_INPUT"))
		print("CROSS-RUNTIME PARITY: %d checks, %d failures" % [checks, failures])
		quit(1 if failures else 0)
		return
	_test_canonical()
	_test_strict_json()
	_test_compiler()
	_test_actions_and_views()
	_test_effects_and_cleanup()
	_test_combat()
	_test_death_order()
	_test_random_and_budget()
	_test_cleanup_chain()
	_test_replay()
	print("ENGINE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/" + path))

func _base(name: String = "测试单位", kind: String = "unit") -> Dictionary:
	return {"schema_version": "1.0.0", "ruleset_version": "frontline-1", "name": name, "flavor_text": "", "kind": kind, "unit_class": "tank" if kind == "unit" else null, "cost": 1, "operation_cost": 1 if kind == "unit" else 0, "attack": 3 if kind == "unit" else 0, "health": 4 if kind == "unit" else 0, "keywords": [], "play_target": null, "abilities": [], "tokens": [], "appearance": {"emblem": "tank" if kind == "unit" else "order"}}

func _compile(card: Dictionary) -> Dictionary:
	var result := Runtime.compile_card(card, Runtime.builtin_keywords())
	_check(result.ok, "fixture compiles: " + result.get("error", ""))
	return result

func _deck() -> Array:
	var cards := []
	for i in 10:
		var card := _compile(_base("测试单位" + str(i)))
		for j in 4:
			cards.append(card)
	return cards

func _game(seed_value: int = 42) -> RefCounted:
	var game := EngineClass.new()
	var deck := _deck()
	_check(game.setup(deck, deck, seed_value).is_empty(), "setup valid deck")
	return game

func _rich(game: RefCounted) -> int:
	var active: int = game.state.active_player
	game.state.players[active].max_credits = 12
	game.state.players[active].credits = 12
	return active

func _play(game: RefCounted, spec: Dictionary, target: int = -1) -> int:
	var owner := _rich(game)
	var id: String = "test" + str(game.state.next_hand_id)
	game.state.next_hand_id += 1
	game.state.players[owner].hand.append({"instance_id": id, "card": _compile(spec)})
	var uid: int = game.state.next_uid
	var error: String = game.apply_action(owner, {"type": "play", "hand_id": id, "target_uid": target})
	_check(error.is_empty(), "play: " + error)
	return uid

func _test_canonical() -> void:
	for vector in _read("canonical_vectors.json").vectors:
		var input: Variant = JSON.parse_string(vector.input_json)
		_check(Runtime.canonical(input) == vector.canonical_utf8, "canonical " + vector.name)
		_check(Runtime.sha(input) == vector.sha256, "sha " + vector.name)
	_check(Runtime.normalize_text("\u1100\u1161\u11a8") == "각", "Hangul NFC")

func _test_strict_json() -> void:
	for text in ['{"a":1,"a":2}', '{"a":1,"\\u0061":2}', '{"a":1,}', '[1,]', '{} trailing', 'NaN', 'Infinity', '1e999', '01', '"\\ud800"', '"\\udc00"', '"\\ud800\\u0041"', '"unclosed']:
		_check(not Runtime.parse_json(text).ok, "strict JSON rejects " + text)
	_check(Runtime.parse_json('{"a":[true,false,null,1.0,-2],"emoji":"\\ud83d\\ude00"}').ok, "strict valid JSON surrogate pair")
	_check(Runtime.parse_json('"\\b\\f\\n\\r\\t\\\\\\\"\\/"').ok, "strict supported escapes")
	_check(not Runtime.parse_json("[".repeat(18) + "0" + "]".repeat(18)).ok, "strict max depth")
	_check(not Runtime.parse_json('{"a":1}', 2).ok, "strict byte size")
	_check(not Runtime.parse_json('{"a":1.25}').ok, "strict math integer")

func _test_compiler() -> void:
	var keywords: Array = Runtime.builtin_keywords()
	keywords.append(_read("keywords/example_supply.json"))
	var compiled := Runtime.compile_card(_read("valid_unit.json"), keywords)
	var expected: Dictionary = _read("compiled_unit.json")
	_check(compiled.ok, "official fixture compiles")
	if compiled.ok:
		_check(compiled.compiled_program_hash == expected.compiled_program_hash, "compiled fixture exact hash")
		_check(compiled.definition_hash == expected.compiled_program.definition_hash, "source fixture exact hash")
		_check(compiled.definition.abilities.size() == 1 and compiled.definition.keywords.size() == 1, "template expands once")
		_check("抽1张牌" in Runtime.rules_text(compiled), "rules text from program")
	_check(not Runtime.compile_card(_read("invalid_unknown_op.json"), keywords).ok, "unknown op rejected")
	_check(not Runtime.compile_card(_read("invalid_semantic_target.json"), keywords).ok, "invalid semantics rejected")
	var card := _base()
	card.cost = true
	_check(not Runtime.compile_card(card, keywords).ok, "bool is not integer")
	card = _base()
	card.attack = 1.5
	_check(not Runtime.compile_card(card, keywords).ok, "fraction rejected")
	card = _base()
	card.script = "res://injected.gd"
	_check(not Runtime.compile_card(card, keywords).ok, "unknown card field rejected")
	card = _base()
	card.keywords = [{"id": "core.blitz", "version": 3, "params": {}}]
	_check(not Runtime.compile_card(card, keywords).ok, "exact keyword version")
	card.keywords = [{"id": "core.blitz", "version": 1, "params": {}}, {"id": "core.blitz", "version": 1, "params": {}}]
	_check(not Runtime.compile_card(card, keywords).ok, "duplicate keyword rejected")
	var template: Dictionary = _read("keywords/example_supply.json")
	template.parameters.amount.maximum = 4
	_check(not Runtime.validate_keyword(template).is_empty(), "all parameter values validated")
	var swapped: Dictionary = keywords[0].duplicate(true)
	swapped.implementation.builtin_id = "core.guard.v1"
	_check(not Runtime.validate_keyword(swapped).is_empty(), "builtin identity not spoofable")
	card = _base("空指令", "order")
	_check(not Runtime.compile_card(card, keywords).ok, "empty order rejected")
	card = _base()
	card.play_target = {"side": "enemy", "row": "any"}
	_check(not Runtime.compile_card(card, keywords).ok, "unused chosen selector rejected")

func _test_actions_and_views() -> void:
	var game := _game()
	var active: int = game.state.active_player
	var before := Runtime.canonical(game.state)
	_check(not game.apply_action(1 - active, {"type": "end_turn"}).is_empty(), "wrong turn rejected")
	_check(before == Runtime.canonical(game.state), "illegal action leaves all state and RNG unchanged")
	_check(not game.apply_action(active, {"type": "move", "uid": true}).is_empty(), "invalid action integer rejected")
	var view: Dictionary = game.view_for(active)
	_check(view.players[1 - active].hand.is_empty() and view.players[active].deck.is_empty(), "private cards hidden")
	_check(not view.has("rng_state") and not view.has("private_log") and not view.has("seed"), "private RNG hidden")
	_check(view.players[1 - active].hand_count == 5 and view.players[active].hand_count == 5, "initial hand counts")
	var uid := _play(game, _base())
	_check(not game.can_move(uid), "new unit summoning sickness")
	_check(game.apply_action(1 - active, {"type": "concede"}).is_empty() and game.state.winner == active, "off-turn concede allowed")
	var duplicate := _deck()
	for i in 40: duplicate[i] = duplicate[0]
	_check(not EngineClass.new().setup(duplicate, duplicate, 42).is_empty(), "max three enforced")
	_check(not EngineClass.new().setup([], [], 42).is_empty(), "deck size enforced")

func _test_effects_and_cleanup() -> void:
	var game := _game()
	var owner := _rich(game)
	var spec := _base("全操作单位")
	spec.keywords = [{"id": "core.blitz", "version": 1, "params": {}}]
	spec.tokens = [{"token_id": "recruit", "name": "测试衍生物", "unit_class": "infantry", "attack": 1, "health": 2, "keywords": [{"id": "core.guard", "version": 1, "params": {}}]}]
	spec.abilities = [{"trigger": "on_play", "effects": [{"op": "damage", "target": "own_hq", "amount": 3}, {"op": "heal", "target": "own_hq", "amount": 1}, {"op": "draw", "player": "owner", "amount": 1}, {"op": "gain_kredits", "amount": 3}]}, {"trigger": "on_play", "effects": [{"op": "modify_stats", "target": "self", "attack_delta": 2, "health_delta": 2, "duration": "end_of_turn"}, {"op": "grant_keyword", "target": "self", "keyword_id": "core.guard", "keyword_version": 1, "duration": "end_of_turn"}, {"op": "summon", "token_id": "recruit", "amount": 2, "row": "support"}]}]
	var initial_hand: int = game.state.players[owner].hand.size()
	var uid := _play(game, spec)
	_check(game.state.players[owner].hp == 18, "damage then heal HQ")
	_check(game.state.players[owner].credits == 12, "resource gain capped at existing slots")
	_check(game.state.players[owner].hand.size() == initial_hand + 1, "draw operation")
	_check(game.state.units.size() == 3, "summon creates two tokens")
	_check(game._operation_cost(game.state.units[1]) == 1, "token action cost fixed one")
	_check(game._unit(uid).attack == 5 and game._unit(uid).max_hp == 6, "stat modifier")
	_check(game._has_keyword(game._unit(uid), "core.guard"), "grant guard")
	_check(game.can_move(uid), "builtin blitz ready immediately")
	game._unit(uid).damage_taken = 3
	game._recompute(game._unit(uid))
	_check(game.apply_action(owner, {"type": "end_turn"}).is_empty(), "end turn cleanup")
	_check(game._unit(uid).max_hp == 4 and game._unit(uid).hp == 1, "expiry preserves damage")
	_check(not game._has_keyword(game._unit(uid), "core.guard") and game._has_keyword(game._unit(uid), "core.blitz"), "expiry removes only temporary keyword")
	game.state.players[game.state.active_player].deck = []
	game.state.players[game.state.active_player].hp = 1
	var active: int = game.state.active_player
	var fatigue := _base("疲劳指令", "order")
	fatigue.abilities = [{"trigger": "on_play", "effects": [{"op": "draw", "player": "owner", "amount": 2}, {"op": "heal", "target": "own_hq", "amount": 10}]}]
	_play(game, fatigue)
	_check(game.state.winner == 1 - active and game.state.players[active].hp == 0, "lethal checkpoint stops later heal")

func _test_combat() -> void:
	var game := _game()
	var attacker_owner: int = game.state.active_player
	var spec := _base("突击坦克")
	spec.keywords = [{"id": "core.blitz", "version": 1, "params": {}}]
	var attacker := _play(game, spec)
	_check(game.apply_action(attacker_owner, {"type": "move", "uid": attacker}).is_empty(), "tank can advance")
	_check(-1 in game.legal_targets(attacker_owner, {"type": "attack", "uid": attacker}), "front permits HQ attack")
	var guard := _base("守护者")
	guard.keywords = [{"id": "core.guard", "version": 1, "params": {}}]
	var defender: Dictionary = game._new_unit(1 - attacker_owner, _compile(guard))
	_check(not -1 in game.legal_targets(attacker_owner, {"type": "attack", "uid": attacker}), "support guard protects HQ")
	_check(game.apply_action(attacker_owner, {"type": "attack", "uid": attacker, "target_uid": defender.uid}).is_empty(), "guard legal attack")
	_check(game._unit(attacker).hp == 1 and game._unit(defender.uid).hp == 1, "ordinary damage simultaneous retaliation")
	game._unit(attacker).attacked = false
	game._unit(attacker).attacks_used = 0
	_rich(game)
	game.apply_action(attacker_owner, {"type": "attack", "uid": attacker, "target_uid": defender.uid})
	_check(game.state.units.is_empty(), "simultaneous deaths removed")
	var infantry := _base("步兵")
	infantry.unit_class = "infantry"
	infantry.keywords = spec.keywords
	var foot := _play(game, infantry)
	game.apply_action(attacker_owner, {"type": "move", "uid": foot})
	_check(game._unit(foot).attacked, "infantry move consumes attack")

func _test_death_order() -> void:
	var game := _game()
	var owner := _rich(game)
	var victim := _base("死亡触发单位")
	victim.health = 1
	victim.abilities = [{"trigger": "on_death", "effects": [{"op": "damage", "target": "enemy_hq", "amount": 2}]}]
	var uid := _play(game, victim)
	var order := _base("先伤害后治疗", "order")
	order.play_target = {"side": "ally", "row": "any"}
	order.abilities = [{"trigger": "on_play", "effects": [{"op": "damage", "target": "chosen", "amount": 1}, {"op": "heal", "target": "chosen", "amount": 10}, {"op": "heal", "target": "enemy_hq", "amount": 1}]}]
	game.state.players[1 - owner].hp = 10
	_play(game, order, uid)
	_check(game._unit(uid).is_empty(), "death removes before later heal")
	_check(game.state.players[1 - owner].hp == 9, "death FIFO after source ability completes")
	var unit := _base("回合触发器")
	unit.abilities = [{"trigger": "own_turn_start", "effects": [{"op": "heal", "target": "own_hq", "amount": 1}]}, {"trigger": "own_turn_end", "effects": [{"op": "damage", "target": "enemy_hq", "amount": 1}]}]
	_play(game, unit)
	game.state.players[owner].hp = 15
	game.apply_action(owner, {"type": "end_turn"})
	_check(game.state.players[1 - owner].hp == 8, "turn end trigger")
	game.apply_action(1 - owner, {"type": "end_turn"})
	_check(game.state.players[owner].hp == 16, "turn start trigger")

func _test_replay() -> void:
	var first := _game(9981)
	var second := _game(9981)
	for i in 120:
		if first.state.winner != -1: break
		var player: int = first.state.active_player
		var action: Dictionary = first.ai_action(player)
		var first_error: String = first.apply_action(player, action)
		var second_error: String = second.apply_action(player, action)
		_check(first_error.is_empty() and second_error.is_empty(), "AI emits valid action " + str(i))
		_check(Runtime.sha(first.state) == Runtime.sha(second.state), "seeded replay step " + str(i))
	_check(first.state.state_seq > 20, "AI battle progresses")

func _test_random_and_budget() -> void:
	var first := _game(7654)
	var second := _game(7654)
	var random_order := _base("随机测试", "order")
	random_order.abilities = [{"trigger": "on_play", "effects": [{"op": "damage", "target": "random_enemy_unit", "amount": 1}, {"op": "damage", "target": "random_enemy_unit", "amount": 1}]}]
	for game in [first, second]:
		for i in 3:
			game._new_unit(1 - int(game.state.active_player), _compile(_base("目标" + str(i))))
		_play(game, random_order)
	_check(Runtime.sha(first.state) == Runtime.sha(second.state), "random target replay exact")
	var before := Runtime.sha(first.state)
	first.apply_action(first.state.active_player, {"type": "play", "hand_id": "missing", "target_uid": -1})
	_check(Runtime.sha(first.state) == before, "invalid action never consumes random")
	var game := _game()
	var owner: int = game.state.active_player
	var source := _base("层数上限测试")
	var uid := _play(game, source)
	for i in 64:
		game._unit(uid).modifiers.append({"modifier_id": i, "attack_delta": 1, "health_delta": 0, "source_uid": uid, "expires_turn": -1})
	game._recompute(game._unit(uid))
	var overflow := _base("越界层", "order")
	overflow.play_target = {"side": "ally", "row": "any"}
	overflow.abilities = [{"trigger": "on_play", "effects": [{"op": "modify_stats", "target": "chosen", "attack_delta": 1, "health_delta": 0, "duration": "battle"}]}]
	_rich(game)
	game.state.players[owner].hand.append({"instance_id": "overflow", "card": _compile(overflow)})
	var previous: Dictionary = game.state.duplicate(true)
	var error: String = game.apply_action(owner, {"type": "play", "hand_id": "overflow", "target_uid": uid})
	_check(error == "RULE_BUDGET_EXCEEDED" and game.state.winner == 3, "runtime budget aborts")
	_check(game.state.players == previous.players and game.state.units == previous.units and game.state.rng_state == previous.rng_state, "budget rolls back cards units resources RNG")
	_check(game.state.state_seq == previous.state_seq + 1, "budget commits only abort transition")

func _test_backend_parity(path: String) -> void:
	var corpus: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	for test_case in corpus:
		var result := Runtime.compile_card(test_case.definition, test_case.keywords)
		var identical: bool = result.ok == test_case.expected.ok
		if result.ok and test_case.expected.ok:
			identical = identical and result.definition_hash == test_case.expected.definition_hash and result.compiled_program_hash == test_case.expected.compiled_program_hash
		_check(identical, "backend parity " + test_case.name + ": " + result.get("error", ""))

func _test_cleanup_chain() -> void:
	var game := _game()
	var owner: int = game.state.active_player
	var permanent_guard := _base("固有守护")
	permanent_guard.keywords = [{"id": "core.guard", "version": 1, "params": {}}]
	var survivor := _play(game, permanent_guard)
	var expiring := _base("清理阶段触发")
	expiring.health = 1
	expiring.abilities = [{"trigger": "on_play", "effects": [{"op": "modify_stats", "target": "self", "attack_delta": 0, "health_delta": 4, "duration": "end_of_turn"}]}, {"trigger": "on_death", "effects": [{"op": "grant_keyword", "target": "all_friendly_units", "keyword_id": "core.guard", "keyword_version": 1, "duration": "end_of_turn"}, {"op": "modify_stats", "target": "all_friendly_units", "attack_delta": 0, "health_delta": 3, "duration": "end_of_turn"}]}]
	var uid := _play(game, expiring)
	game._unit(uid).damage_taken = 2
	game._recompute(game._unit(uid))
	game.apply_action(owner, {"type": "end_turn"})
	_check(game._unit(uid).is_empty(), "expiry loss of max HP causes death")
	_check(game._unit(survivor).max_hp == 4 and game._unit(survivor).grants.is_empty(), "cleanup also expires layers created by death during cleanup")
	_check(game._has_keyword(game._unit(survivor), "core.guard"), "cleanup retains innate guard")
	game._unit(survivor).modifiers.append({"modifier_id": 1000, "attack_delta": -5, "health_delta": -5, "source_uid": survivor, "expires_turn": -1})
	game._recompute(game._unit(survivor))
	_check(game._unit(survivor).attack == 0 and game._unit(survivor).max_hp == 0, "stat reductions can lower defense to zero")
	game._checkpoint()
	_check(game._unit(survivor).is_empty(),"Zero defense destroys unit at checkpoint")
