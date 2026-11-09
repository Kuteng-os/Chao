extends Node
var failures:=0
var checks:=0
var view: Control
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(label)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	source.keywords=[];source.cost=4
	var deck: Array=[]
	for i in 10:
		source.name="手牌"+str(i)
		for j in 4: deck.append(CardRuntime.compile_card(source,[]))
	var game:=BattleEngine.new()
	check(game.setup(deck,deck,23).is_empty(),"fixture setup")
	game.state.active_player=0;game.state.players[0].credits=5
	game.state.players[0].hand=[]
	for i in 9: game.state.players[0].hand.append({"instance_id":"pick"+str(i),"card":deck[i*4]})
	view=load("res://scripts/ui/battle_view.gd").new()
	view.state=game.view_for(0);view.connected=true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	for viewport_size in [Vector2i(1435,953),Vector2i(1920,1080),Vector2i(1440,640),Vector2i(960,540)]:
		get_window().size=viewport_size
		await get_tree().process_frame
		view.present_snapshot(game.view_for(0),true,"",-1)
		await get_tree().process_frame
		var faces: Array=[]
		for i in 9:faces.append(view.visual_faces["h:pick"+str(i)])
		# Reverse GUI sibling order to reproduce reused controls disagreeing with z order.
		for face in faces: view.board.move_child(face,0)
		for face in faces:
			var point: Vector2=face.get_global_transform_with_canvas()*Vector2(34,24)
			check(view._hand_hit_owner(point)==face,"visible title belongs to "+face.spec.name+" at "+str(viewport_size))
			for other in faces:
				check(other._has_point(other.get_global_transform_with_canvas().affine_inverse()*point)==(face==other),"only visible face accepts pointer")
		# Hover enlargement cannot steal a neighbor's resting title strip.
		var raised=faces[6]
		raised.position-=Vector2(0,24);raised.scale=Vector2(1.1,1.1);raised.extended_hover=true;raised.z_index=40
		var next=faces[5]
		var point: Vector2=next.get_global_transform_with_canvas()*Vector2(34,24)
		check(view._hand_hit_owner(point)==next,"4-cost middle hand stays reachable beside raised neighbor")
	print("HAND PICK 850: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)
