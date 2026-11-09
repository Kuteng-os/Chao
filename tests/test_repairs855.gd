extends "res://tests/test_engine.gd"
var f: Dictionary
func _initialize() -> void:
 f=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/repairs855.json"))
 var parity: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/parity855.json"))
 for key in f:
  var c:=_compile(f[key]);if c.ok:_check(c.compiled_program_hash==parity[key].compiled_program_hash,"Node/native parity "+key)
 if failures:quit(1);return
 _bounce()
 _bounce_expiry()
 _full_hand()
 _history()
 _free_deployment()
 print("REPAIRS 855: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)

func _bounce() -> void:
 var g:=_game();var me:=_rich(g);g.state.players[me].hand.clear()
 var c:=_compile(f.unit)
 var a: Dictionary=g._new_unit(me,c);var b: Dictionary=g._new_unit(me,c.duplicate(true))
 g._receive_card(me,c.duplicate(true),"test")
 var twin: Dictionary=g.state.players[me].hand[0]
 # A permanent layer must survive; the one-shot price change must not become permanent.
 g._effect({"op":"modify_stats","target":"self","attack_delta":2,"health_delta":1,"duration":"match"},g._context(me,a.uid,a.card))
 _play(g,f.bounce,a.uid)
 _check(not g.state.has("pending_choice"),"bounce discount never requests a second hand selection")
 _check(g._unit(a.uid).is_empty() and not g._unit(b.uid).is_empty(),"only selected unit returns")
 var returned: Dictionary=g.state.players[me].hand.back()
 _check(g.play_cost(me,returned.card)==3,"returned exact instance costs two less")
 _check(g.play_cost(me,twin.card)==5,"identical named existing hand card is unaffected")
 _check(returned.card.get("match_layers",[]).size()==1,"permanent combat buff retained on return")
 var next_uid: int=g.state.next_uid;g.state.players[me].credits=3
 _check(g.apply_action(me,{"type":"play","hand_id":returned.instance_id}).is_empty(),"discounted next deployment is affordable")
 _check(g.state.players[me].credits==0 and not g._unit(next_uid).card.has("hand_cost_layers"),"deployment consumes discount once")
 g._reset_budget();g._leave_battlefield(g._unit(next_uid),true)
 _check(g.play_cost(me,g.state.players[me].hand.back().card)==5,"ordinary second bounce does not renew consumed discount")

func _bounce_expiry() -> void:
 var g:=_game();var me:=_rich(g);g.state.players[me].hand.clear()
 var a: Dictionary=g._new_unit(me,_compile(f.unit));_play(g,f.bounce,a.uid)
 var returned: Dictionary=g.state.players[me].hand.back()
 _check(g.apply_action(me,{"type":"end_turn"}).is_empty(),"end turn settles return discount")
 _check(g.play_cost(me,returned.card)==5,"temporary discount expires at end of granting turn")
 g._reset_budget();var cheap: Dictionary=f.unit.duplicate(true);cheap.cost=1
 a=g._new_unit(me,_compile(cheap));g._effect({"op":"return_to_hand","target":"self","cost_delta":-2,"duration":"hand"},g._context(me,a.uid,a.card))
 _check(g.play_cost(me,g.state.players[me].hand.back().card)==0,"discount cannot make negative cost")
 for duration in ["end_of_turn","hand"]:
  var bad: Dictionary=f.bounce.duplicate(true);bad.abilities[0].effects[0].cost_delta=0
  _check(not Runtime.compile_card(bad,Runtime.builtin_keywords()).ok,"zero discount is invalid")

func _full_hand() -> void:
 var g:=_game();var me:=_rich(g);g.state.players[me].hand.clear();var c:=_compile(f.unit)
 for i in 10:g._receive_card(me,c.duplicate(true),"test")
 var a: Dictionary=g._new_unit(me,c.duplicate(true));var ctx: Dictionary=g._context(me,a.uid,a.card)
 g._effect({"op":"return_to_hand","target":"self","cost_delta":-2,"duration":"end_of_turn"},ctx)
 _check(g.state.players[me].hand.size()==10 and g.state.players[me].burned.size()==1,"full hand burns returning card")
 _check(g.state.players[me].hand.all(func(e):return g.play_cost(me,e.card)==5),"burned card discount never attaches to another card")

func _query(g: RefCounted,owner: int,player: String="owner",filter: Dictionary={"sin":"gloom"}) -> bool:
 return g._premise_met({"test":"deployed_last_turn","player":player,"filter":filter},g._context(owner,-1,_compile(f.unit)))

func _history() -> void:
 var g:=_game();var me:=_rich(g);g.state.players[me].hand.clear()
 _check(not _query(g,me),"first turn has no previous own deployment")
 var id:=_play(g,f.unit);_check(not _query(g,me),"current-turn deployment does not satisfy last-turn premise")
 g._reset_budget();g._leave_battlefield(g._unit(id),false)
 _check(g.apply_action(me,{"type":"end_turn"}).is_empty(),"advance to opponent turn")
 _check(_query(g,1-me,"opponent"),"opponent can inspect most recent ended own turn")
 _check(g.apply_action(1-me,{"type":"end_turn"}).is_empty(),"advance to next own turn")
 _check(_query(g,me),"previous own turn counted even after source leaves")
 _check(_query(g,me,"owner",{"unit_classes":[f.unit.unit_class]}),"history supports unit class filter")
 _check(not _query(g,me,"owner",{"sin":"wrath"}),"wrong sin does not match")
 var enemy: Dictionary=g._new_unit(1-me,_compile(f.unit));enemy.row="front"
 _play(g,f.history,enemy.uid)
 _check(g._unit(enemy.uid).row=="support","reported on-play retreat executes after matching prior deployment")
 # Fresh round with no deployments must clear, never query the entire match history.
 g.state.players[me]["deployments_this_turn"]=[]
 g.apply_action(me,{"type":"end_turn"});g.apply_action(1-me,{"type":"end_turn"})
 _check(not _query(g,me),"an empty own turn replaces old history")

func _free_deployment() -> void:
 var g:=_game();var me:=_rich(g);var c:=_compile(f.unit)
 var a: Dictionary=g._new_unit(me,c.duplicate(true),"",true);g._initialize_summoned_unit(a)
 _check(g.state.players[me].get("deployments_this_turn",[]).is_empty(),"summoning is excluded from deployment history")
 a=g._new_unit(me,c.duplicate(true));g._initialize_deployed_unit(a)
 _check(g.state.players[me].deployments_this_turn.size()==1,"free deployment is recorded")
 a=g._new_unit(1-me,c.duplicate(true));g._initialize_deployed_unit(a)
 _check(g.state.players[1-me].get("deployments_this_turn",[]).is_empty(),"off-turn deployment does not count as an own-turn deployment")
