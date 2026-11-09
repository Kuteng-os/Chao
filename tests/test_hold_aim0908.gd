extends "res://tests/test_touch_drag.gd"
var view:Control
var actions:Array=[]
var latched:=0

func _run()->void:
	root.size=Vector2i(1440,900)
	var spec:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	spec.name="aim";spec.unit_class="tank";spec.keywords=[];spec.abilities=[];spec.cost=1;spec.operation_cost=0;spec.attack=2;spec.health=9
	var deck:Array=[]
	for i in 10:
		var definition:=spec.duplicate(true);definition.name+=str(i)
		var card:=CardRuntime.compile_card(definition,[])
		for copy in 4:deck.append(card)
	var game:=BattleEngine.new();check(game.setup(deck,deck,56).is_empty(),"Setup")
	game.state.active_player=0;game.state.players[0].credits=10
	var attacker:Dictionary=game._new_unit(0,deck[0]);attacker.row="front";attacker.born_turn=-1
	var mover:Dictionary=game._new_unit(0,deck[0]);mover.born_turn=-1
	var enemy:Dictionary=game._new_unit(1,deck[4])
	view=load("res://scripts/ui/battle_view.gd").new()
	view.state=game.view_for(0);view.connected=true;view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(view)
	view.action_requested.connect(func(action):actions.append(action))
	view.hand_clicked.connect(func(_card):latched+=1)
	await frames(4)
	var face:CardFace=view.visual_faces["u:%d"%attacker.uid]
	var from:Vector2=face.get_global_transform()*face.card_body_rect().get_center()
	var target:Vector2=view.visual_faces["u:%d"%enemy.uid].get_global_rect().get_center()
	for mobile in [false,true]:
		view.touch_mode=mobile;face.touch_gate.touch_mode=mobile
		await motion(from);await press(true);await press(false);await motion(target)
		check(view.selected_unit==-1 and actions.is_empty() and not view.aim.active,"Click then hover never arms an attack")
		await press(true);await press(false)
		check(actions.is_empty(),"Second target click cannot attack")
		view._hide_inspector()
		await motion(from);await press(true);await motion(from+Vector2(25,-25));await motion(target)
		check(root.gui_is_dragging() and view.aim.active and view.aim.valid,"Held unit drag displays a valid attack arrow")
		check(actions.is_empty(),"Aiming does not act before release")
		check(view.aim.origin.is_equal_approx(face.card_top_in_parent()),"Arrow starts at the printed card top")
		check(not view.choice_overlay.visible,"Ordinary attacks keep the battlefield undimmed")
		await press(false)
		check(actions.size()==1 and actions[0].type=="attack" and actions[0].target_uid==enemy.uid,"Release submits one attack")
		check(not view.aim.active and view.drag_data.is_empty(),"Arrow clears on release")
		actions.clear()
		for cancellation in ["return","invalid","right","escape","focus"]:
			await motion(from);await press(true);await motion(from+Vector2(25,-25));await motion(target)
			if cancellation=="return":await motion(from)
			elif cancellation=="invalid":await motion(Vector2(30,350))
			elif cancellation=="right":
				var right:=InputEventMouseButton.new();right.button_index=MOUSE_BUTTON_RIGHT;right.pressed=true;right.position=mouse_position
				Input.parse_input_event(right);await frames(2)
				right=right.duplicate();right.pressed=false;Input.parse_input_event(right)
			elif cancellation=="escape":
				var key:=InputEventKey.new();key.keycode=KEY_ESCAPE;key.pressed=true;Input.parse_input_event(key);await frames(2)
				key=key.duplicate();key.pressed=false;Input.parse_input_event(key)
			else:view._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			await press(false)
			check(actions.is_empty() and not view.aim.active and not root.gui_is_dragging(),"Canceled aim (%s) cannot act later"%cancellation)
			await motion(target);await press(true);await press(false)
			check(actions.is_empty(),"Canceled aim never becomes click-to-attack")
		var mover_face:CardFace=view.visual_faces["u:%d"%mover.uid];mover_face.touch_gate.touch_mode=mobile
		var move_from:Vector2=mover_face.get_global_transform()*mover_face.card_body_rect().get_center()
		await motion(move_from);await press(true);await motion(move_from+Vector2(25,-25));await motion(Vector2(1050,440))
		check(view.aim.active and view.aim.valid and not view.aim.attack,"Held move shows the frontline insertion")
		await press(false)
		check(actions.size()==1 and actions[0].type=="move" and actions[0].uid==mover.uid,"Frontline move submits on release")
		actions.clear()
		var hand:CardFace=view.visual_faces["h:"+str(view.state.players[0].hand[-1].instance_id)]
		hand.touch_gate.touch_mode=mobile
		var hand_point:Vector2=hand.get_global_transform()*Vector2(110,35)
		await motion(hand_point);await press(true);await press(false)
		check(latched==0 and view.selected_hand.is_empty() and not view.aim.active,"Clicking a hand card only inspects it")
		await motion(Vector2(1050,620));await press(true);await press(false)
		check(actions.is_empty(),"Clicking the board afterward cannot deploy")
		await motion(hand_point);await press(true);await motion(hand_point+Vector2(0,-45));await motion(Vector2(1050,620))
		check(root.gui_is_dragging() and not view.aim.active and view.aim.insertion.has_area(),"Ordinary deployment pulls the card out without an attack arrow")
		await press(false)
		check(actions.size()==1 and actions[0].type=="play","Held hand deployment submits on release")
		actions.clear();await create_timer(0.3).timeout
	# Stale controller selection cannot revive an arrow without a held gesture.
	view.present_snapshot(game.view_for(0),true,"",attacker.uid);await frames(2)
	check(not view.aim.active,"A legacy selection alone cannot display the aim arrow")
	view.queue_free();await frames(3)
	print("HOLD_AIM0908: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
