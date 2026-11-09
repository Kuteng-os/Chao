extends Control
const Sprite = preload("res://scripts/ui/emote_sprite.gd")
signal picked(index: int)
signal canceled
var service: Node
var slots: Array = []
var selected := -1
var editing := false
var compact := false
var center_text := "取消"
var _hover := -1

func _ready() -> void:
	custom_minimum_size=custom_minimum_size.max(Vector2(224,224) if compact else Vector2(340,340))
	mouse_filter=Control.MOUSE_FILTER_STOP
	resized.connect(rebuild)
	rebuild()

func rebuild() -> void:
	for child in get_children(): remove_child(child);child.queue_free()
	if not is_instance_valid(service): return
	var center := size/2.0
	var icon_size := minf(68,minf(size.x,size.y)*0.17)
	var radius := minf(size.x,size.y)*0.34
	for i in 8:
		var angle := -PI/2.0+float(i)*TAU/8.0
		var at := center+Vector2(cos(angle),sin(angle))*radius
		var e: Dictionary=service.entry(str(slots[i])) if slots.size()==8 else {}
		if not e.is_empty():
			var sprite := Sprite.new();sprite.entry=e;sprite.origin=service.origin
			sprite.position=at-Vector2.ONE*icon_size/2.0;sprite.size=Vector2.ONE*icon_size;add_child(sprite)
		else:
			var label := Label.new();label.text=str(i+1) if editing else "·";label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
			label.position=at-Vector2(30,24);label.size=Vector2(60,48);label.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(label)
	var title := Label.new();title.text="位置 %d"%(selected+1) if editing else center_text
	title.position=center-Vector2(55,16);title.size=Vector2(110,32);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.mouse_filter=Control.MOUSE_FILTER_IGNORE;title.add_theme_font_size_override("font_size",13 if compact else 17);add_child(title)
	queue_redraw()

func sector(point: Vector2) -> int:
	var delta := point-size/2.0
	var radius := minf(size.x,size.y)/2.0
	if delta.length()<radius*0.34 or delta.length()>radius: return -1
	return posmod(int(floor((delta.angle()+PI/2.0+PI/8.0)/(TAU/8.0))),8)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover=sector(event.position);queue_redraw()
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		var index := sector(event.position)
		accept_event()
		if index>=0: picked.emit(index)
		else: canceled.emit()

func _draw() -> void:
	var center := size/2.0
	var radius := minf(size.x,size.y)/2.0-2
	for i in 8:
		var start := -PI/2.0+float(i)*TAU/8.0-PI/8.0+0.014
		var end := start+TAU/8.0-0.028
		var points := PackedVector2Array()
		for step in 13:
			var angle := lerpf(start,end,float(step)/12.0);points.append(center+Vector2(cos(angle),sin(angle))*radius)
		for step in range(12,-1,-1):
			var angle := lerpf(start,end,float(step)/12.0);points.append(center+Vector2(cos(angle),sin(angle))*radius*0.35)
		draw_colored_polygon(points,Color("636363d9") if i==selected or i==_hover else Color("14232dea"))
		draw_polyline(points+PackedVector2Array([points[0]]),ChaoUI.ACCENT if i==selected else Color("79797966"),1.0,true)
	draw_circle(center,radius*0.32,Color("0b1822e6"))

func set_direction(delta: Vector2) -> int:
	_hover=-1 if delta.length()<(14 if compact else 28) else posmod(int(floor((delta.angle()+PI/2.0+PI/8.0)/(TAU/8.0))),8)
	queue_redraw()
	return _hover
