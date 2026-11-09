extends SceneTree
const Runtime = preload("res://scripts/core/card_runtime.gd")
const Rules = preload("res://scripts/core/battle_engine.gd")
const Controller = preload("res://scripts/network/match_controller.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func card(name: String, guard: bool = false, kind: String = "tank") -> Dictionary:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	source.name = name
	source.cost = 1
	source.operation_cost = 0
	source.attack = 1
	source.health = 9
	source.unit_class = kind
	source.appearance.emblem = kind
	source.keywords = [{"id":"core.blitz","version":1,"params":{}}]
	if guard: source.keywords.append({"id":"core.guard","version":1,"params":{}})
	var compiled := Runtime.compile_card(source,Runtime.builtin_keywords())
	check(compiled.ok,"Placement fixture compiles: "+compiled.get("error",""))
	return compiled

func game() -> RefCounted:
	var deck: Array = []
	for i in 10:
		var c := card("部署测试"+str(i))
		for j in 4: deck.append(c)
	var engine := Rules.new()
	check(engine.setup(deck,deck,77).is_empty(),"Placement fixture starts")
	engine.state.active_player = 0
	engine.state.players[0].credits = 12
	return engine

func play(engine: RefCounted, position: int) -> int:
	var entry: Dictionary = engine.state.players[0].hand[0]
	var uid: int = engine.state.next_uid
	check(engine.apply_action(0,{"type":"play","hand_id":entry.instance_id,"position":position}).is_empty(),"Play into requested slot")
	return uid

func _initialize() -> void:
	var engine := game()
	var a := play(engine,0)
	var b := play(engine,2)
	var c := play(engine,1)
	var d := play(engine,4)
	check(engine.line_order(0,"support")==[a,c,-1,b,d],"Inserts on either side of HQ and between existing units")
	check(engine.apply_action(0,{"type":"move","uid":b,"position":0}).is_empty(),"Move first unit to frontline")
	check(engine.line_order(0,"support")==[a,c,-1,d],"Moving closes support gap and retains HQ order")
	check(engine.apply_action(0,{"type":"move","uid":a,"position":0}).is_empty(),"Move before existing front unit")
	check(engine.apply_action(0,{"type":"move","uid":d,"position":1}).is_empty(),"Move between front units")
	check(engine.line_order(0,"front")==[a,d,b],"Front insertion order is independent of UID")
	var before: String = Runtime.canonical(engine.state)
	for bad in [-1,5,true,"1",1.5]:
		check(not engine.apply_action(0,{"type":"move","uid":c,"position":bad}).is_empty(),"Invalid slot rejected")
		check(Runtime.canonical(engine.state)==before,"Rejected slot never changes state or spends credits")
	var view: Dictionary = engine.view_for(0)
	var replica := Rules.new()
	replica.state = view
	check(replica.line_order(0,"front")==[a,d,b],"Public snapshot reconstructs exact front order")
	replica.state = engine.view_for(1)
	check(replica.line_order(0,"support")==[c,-1],"Both players see identical support order")
	# Exercise every legal slot through actual play actions, not only helper calls.
	for existing in 4:
		for slot in existing+2:
			var trial := game()
			for i in existing: play(trial,i)
			var expected: Array = trial.line_order(0,"support")
			var uid := play(trial,slot)
			expected.insert(slot,uid)
			check(trial.line_order(0,"support")==expected,"All support insertion gaps preserve existing order")
	# Guard protects only immediate neighbors, including HQ. Guard never chains.
	engine = game()
	var guard: Dictionary = engine._new_unit(1,card("守护",true),"",false,0)
	var left: Dictionary = engine._new_unit(1,card("左侧"),"",false,0)
	var far: Dictionary = engine._new_unit(1,card("远端"),"",false,0)
	var right: Dictionary = engine._new_unit(1,card("右侧"),"",false,4)
	check(engine.line_order(1,"support")==[far.uid,left.uid,guard.uid,-1,right.uid],"Guard adjacency fixture")
	for kind in ["tank","infantry","fighter"]:
		check(not engine._guard_allows(1,"support",left.uid,kind),"Immediate left protected")
		check(not engine._guard_allows(1,"support",-1,kind),"Immediate HQ protected")
		check(engine._guard_allows(1,"support",far.uid,kind),"Distant target is not protected")
		check(engine._guard_allows(1,"support",right.uid,kind),"Guard does not project through HQ")
		check(engine._guard_allows(1,"support",guard.uid,kind),"Guard itself can be attacked")
	for kind in ["artillery","bomber"]:
		check(engine._guard_allows(1,"support",left.uid,kind) and engine._guard_allows(1,"support",-1,kind),"Artillery and bombers bypass Guard")
	var attacker: Dictionary = engine._new_unit(0,card("战斗机",false,"fighter"))
	var legal: Array = engine.legal_targets(0,{"type":"attack","uid":attacker.uid})
	check(left.uid not in legal and -1 not in legal and far.uid in legal and right.uid in legal,"Real attack legality applies adjacency")
	left.damage_taken = left.max_hp
	engine._checkpoint()
	check(engine.line_order(1,"support")==[far.uid,guard.uid,-1,right.uid],"Death closes gap preserving HQ and unit order")
	check(not engine._guard_allows(1,"support",far.uid,"fighter"),"New adjacent neighbor becomes protected after death")
	guard.damage_taken = guard.max_hp
	engine._checkpoint()
	check(engine._guard_allows(1,"support",far.uid,"fighter") and engine._guard_allows(1,"support",-1,"fighter"),"Guard death immediately releases protection")
	var network := Controller.new()
	for action in [{"type":"play","hand_id":"h1","position":4},{"type":"move","uid":1,"position":0}]:
		check(network._normalize_action(action)==action,"LAN preserves selected position")
	for bad in [-1,5,true,"1",1.5]:
		check(network._normalize_action({"type":"play","hand_id":"h1","position":bad}).is_empty(),"LAN rejects malformed positions")
	check(network._normalize_action({"type":"attack","uid":1,"target_uid":-1,"position":0}).is_empty(),"Attack cannot smuggle a position change")
	network.free()
	print("PLACEMENT TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
