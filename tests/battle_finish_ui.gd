extends Node
var checks:=0
var failures:=0
var returned:=0

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(message)

func _ready() -> void:
	if OS.has_feature("mobile"): preload("res://scripts/ui/screen_layout.gd").configure(get_window(),true)
	_run.call_deferred()

func _settle(view: Control) -> void:
	var deadline:=Time.get_ticks_msec()+6000
	while view.input_locked and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	await get_tree().process_frame
	check(not view.input_locked,"terminal animation completes")

func _run() -> void:
	var base: Dictionary={"schema_version":"1.0.0","ruleset_version":"frontline-1","name":"测试指令","kind":"order","unit_class":null,"cost":1,"operation_cost":0,"attack":0,"health":0,"keywords":[],"play_target":null,"abilities":[{"trigger":"on_play","effects":[{"op":"damage","target":"enemy_hq","amount":2}]}],"tokens":[],"flavor_text":"","appearance":{"emblem":"order"}}
	var deck: Array=[]
	for i in 10:
		base.name="测试指令"+str(i)
		var card:=CardRuntime.compile_card(base,[])
		check(card.ok,"order compiles")
		for n in 4: deck.append(card)
	for winner in [0,1]:
		var game:=BattleEngine.new()
		check(game.setup(deck,deck,56).is_empty(),"battle initializes")
		game.state.active_player=winner
		game.state.players[winner].credits=12
		game.state.players[1-winner].hp=2
		var controller: Node=load("res://scripts/network/match_controller.gd").new()
		add_child(controller)
		controller.set_process(false)
		controller.mode="solo";controller.local_player=winner;controller.connected=true;controller._engine=game
		controller._refresh_views()
		var view: Control=load("res://scripts/ui/battle_view.gd").new()
		view.state=game.view_for(0);view.connected=true;view.solo=true
		view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(view)
		view.finish_requested.connect(func(): controller.leave_game();returned+=1)
		controller.state_changed.connect(func():
			if not controller.state.is_empty(): view.present_snapshot(game.view_for(0),true,"",-1))
		await get_tree().process_frame
		var hand_id: String=game.state.players[winner].hand[0].instance_id
		if winner==0:
			view.selected_hand=hand_id
			view._refresh_rules()
			view._process(0)
			check(not view.aim.active,"untargeted order selection has no arrow")
			view.drag_data={"type":"play","hand_id":hand_id}
			view._process(0)
			check(not view.aim.active,"untargeted order drag has no arrow")
			var drop: Vector2=view.board.position+view._combat_rect(Rect2(210,110,1020,649)).get_center()*view.board.scale
			check(view._drop_action(drop,view.drag_data).get("type")=="play","untargeted order still playable by dragging onto battle")
			var hand_face: Control=view.visual_faces["h:"+hand_id]
			check(float(hand_face.get_meta("layout_rect").position.y)>=755,"hand below support units")
		# Same synchronous state_changed + caller refresh sequence as main._act.
		controller.submit_action({"type":"play","hand_id":hand_id})
		check(game.state.winner==winner,"practice authority resolves winner")
		view.present_snapshot(game.view_for(0),true,"",-1)
		check(not view.queued_snapshot.is_empty(),"duplicate final snapshot queued during animation")
		await _settle(view)
		var panels: Array=view.board.get_children().filter(func(node):return node is PanelContainer and node.z_index==100)
		check(panels.size()==1,"exactly one result panel after duplicate final snapshot")
		if panels.size()==1:
			var buttons:Array=panels[0].find_children("*","Button",true,false)
			check(buttons.size()==1,"result has one return action")
			var button: Button=buttons[0]
			check(panels[0].get_child(0).get_child(0).text==("胜利" if winner==0 else "失败"),"correct outcome displayed")
			view.present_snapshot(game.view_for(0),true,"",-1)
			check(view.board.get_children().filter(func(n):return n is PanelContainer and n.z_index==100).size()==1,"repeated final refresh never duplicates panel")
			if DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("user://battle-result-%d.png"%winner)
			button.pressed.emit()
			check(controller.mode=="menu" and controller.state.is_empty(),"return button clears practice match")
		view.queue_free();controller.queue_free()
		await get_tree().process_frame
	check(returned==2,"victory and defeat can both return")
	print("BATTLE FINISH UI: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
