extends RefCounted
## Headless card trial for tools: plays one card through the real battle engine and writes a step-by-step report.
## Run with: Frontline.exe --headless -- --card-trial=<job.json> --card-trial-out=<report.json>

const Runtime = preload("res://scripts/core/card_runtime.gd")
const EngineClass = preload("res://scripts/core/battle_engine.gd")
const MAX_JOB_BYTES := 8388608
const MAX_STEPS := 40
const MAX_CHOICES := 24
const RICH_CREDITS := 12
const HAND_ID := "trial-card"
const KILL_HAND_ID := "trial-kill"
const ACTIONS := ["play", "move", "attack", "activate", "end_turn", "enemy_ai", "kill"]
const DEFAULT_ACTIONS := {
	"unit": ["play", "end_turn", "end_turn", "move", "attack", "activate", "end_turn", "end_turn", "kill"],
	"order": ["play", "end_turn", "end_turn"],
	"counter": ["play", "end_turn", "enemy_ai", "end_turn"],
	"field": ["play", "end_turn", "end_turn"],
	"hq": ["end_turn", "end_turn"],
}
const DEFAULT_ALLIES := [{"name":"试卡友军","unit_class":"infantry","attack":1,"health":3,"row":"support"}]
const DEFAULT_ENEMIES := [{"name":"试卡敌军甲","unit_class":"infantry","attack":2,"health":3,"row":"support"},{"name":"试卡敌军乙","unit_class":"tank","attack":3,"health":4,"row":"support"}]

var game: RefCounted
var keywords: Array = []
var me := 0
var enemy := 1
var tested_uid := 0
var choices: Array = []
var target_index := 0
var attack_target_index := 0
var activate_index := 0

static func arguments(args: PackedStringArray) -> Dictionary:
	var found := {}
	for arg in args:
		if arg.begins_with("--card-trial="): found["job"] = arg.get_slice("=", 1)
		elif arg.begins_with("--card-trial-out="): found["out"] = arg.get_slice("=", 1)
	return found if found.has("job") and found.has("out") else {}

func execute(job_path: String, out_path: String) -> void:
	var report := _run_job(job_path)
	var temp := out_path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(report))
	file.close()
	DirAccess.rename_absolute(temp, out_path)

func _fail(message: String) -> Dictionary:
	return {"ok":false,"error":message}

func _run_job(job_path: String) -> Dictionary:
	var parsed := Runtime.parse_json(FileAccess.get_file_as_string(job_path), MAX_JOB_BYTES)
	if not parsed.ok or not parsed.value is Dictionary: return _fail("试卡任务无法读取。")
	var job: Dictionary = parsed.value
	if not job.get("card") is Dictionary: return _fail("试卡任务缺少 card。")
	keywords = job.get("keywords", []) if job.get("keywords") is Array else []
	if keywords.is_empty(): keywords = Runtime.builtin_keywords()
	var scenario: Dictionary = job.get("scenario", {}) if job.get("scenario") is Dictionary else {}
	return _trial(job.card, scenario)

func _base(name_text: String, kind: String, unit_class: Variant, attack: int, health: int) -> Dictionary:
	return {"schema_version":"1.0.0","ruleset_version":"frontline-1","name":name_text,"flavor_text":"","kind":kind,"unit_class":unit_class,"cost":0 if kind == "order" else 1,"operation_cost":0 if kind == "order" else 1,"attack":attack,"health":health,"keywords":[],"play_target":null,"abilities":[],"tokens":[],"appearance":{"emblem":"order" if kind == "order" else unit_class}}

func _filler_deck() -> Array:
	var deck: Array = []
	for index in DeckRules.DECK_SIZE / 4:
		var compiled := Runtime.compile_card(_base("试卡牌%d" % index, "unit", "infantry", 1, 2), keywords)
		if not compiled.ok: return []
		for _copy in 4: deck.append(compiled)
	return deck

func _kill_order() -> Dictionary:
	var spec := _base("试卡·消灭", "order", null, 0, 0)
	spec.play_target = {"side":"enemy","row":"any"}
	spec.abilities = [{"trigger":"on_play","effects":[{"op":"destroy","target":"chosen"}]}]
	return Runtime.compile_card(spec, keywords)

func _trial(card: Dictionary, scenario: Dictionary) -> Dictionary:
	var compiled := Runtime.compile_card(card, keywords)
	if not compiled.ok: return _fail("卡牌未通过游戏编译：" + str(compiled.get("error", "")))
	var kind := str(compiled.definition.kind)
	var deck := _filler_deck()
	if deck.is_empty(): return _fail("无法准备试卡牌组。")
	game = EngineClass.new()
	var headquarters: Array = [compiled, {}] if kind == "hq" else []
	if kind == "hq": headquarters = [compiled, compiled]
	var error: String = game.setup(deck, deck, 20261109, headquarters)
	if not error.is_empty(): return _fail("无法开局：" + error)
	me = int(game.state.active_player)
	enemy = 1 - me
	choices = scenario.get("choices", []) if scenario.get("choices") is Array else []
	target_index = int(scenario.get("target_index", 0))
	attack_target_index = int(scenario.get("attack_target_index", 0))
	activate_index = int(scenario.get("activate_index", 0))
	for seat in 2:
		game.state.players[seat].max_credits = RICH_CREDITS
		game.state.players[seat].credits = RICH_CREDITS
	game.state.players[me].credits = int(clampi(int(scenario.get("credits", RICH_CREDITS)), 0, RICH_CREDITS))
	var placed := _place(me, scenario.get("my_units", DEFAULT_ALLIES))
	if placed.is_empty(): placed = _place(enemy, scenario.get("enemy_units", DEFAULT_ENEMIES))
	if not placed.is_empty(): return _fail(placed)
	if kind != "hq": game.state.players[me].hand.append({"instance_id":HAND_ID,"card":compiled})
	var requested: Variant = scenario.get("actions")
	var plan: Array = requested if requested is Array and not requested.is_empty() else DEFAULT_ACTIONS.get(kind, ["play"])
	var initial := _snapshot()
	var steps: Array = []
	for action in plan.slice(0, MAX_STEPS):
		var step := _step(str(action))
		steps.append(step)
		if step.status == "error" or int(game.state.winner) != -1: break
	return {"ok":true,"card":str(compiled.definition.name),"rules_text":Runtime.rules_text(compiled.definition),"plan":plan.slice(0, MAX_STEPS),"initial":initial,"steps":steps,"final":_snapshot(),"note":"me 是使用这张卡的一方，enemy 是对手。status=skipped 表示当前局面下该动作不合法。"}

func _place(owner: int, list: Variant) -> String:
	if not list is Array: return "单位列表必须是数组。"
	for raw in list.slice(0, 8):
		if not raw is Dictionary: return "单位配置必须是对象。"
		var unit_class := str(raw.get("unit_class", "infantry"))
		if not unit_class in ["infantry","tank","artillery","fighter","bomber"]: return "兵种无效：" + unit_class
		var spec := _base(str(raw.get("name", "试卡单位")).left(32), "unit", unit_class, clampi(int(raw.get("attack", 1)), 0, 20), clampi(int(raw.get("health", 2)), 1, 20))
		var compiled := Runtime.compile_card(spec, keywords)
		if not compiled.ok: return "试卡单位无效：" + str(compiled.get("error", ""))
		var row := str(raw.get("row", "support"))
		if not row in ["support","front"]: return "row 必须是 support 或 front。"
		var unit: Dictionary = game._new_unit(owner, compiled)
		if row == "front":
			game._remove_from_line(unit)
			unit.row = "front"
			game._position_unit(unit)
		game._recompute(unit)
	return ""

func _side(seat: int) -> String:
	return "me" if seat == me else "enemy"

func _name_of(uid: int) -> String:
	if uid == -1: return "无目标"
	if uid <= -101: return ("我方" if -101 - uid == me else "敌方") + "总部"
	var unit: Dictionary = game._unit(uid)
	return "" if unit.is_empty() else "%s(%s)" % [str(game._unit_definition(unit).name), "我方" if int(unit.owner) == me else "敌方"]

func _snapshot() -> Dictionary:
	var players := {}
	for seat in 2:
		var player: Dictionary = game.state.players[seat]
		players[_side(seat)] = {"hq_hp":int(player.hp),"credits":int(player.credits),"max_credits":int(player.max_credits),"hand":player.hand.size(),"deck":player.deck.size(),"hidden_counters":player.get("counters",[]).size()}
	var units: Array = []
	for unit in game.state.units:
		units.append({"uid":int(unit.uid),"side":_side(int(unit.owner)),"name":str(game._unit_definition(unit).name),"row":str(unit.row),"attack":int(unit.attack),"hp":int(unit.hp),"max_hp":int(unit.max_hp),"tested":int(unit.uid) == tested_uid})
	return {"turn":int(game.state.turn),"active":_side(int(game.state.active_player)),"players":players,"units":units,"winner":{-1:"none",me:"me",enemy:"enemy"}.get(int(game.state.winner), "aborted")}

func _step(action: String) -> Dictionary:
	var log_start: int = game.state.log.size()
	var taken: Array = []
	var outcome: Dictionary = _skip("未知动作，可用：" + ", ".join(ACTIONS)) if not action in ACTIONS else call("_do_" + action, taken)
	var result := {"action":action,"status":outcome.status,"detail":outcome.get("detail","")}
	if not taken.is_empty(): result["decisions"] = taken
	if int(game.state.get("winner", -1)) == 3: result["fault"] = str(game.state.get("error", ""))
	result["log"] = game.state.log.slice(mini(log_start, game.state.log.size()))
	result["state"] = _snapshot()
	return result

func _skip(detail: String) -> Dictionary:
	return {"status":"skipped","detail":detail}

func _done(detail: String = "") -> Dictionary:
	return {"status":"ok","detail":detail}

## Applies one action and answers any choice the engine raises, so nested triggers finish like a real match.
func _apply(player: int, action: Dictionary, taken: Array) -> Dictionary:
	var error: String = game.apply_action(player, action)
	if not error.is_empty(): return {"status":"error","detail":error}
	for _guard in MAX_CHOICES:
		if not game.state.has("pending_choice"): return _done()
		var choice: Dictionary = game.state.pending_choice
		var pick := int(choices.pop_front()) if not choices.is_empty() else 0
		if choice.get("kind","unit") != "unit":
			error = game.apply_action(int(choice.owner), {"type":"choose_card","choice_id":choice.choice_id,"option_index":maxi(0, pick)})
			taken.append({"kind":str(choice.get("kind")),"option_index":maxi(0, pick)})
		else:
			var targets: Array = choice.targets
			var target: int = targets[clampi(pick, 0, targets.size() - 1)]
			taken.append({"kind":"unit","choice_from":targets.map(_name_of),"chosen":_name_of(target)})
			error = game.apply_action(int(choice.owner), {"type":"choose_target","choice_id":choice.choice_id,"target_uid":target})
		if not error.is_empty(): return {"status":"error","detail":error}
	return {"status":"error","detail":"连续选择次数超过上限。"}

func _do_play(taken: Array) -> Dictionary:
	if int(game.state.active_player) != me: return _skip("当前不是我方回合。")
	if game._hand(me, HAND_ID).is_empty(): return _skip("手牌里没有这张卡。")
	var action := {"type":"play","hand_id":HAND_ID}
	var targets: Array = game.legal_targets(me, action)
	if targets.is_empty(): return _skip("无法打出：费用 %d，当前指挥点 %d，或没有合法位置。" % [game.play_cost(me, game._hand(me, HAND_ID).card), int(game.state.players[me].credits)])
	var target: int = targets[clampi(target_index, 0, targets.size() - 1)]
	action["target_uid"] = target
	var next_uid := int(game.state.next_uid)
	var outcome := _apply(me, action, taken)
	if outcome.status == "ok":
		if not game._unit(next_uid).is_empty() and int(game._unit(next_uid).owner) == me: tested_uid = next_uid
		outcome.detail = "可选目标：%s；选择：%s" % [", ".join(targets.map(_name_of)), _name_of(target)]
	return outcome

func _do_move(taken: Array) -> Dictionary:
	if tested_uid == 0: return _skip("这张卡没有在场单位。")
	if not game.can_move(tested_uid): return _skip("当前不能推进（未就绪、已行动，或前线被占）。")
	return _apply(me, {"type":"move","uid":tested_uid}, taken)

func _do_attack(taken: Array) -> Dictionary:
	if tested_uid == 0 or game._unit(tested_uid).is_empty(): return _skip("这张卡没有在场单位。")
	if int(game.state.active_player) != me: return _skip("当前不是我方回合。")
	var action := {"type":"attack","uid":tested_uid}
	var targets: Array = game.legal_targets(me, action)
	if targets.is_empty(): return _skip("没有可攻击的目标，或单位未就绪。")
	var target: int = targets[clampi(attack_target_index, 0, targets.size() - 1)]
	action["target_uid"] = target
	var outcome := _apply(me, action, taken)
	if outcome.status == "ok": outcome.detail = "可选目标：%s；攻击：%s" % [", ".join(targets.map(_name_of)), _name_of(target)]
	return outcome

func _do_activate(taken: Array) -> Dictionary:
	if tested_uid == 0 or game._unit(tested_uid).is_empty(): return _skip("这张卡没有在场单位。")
	var reason: String = game.activation_error(me, tested_uid, activate_index)
	if not reason.is_empty(): return _skip(reason)
	return _apply(me, {"type":"activate","uid":tested_uid,"ability_index":activate_index}, taken)

func _do_end_turn(taken: Array) -> Dictionary:
	var active := int(game.state.active_player)
	game.state.players[1 - active].credits = maxi(int(game.state.players[1 - active].credits), 0)
	return _apply(active, {"type":"end_turn"}, taken)

func _do_enemy_ai(taken: Array) -> Dictionary:
	if int(game.state.active_player) != enemy: return _skip("当前不是对手回合。")
	for _guard in MAX_STEPS:
		if int(game.state.active_player) != enemy or int(game.state.winner) != -1: return _done()
		var action: Dictionary = game.ai_action(enemy)
		var outcome := _apply(enemy, action, taken)
		if outcome.status != "ok": return outcome
	return {"status":"error","detail":"对手行动次数超过上限。"}

## Destroys the tested unit with a real enemy order so death triggers resolve through the normal action pipeline.
func _do_kill(taken: Array) -> Dictionary:
	if tested_uid == 0 or game._unit(tested_uid).is_empty(): return _skip("这张卡没有在场单位。")
	if int(game.state.active_player) == me:
		var passed := _apply(me, {"type":"end_turn"}, taken)
		if passed.status != "ok" or int(game.state.winner) != -1: return passed
	var order := _kill_order()
	if not order.ok: return {"status":"error","detail":"无法准备消灭指令：" + str(order.get("error", ""))}
	game.state.players[enemy].credits = RICH_CREDITS
	game.state.players[enemy].hand.append({"instance_id":KILL_HAND_ID,"card":order})
	var action := {"type":"play","hand_id":KILL_HAND_ID}
	if not tested_uid in game.legal_targets(enemy, action): return _skip("这张卡目前不能被选为目标。")
	action["target_uid"] = tested_uid
	return _apply(enemy, action, taken)
