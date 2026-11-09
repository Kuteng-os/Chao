extends "res://tests/test_touch_drag.gd"
var view:Control
var actions:Array=[]
var opened:=0
var tapped:=0

func _run()->void:
	root.size=Vector2i(1440,900)
	var spec:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	spec.keywords=[];spec.abilities=[];spec.cost=2;spec.operation_cost=0
	spec.tokens=[{"token_id":"child","name":"衍生单位","unit_class":"infantry","attack":1,"health":2,"keywords":[]}]
	var deck:Array=[]
	for i in 10:
		var copy:=spec.duplicate(true);copy.name="长按测试"+str(i)
		var card:=CardRuntime.compile_card(copy,[])
		for j in 4:deck.append(card)
	var game:=BattleEngine.new();check(game.setup(deck,deck,5).is_empty(),"Setup")
	game.state.active_player=0;game.state.players[0].credits=0
	var enemy:Dictionary=game._new_unit(1,deck[0])
	view=load("res://scripts/ui/battle_view.gd").new();view.state=game.view_for(0);view.connected=true;view.touch_mode=true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(view);view.action_requested.connect(func(a):actions.append(a));await frames(5)
	var hand_id:String=game.state.players[0].hand[-1].instance_id
	var face:CardFace=view.visual_faces["h:"+hand_id];face.touch_gate.touch_mode=true
	var from:Vector2=face.get_global_transform()*Vector2(110,30)
	await motion(from);await press(true);await motion(from+Vector2(7,-5));await create_timer(0.55).timeout
	check(is_instance_valid(view.inspector) and view.inspector_pinned,"Stationary finger with small jitter opens hand details even without cost")
	check(not root.gui_is_dragging() and not view.aim.active,"Inspection neither pulls card nor arms arrow")
	await press(false);await frames()
	check(is_instance_valid(view.inspector) and actions.is_empty(),"Finger release keeps details open and sends no play")
	var derived:=find_button(view.inspector_panel,"查看衍生卡")
	check(derived!=null,"Mobile details expose derived cards")
	if derived!=null:derived.pressed.emit()
	await frames();check(is_instance_valid(view.related_panel),"Derived viewer opens from long-press details")
	view._hide_inspector();await frames()
	var enemy_face:CardFace=view.visual_faces["u:%d"%enemy.uid];enemy_face.touch_gate.touch_mode=true
	var enemy_point:=enemy_face.get_global_rect().get_center()
	await motion(enemy_point);await press(true);await create_timer(0.55).timeout
	check(is_instance_valid(view.inspector),"Enemy unit inspection does not depend on ownership or legal drag")
	await press(false);view._hide_inspector();await frames()
	await motion(from);await press(true);face._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT);await create_timer(0.5).timeout;await press(false)
	check(not is_instance_valid(view.inspector) and actions.is_empty(),"Focus loss cancels pending inspection without a later click")
	await motion(from);await press(true)
	game.state.players[0].credits=4;view.present_snapshot(game.view_for(0),true,"",-1)
	for i in 3:view.presentation.finish();await frames()
	await create_timer(0.5).timeout;await press(false)
	check(not is_instance_valid(view.inspector),"Changed snapshot invalidates a pending hold")
	face=view.visual_faces["h:"+hand_id]
	await motion(from);await press(true);await motion(from+Vector2(0,-50));await motion(Vector2(1050,610))
	check(root.gui_is_dragging() and not is_instance_valid(view.inspector),"Battle drag starts before hold timeout")
	await press(false);check(actions.size()==1 and actions[0].type=="play","Normal immediate drag still plays exactly once")
	actions.clear();await create_timer(0.3).timeout
	await motion(from);await press(true);await create_timer(0.55).timeout
	check(is_instance_valid(view.inspector),"Long press can precede a deliberate drag")
	await motion(from+Vector2(0,-50));await motion(Vector2(1050,610))
	check(root.gui_is_dragging() and not is_instance_valid(view.inspector),"Dragging after inspection closes details")
	await press(false);check(actions.size()==1,"Inspect then drag acts exactly once")
	actions.clear()
	await finger(from,true,0)
	var drag:=InputEventScreenDrag.new();drag.index=0;drag.position=Vector2(1050,610);drag.relative=drag.position-from
	Input.parse_input_event(drag);await frames(3)
	check(root.gui_is_dragging(),"Raw touch can immediately drag a playable card")
	await finger(drag.position,false,0,true);await frames(3)
	check(actions.is_empty() and not root.gui_is_dragging(),"System-canceled drag cannot play a card")
	view.queue_free();await frames(4)
	# Raw touch events cover a device without synthesized mouse events as well.
	var raw:=Face.new();raw.spec=spec;raw.position=Vector2(70,70);raw.size=Face.full_size(200);raw.touch_gate.hold_required=false
	raw.touch_gate.inspect_requested=func():opened+=1
	raw.pressed.connect(func():if not raw.ignore_touch_click():tapped+=1,CONNECT_DEFERRED)
	root.add_child(raw);await frames()
	var point:=raw.get_global_rect().get_center()
	await finger(point,true,0);await create_timer(0.55).timeout;await finger(point,false,0)
	check(opened==1 and tapped==0,"Raw finger hold opens once and does not tap")
	await finger(point,true,0);await finger(point+Vector2(10,0),true,1);await create_timer(0.6).timeout
	await finger(point+Vector2(10,0),false,1);await finger(point,false,0)
	check(opened==1 and tapped==0,"Multiple fingers cancel without delayed inspection or tap")
	await finger(point,true,0);await finger(point,false,0,true);await create_timer(0.5).timeout
	check(opened==1 and tapped==0,"Canceled touch cannot fire later: opened=%d tapped=%d"%[opened,tapped])
	raw.queue_free();await frames()
	print("TOUCH_INSPECT902: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func finger(point:Vector2,down:bool,index:int,canceled:=false)->void:
	var event:=InputEventScreenTouch.new();event.position=point;event.pressed=down;event.index=index;event.canceled=canceled
	Input.parse_input_event(event);await frames(2)

func find_button(node:Node,title:String)->Button:
	if not is_instance_valid(node):return null
	for child in node.get_children():
		if child is Button and child.text==title:return child
		var found:=find_button(child,title)
		if found!=null:return found
	return null
