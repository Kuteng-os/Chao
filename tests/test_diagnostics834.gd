extends "res://tests/test_engine.gd"
var records: Array
const RABBIT := "第4集团军“兔子”"
func _initialize() -> void:
	var path := OS.get_environment("CHAO_834_FIXTURE")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path if not path.is_empty() else "res://tests/fixtures834.json"))
	records=data.cards
	for row in records:
		var c:=_compile(row.definition)
		_check(c.definition_hash==row.definition_hash and c.compiled_program_hash==row.compiled_program_hash,"cross runtime compile "+row.definition.name)
		_check(not "[object" in Runtime.rules_text(c),"readable dynamic rules")
	_repeated()
	_discount()
	_replay()
	_invalid()
	print("DIAGNOSTICS 834: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _repeated() -> void:
	for n in [0,1,3]:
		var g:=_game();var p:=_rich(g)
		for i in n:g._new_unit(p,_compile(_base(RABBIT)))
		g._new_unit(1-p,_compile(_base(RABBIT)))
		var u:=_base("重甲靶");u.health=10
		var armor:Dictionary=g._new_unit(1-p,_compile(u))
		g._effect({"op":"modify_stacks","target":"self","stack":"heavy_armor","amount":1,"duration":"battle"},g._context(1-p,armor.uid,armor.card))
		var raw:Dictionary=g._new_unit(1-p,_compile(u))
		_play(g,records[0].definition)
		_check(g._unit(armor.uid).hp==10-n,"effect damage retains existing armor semantics")
		_check(g._unit(raw.uid).hp==10-n,"each packet damages ordinary unit")
		_check(g.state.players[1-p].hp==20-n,"HQ participates only via explicit effect")
	# The count is snapshotted even if a counted enemy dies in the first pass.
	var g:=_game();var p:=_rich(g)
	var rabbit:=_base(RABBIT);rabbit.health=1
	g._new_unit(1-p,_compile(rabbit));g._new_unit(1-p,_compile(rabbit))
	var c:Dictionary=records[0].definition.duplicate(true);c.abilities[0].repeat.count_units.side="enemy"
	_play(g,c)
	_check(g.state.units.is_empty() and g.state.players[1-p].hp==18,"locked count survives counted unit deaths")
	# Damage-event triggers settle between passes, gaining armor blocks the second hit.
	g=_game();p=_rich(g)
	var defender:=_base("受伤重甲");defender.abilities=[{"trigger":"on_damaged","effects":[{"op":"modify_incoming_damage","target":"self","damage_kind":"effect","amount":-1,"duration":"battle"}]}]
	var target:Dictionary=g._new_unit(1-p,_compile(defender))
	c=records[0].definition.duplicate(true);c.abilities[0].repeat=2
	_play(g,c)
	_check(g._unit(target.uid).hp==3,"damage triggers resolve between passes")

func _discount() -> void:
	var g:=_game();var p:=_rich(g);var c:=_compile(records[1].definition)
	g.state.players[p].hand=[{"instance_id":"discount","card":c}]
	var enemy:Dictionary=g._new_unit(1-p,_compile(_base("目标")))
	g.state.players[p].credits=3
	_check(g.legal_targets(p,{"type":"play","hand_id":"discount"}).is_empty(),"base cost not affordable")
	for i in 2:g._new_unit(p,_compile(_base(RABBIT)))
	var before:=Runtime.sha(g.state);var budget:=Runtime.sha(g._budget)
	for i in 30:
		_check(g.play_cost(p,c)==3 and enemy.uid in g.legal_targets(p,{"type":"play","hand_id":"discount"}),"discounted legality")
	_check(before==Runtime.sha(g.state) and budget==Runtime.sha(g._budget),"cost previews cannot mutate state or budget")
	_check(g.apply_action(p,{"type":"play","hand_id":"discount","target_uid":enemy.uid}).is_empty(),"discounted play")
	_check(g.state.players[p].credits==0 and g._unit(enemy.uid).is_empty(),"correct fee and full damage")
	_check(c.source.cost==7 and c.definition.cost==7,"printed cost unchanged")
	for i in 2:g._new_unit(p,_compile(_base(RABBIT)))
	_check(g.play_cost(p,c)==0,"cost floor zero")
	g._leave_battlefield(g.state.units[0],false);g._leave_battlefield(g.state.units[0],false)
	_check(g.play_cost(p,c)==3,"cost rises when support leaves")
	# Counter costs are evaluated again at trigger; arming remains hidden/free.
	var counter:=_base("减费反制","counter");counter.cost=7;counter["counter_trigger"]="enemy_order_played";counter["cost_reduction"]=c.definition.cost_reduction
	counter.abilities=[{"trigger":"on_reveal","effects":[{"op":"damage","target":"enemy_hq","amount":1}]}]
	_play(g,counter);g.state.players[p].credits=3
	var hp:int=g.state.players[1-p].hp
	g.apply_action(p,{"type":"end_turn"});_play(g,_base("触发指令","order").merged({"abilities":[{"trigger":"on_play","effects":[{"op":"gain_kredits","amount":1}]}]},true))
	_check(g.state.players[p].credits==0 and g.state.players[1-p].hp==hp-1,"counter pays current reduced cost at trigger")

func _replay() -> void:
	var g:=_game();var p:=_rich(g)
	var c:=_base("重复抉择","order");c.cost=2;c.abilities=[{"trigger":"on_play","repeat":2,"effects":[{"op":"choose_effect","options":[{"label":"抽牌","effects":[{"op":"draw","player":"owner","amount":1}]},{"label":"伤害","effects":[{"op":"damage","target":"enemy_hq","amount":1}]}]}]}]
	_play(g,c)
	for i in 2:
		_check(g.state.has("pending_choice"),"each repetition offers choice")
		var restored:=EngineClass.new();restored.state=g.state.duplicate(true)
		var action:Dictionary={"type":"choose_card","choice_id":g.state.pending_choice.choice_id,"option_index":1}
		_check(g.apply_action(p,action).is_empty() and restored.apply_action(p,action).is_empty(),"repeat choice resumes")
		_check(Runtime.sha(g.state)==Runtime.sha(restored.state),"repeat deterministic after restore")
	_check(g.state.players[p].credits==10 and g.state.players[1-p].hp==18,"repeat pays once, executes twice")

func _invalid() -> void:
	for r in [0,17,{"count_units":{"side":"ally","card_name":" "}}]:
		var c:Dictionary=records[0].definition.duplicate(true);c.abilities[0].repeat=r
		_check(not Runtime.compile_card(c,Runtime.builtin_keywords()).ok,"invalid repetition rejected")
	var c:Dictionary=records[1].definition.duplicate(true);c.cost_reduction.amount=-1
	_check(not Runtime.compile_card(c,Runtime.builtin_keywords()).ok,"negative reduction rejected")
