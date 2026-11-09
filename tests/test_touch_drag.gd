extends "res://tests/test_ui.gd"
const Face = preload("res://scripts/ui/card_face.gd")
const Drop = preload("res://scripts/ui/deck_drop_zone.gd")
const Store = preload("res://scripts/app_store.gd")
var drop_count := 0

class CountingStore extends Store:
	var writes := 0
	func save_profile() -> bool:
		writes += 1
		return super.save_profile()

func frames(n:=3) -> void:
	for i in n: await process_frame

func _run() -> void:
	root.size=Vector2i(1440,900)
	var face:=Face.new()
	face.spec=JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	face.spec.keywords=[]
	face.position=Vector2(80,80);face.size=Face.full_size(202)
	face.drag_payload={"type":"deck_add","card_id":"fixture"}
	root.add_child(face)
	var drop:=Drop.new()
	drop.position=Vector2(400,70);drop.size=Vector2(300,600)
	drop.card_dropped.connect(func(_id):drop_count+=1)
	root.add_child(drop)
	await frames()
	face.touch_gate.touch_mode=true
	var from:=face.get_global_rect().get_center()
	var to:=drop.get_global_rect().get_center()
	await motion(from)
	await press(true)
	await create_timer(0.1).timeout
	await motion(to)
	await press(false)
	await frames()
	check(drop_count==0,"quick swipe does not add a card")
	check(not root.gui_is_dragging(),"quick swipe leaves no active drag")
	await motion(from)
	await press(true)
	await create_timer(0.45).timeout
	check(root.gui_is_dragging(),"held mobile card starts drag without extra movement")
	await motion(to)
	await press(false)
	await frames()
	check(drop_count==1,"held mobile drag adds exactly one card")
	check(face.ignore_touch_click(),"release after dragging suppresses card detail click")
	face.touch_gate.touch_mode=false
	await motion(from)
	await press(true)
	await motion(from+Vector2(35,-30))
	await motion(to)
	await press(false)
	await frames()
	check(drop_count==2,"desktop dragging has no hold delay")
	face.compact=true;face.size=Face.FIELD_SIZE;face.pivot_offset=face.size/2;face.rotation=0.15
	var body:Rect2=face.card_body_rect()
	check(face.card_top_in_parent().is_equal_approx(face.get_transform()*Vector2(body.get_center().x,body.position.y)),"arrow starts at rotated card body top, excluding side badges")
	var store:=CountingStore.new()
	root.add_child(store)
	store.settings.backend_url="http://127.0.0.1:1";store._ensure_context()
	var d:Dictionary=await store.create_draft(face.spec)
	await store.confirm_draft(d.draft)
	var id:String=store.cards[0].card_id
	var before:int=store.writes
	store.add_to_deck(id);store.add_to_deck(id);store.remove_from_deck(id)
	check(store.writes==before,"local deck edits perform no profile write")
	check(store.save_local_deck("本地保存").ok and store.writes==before+1,"explicit save persists the edited deck once")
	face.queue_free();drop.queue_free();store.queue_free();await frames()
	print("TOUCH DRAG: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)

func motion(point:Vector2) -> void:
	var event:=InputEventMouseMotion.new()
	event.position=point;event.global_position=point;event.relative=point-mouse_position
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0
	mouse_position=point;Input.parse_input_event(event);await frames(2)

func press(down:bool) -> void:
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=mouse_position;event.global_position=mouse_position
	Input.parse_input_event(event);await frames(2)
