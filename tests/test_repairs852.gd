extends "res://tests/test_engine.gd"
var fixture: Dictionary

func _configured(spec: Dictionary) -> Dictionary:
	var compiled := Runtime.compile_card(spec,Runtime.builtin_keywords()+[fixture.keyword])
	_check(compiled.ok,"configured compile: "+compiled.get("error",""))
	return compiled

func _settle(g: RefCounted) -> void:
	g._checkpoint()
	g._drain_deaths()
	_check(g._fault.is_empty(),"condition resolution stays bounded: "+g._fault)

func _initialize() -> void:
	fixture=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/repairs852.json"))
	var c:=_configured(fixture.card)
	if not c.ok: quit(1);return
	_check(c.compiled_program_hash==fixture.hash,"native/server compiled hash parity")
	_check("满足条件时" in Runtime.rules_text(c),"localized conditional rules")
	_check(Runtime.display_definition(c)._printed.abilities.size()==1,"card face includes per-card effects")
	_check(_configured(fixture.parent).ok,"generated cards support independently configured keywords")
	var bad: Dictionary=fixture.card.duplicate(true)
	bad.keywords[0].abilities=[]
	_check(not Runtime.compile_card(bad,[fixture.keyword]).ok,"reject empty per-card configuration")
	bad=fixture.card.duplicate(true);bad.keywords[0].abilities[0].erase("premise")
	_check(not Runtime.compile_card(bad,[fixture.keyword]).ok,"reject missing conditional premise")
	var g:=_game();var me:=_rich(g)
	g.state.players[me].hand=[]
	var a: Dictionary=g._new_unit(me,c)
	_settle(g)
	_check(a.attack==3,"does not release before prerequisite")
	var enemy: Dictionary=g._new_unit(1-me,_compile(_base()))
	var count: int=g.state.players[me].hand.size()
	_settle(g)
	_check(a.attack==5 and a.max_hp==5,"release changes stats when prerequisite becomes true")
	_check(g.state.players[me].hand.size()==count+1,"release instant effect draws once")
	_settle(g);_settle(g)
	_check(a.attack==5 and g.state.players[me].hand.size()==count+1,"no repeated release while prerequisite remains true")
	g._leave_battlefield(enemy,false);_settle(g)
	_check(a.attack==5,"losing prerequisite does not remove acquired enhancement")
	enemy=g._new_unit(1-me,_compile(_base()));_settle(g)
	_check(a.attack==5,"false-to-true again does not retrigger in same presence")
	g._leave_battlefield(a,true);_settle(g)
	var returned: Dictionary=g.state.players[me].hand.back().card
	_check(returned.definition.attack==3 and returned.get("match_layers",[]).is_empty(),"return does not retain temporary liberation enhancement")
	a=g._new_unit(me,returned)
	_check(a.attack==3,"replayed body starts from original stats")
	_settle(g)
	_check(a.attack==5,"new presence can release once again without stacking old buff")
	var b: Dictionary=g._new_unit(me,c)
	b.suppressed=true;_settle(g)
	_check(b.attack==3,"suppression prevents conditional release")
	b.suppressed=false;_settle(g)
	_check(b.attack==5,"unsuppressed fresh condition can release")
	var dead: Dictionary=g._new_unit(me,c);dead.destroyed=true
	count=g.state.players[me].hand.size();_settle(g)
	_check(g._unit(dead.uid).is_empty() and g.state.players[me].hand.size()==count,"dead unit cannot release")
	# Target choice pauses and replays the entire action; the first stat effect must not double.
	g=_game();me=_rich(g);g.state.players[me].hand=[]
	enemy=g._new_unit(1-me,_compile(_base()))
	var choice: Dictionary=fixture.card.duplicate(true)
	choice.keywords[0].abilities[0]["target"]={"side":"enemy","row":"any","timing":"trigger"}
	choice.keywords[0].abilities[0].effects.append({"op":"damage","target":"chosen","amount":1})
	g.state.players[me].hand.append({"instance_id":"release-choice","card":_configured(choice)})
	_check(g.apply_action(me,{"type":"play","hand_id":"release-choice","target_uid":-1}).is_empty(),"condition action starts")
	_check(g.state.has("pending_choice"),"condition requests visible target selection")
	if g.state.has("pending_choice"):
		var pending: Dictionary=g.state.pending_choice
		_check(g.apply_action(me,{"type":"choose_target","choice_id":pending.choice_id,"target_uid":enemy.uid}).is_empty(),"condition target choice completes")
		var bodies: Array=g.state.units.filter(func(u):return u.owner==me)
		_check(bodies.size()==1 and bodies[0].attack==5,"transactional replay applies enhancement once")
		_check(g._unit(enemy.uid).hp==3,"chosen immediate effect resolves")
	print("REPAIRS 852: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
