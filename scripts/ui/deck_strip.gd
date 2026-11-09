extends Button
signal drag_started(data: Dictionary)
var drag_allowed: Callable
var touch_gate = preload("res://scripts/ui/touch_drag_gate.gd").new(self)

var record: Dictionary = {}
var copies := 1
var draggable := true
var artwork: Texture2D

func _ready() -> void:
	set_process(false)
	gui_input.connect(touch_gate.gui_input)

	custom_minimum_size = Vector2(270, 52 if OS.has_feature("mobile") else 44)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus"]: add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	resized.connect(queue_redraw)
	tooltip_text = str(record.get("definition", {}).get("name", ""))
	var id := str(record.get("art", {}).get("id", ""))
	if not id.is_empty():
		artwork = await CardArtCache.load_art(id, get_tree())
		queue_redraw()

func _draw() -> void:
	if record.is_empty():return
	var spec:Dictionary=record.definition
	var font:=get_theme_font("font")
	var rect:=Rect2(0,1,size.x,size.y-2)
	var base:=SinCatalog.color_for(spec).lerp(Color("2b2b2b"),0.55)
	if is_hovered():base=base.lightened(0.10)
	draw_style_box(ChaoUI.style(base,Color("95959522"),5,0),rect)
	if artwork!=null:
		var source:=artwork.get_size();var crop:=Vector2(92,size.y)/maxf(92/source.x,size.y/source.y)
		draw_texture_rect_region(artwork,Rect2(size.x-92,2,90,size.y-4),Rect2((source-crop)*0.5,crop),Color(1,1,1,0.38))
		draw_rect(Rect2(size.x-92,2,90,size.y-4),Color(0.02,0.05,0.075,0.40))
	draw_style_box(ChaoUI.style(Color("202020bf"),Color.TRANSPARENT,4,0),Rect2(4,5,31,size.y-10))
	draw_string(font,Vector2(4,(size.y+font.get_ascent(22)-font.get_descent(22))/2),str(spec.cost),HORIZONTAL_ALIGNMENT_CENTER,31,22,ChaoUI.ACCENT)
	var title:=TextLine.new();title.add_string(str(spec.name),font,14);title.width=size.x-92;title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	title.draw(get_canvas_item(),Vector2(45,(size.y-title.get_size().y)/2),ChaoUI.TEXT)
	draw_style_box(ChaoUI.style(Color("151515de"),Color.TRANSPARENT,4,0),Rect2(size.x-37,6,29,size.y-12))
	draw_string(font,Vector2(size.x-37,(size.y+font.get_ascent(16)-font.get_descent(16))/2),"×"+str(copies),HORIZONTAL_ALIGNMENT_CENTER,29,16,ChaoUI.TEXT)

func _drag_preview() -> Control:
	var preview = get_script().new()
	preview.record = record
	preview.copies = 1
	preview.custom_minimum_size = size
	preview.size = size
	preview.position = -size * 0.5
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return preview

func can_begin_drag() -> bool:
	return not disabled and draggable and not record.is_empty()

func _drag_data() -> Dictionary:
	return touch_gate.protect_drop({"type":"deck_remove","card_id":str(record.card_id)})

func _get_drag_data(_position: Vector2) -> Variant:
	if not can_begin_drag() or not touch_gate.can_drag(): return null
	set_drag_preview(_drag_preview())
	var data := _drag_data()
	drag_started.emit(data)
	return data

func begin_touch_drag() -> void:
	var data := _drag_data()
	force_drag(data, _drag_preview())
	drag_started.emit(data)

func ignore_touch_click() -> bool:
	return touch_gate.ignore_click()

func _input(event: InputEvent) -> void:
	touch_gate.input(event)

func _process(delta: float) -> void:
	touch_gate.tick(delta)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_EXIT_TREE]: touch_gate.reset()
