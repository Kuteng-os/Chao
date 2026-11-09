extends "res://tests/test_engine.gd"

var registered: Array

func _initialize() -> void:
	registered=JSON.parse_string(FileAccess.get_file_as_string("res://tests/copy836_cards.json"))
	_registered_deaths()
	_hatching_copy()
	_live_self_copy()
	print("COPY836: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _kill(g: RefCounted, seat: int, uid: int) -> void:
	var kill:=_base("测试消灭","order")
	kill.play_target={"side":"ally","row":"any"}
	kill.abilities=[{"trigger":"on_play","effects":[{"op":"destroy","target":"chosen"}]}]
	g.state.players[seat].credits=12
	g._receive_card(seat,_compile(kill),"test")
	var hand_id:String=g.state.players[seat].hand.back().instance_id
	_check(g.apply_action(seat,{"type":"play","hand_id":hand_id,"target_uid":uid}).is_empty(),"death resolved through authoritative action")

func _registered_deaths() -> void:
	for row in registered.slice(0,2):
		for empty in [false,true]:
			var g:=_game();var seat:=_rich(g);var c:=_compile(row.definition)
			g.state.players[seat].hand=[]
			if empty: g.state.players[seat].deck=[]
			var uid:int=g._new_unit(seat,c).uid
			var before:int=g.state.players[seat].deck.size()
			_kill(g,seat,uid)
			_check(g.state.players[seat].deck.size()==before+1,row.definition.name+" inserts exactly one actual card")
			for viewer in [0,1]:
				var view:Dictionary=g.view_for(viewer)
				_check(view.players[seat].deck_count==before+1,"both players receive updated deck count")
				_check(view.players[seat].deck.is_empty(),"deck contents remain concealed")
			if empty:
				var hp:int=g.state.players[seat].hp
				g._draw(seat)
				_check(g.state.players[seat].hand.back().card.definition.name==row.definition.name and g.state.players[seat].hp==hp,"copy refills empty deck and is drawn without fatigue")
			print("DEATH_COPY_COUNTS ",row.definition.name," ",before," -> ",g.state.players[seat].deck.size())

func _hatching_copy() -> void:
	for row in registered.slice(0,2):
		var g:=_game();var seat:=_rich(g);var c:=_compile(row.definition)
		g.state.players[seat].hand=[];g.state.players[seat].deck=[]
		g._receive_card(seat,c.duplicate(true),"test")
		var uid:int=g._new_unit(seat,c).uid
		_play(g,registered[2].definition)
		_check(g.state.pending_choice.kind=="discard","hatching asks for actual hand discard")
		_check(g.apply_action(seat,{"type":"choose_card","choice_id":g.state.pending_choice.choice_id,"option_index":0}).is_empty(),"hatching confirmed")
		var enhanced:Dictionary=g._unit(uid)
		_check(enhanced.attack==int(c.definition.attack)+2,"registered hatching applies permanent buff")
		# Temporary +1/+1 must not survive death or be copied.
		g._effect({"op":"modify_stats","target":"self","attack_delta":1,"health_delta":1,"duration":"battle"},g._context(seat,uid,enhanced.card))
		_kill(g,seat,uid)
		_check(g.state.players[seat].deck.size()==1,"enhanced death inserts exactly one copy")
		var copied:Dictionary=g.state.players[seat].deck[0]
		var displayed:Dictionary=Runtime.display_definition(copied)
		_check(displayed.attack==int(c.definition.attack)+2 and displayed.health==int(c.definition.health)+2,"copy retains permanent stats without temporary buff")
		_check(displayed.operation_cost==maxi(0,int(c.definition.operation_cost)-1),"copy retains permanent operation reduction")
		_check(copied.get("match_abilities",[]).size()==1,"copy retains hatching deployment draw")
		_check(copied.definition==c.definition and copied.definition_hash==c.definition_hash,"copy preserves registered version and hash")
		g._draw(seat)
		g.state.players[seat].deck=[_compile(_base("复制后抽到的牌"))]
		g.state.players[seat].credits=12
		_check(g.apply_action(seat,{"type":"play","hand_id":g.state.players[seat].hand.back().instance_id}).is_empty(),"copied unit can deploy")
		_check(g.state.players[seat].deck.is_empty() and g.state.players[seat].hand.back().card.definition.name=="复制后抽到的牌","inherited deployment ability draws exactly once")
		var next:Dictionary=g.state.units.back()
		_check(next.attack==int(c.definition.attack)+2 and next.hp==int(c.definition.health)+2,"copied unit deploys fully healed with enhancement")
		_kill(g,seat,next.uid)
		_check(g.state.players[seat].deck.size()==1 and g.state.players[seat].deck[0].get("match_abilities",[]).size()==1,"second generation preserves enhancement once without duplication")

func _live_self_copy() -> void:
	var g:=_game();var seat:=_rich(g)
	var card:=_base("先强化再复制")
	card.abilities=[{"trigger":"on_play","effects":[{"op":"modify_stats","target":"self","attack_delta":2,"health_delta":2,"duration":"match"},{"op":"transfer_card","source":"self","destination":"hand","mode":"copy","selection":"top","amount":1}]}]
	g.state.players[seat].hand=[]
	_play(g,card)
	_check(Runtime.display_definition(g.state.players[seat].hand.back().card).attack==5,"self copy reads latest permanent state within same ability group")
