extends Control
const Wheel = preload("res://scripts/ui/emote_wheel.gd")
const Sprite = preload("res://scripts/ui/emote_sprite.gd")
signal send_requested(id: String, point: Vector2)
signal opened
var service: Node
var me := 0
var enabled := true
var input_blocked := false
var _button: Button
var _visual_rng := RandomNumberGenerator.new()
var _wheel_overlay: Control
var _wheel: Control
var _hint: Label
var _bubbles: Array=[]
var hq_width := 156.0
var _due := 0
var _mode := ""
var _anchor := Vector2.ZERO
var _pointer := Vector2.ZERO
var _selected := -1
var _touch_index := -1
var _stable_at := 0
var _touch_start := Vector2.ZERO
var _mobile := OS.has_feature("mobile") or OS.get_environment("FRONTLINE_MOBILE_TEST")=="1"

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;z_index=35
	_button=Button.new();_button.text="表情";_button.custom_minimum_size=Vector2(114,50);add_child(_button)
	_button.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.device!=InputEvent.DEVICE_ID_EMULATION and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and _can_open():
			_open_at(get_local_mouse_position(),"click");_button.accept_event())
	_visual_rng.randomize();_button.visible=_mobile
	resized.connect(_fit);get_window().focus_exited.connect(_cancel_gesture);_fit()

func _can_open() -> bool:
	return enabled and not input_blocked and is_visible_in_tree() and Time.get_ticks_msec()>=_due

func _fit() -> void:
	if not _button: return
	_button.position=Vector2(24,size.y-220)
	_animate_bubbles()
	if is_instance_valid(_wheel): _wheel.position=_wheel_position(_anchor)

func _process(_delta: float) -> void:
	_animate_bubbles()
	_button.visible=_mobile
	_button.disabled=not _can_open()
	_button.text="按住表情" if _mobile else "表情 · "+OS.get_keycode_string(service.shortcut)
	if (not enabled or input_blocked) and not _mode.is_empty(): _close();_touch_index=-1
	if _mode=="placing" and Time.get_ticks_msec()-_stable_at>=240: _open_at(_pointer,"touch")
	if service.mute_opponent:
		for bubble in _bubbles.duplicate():
			if int(bubble.get_meta("player"))!=me: _bubbles.erase(bubble);bubble.queue_free()

func _local_point(point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse()*point

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if event is InputEventKey:
		if event.echo: return
		var key: int=event.physical_keycode if event.physical_keycode else event.keycode
		if event.pressed and key==KEY_ESCAPE and not _mode.is_empty():
			_close();_touch_index=-1;get_viewport().set_input_as_handled();return
		if key!=service.shortcut: return
		if not event.pressed and _mode=="key":
			_finish();get_viewport().set_input_as_handled();return
		var focus := get_viewport().gui_get_focus_owner()
		if event.pressed and _can_open() and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and not focus is LineEdit and not focus is TextEdit:
			_open_at(get_local_mouse_position(),"key");get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _mode=="key":
		_update_direction(_local_point(event.position));get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var point := _local_point(event.position)
		if event.pressed and _touch_index<0 and _button.get_rect().has_point(point) and _can_open():
			_mobile=true;_touch_index=event.index;_mode="placing";_pointer=point;_touch_start=point;_stable_at=Time.get_ticks_msec();queue_redraw();get_viewport().set_input_as_handled()
		elif not event.pressed and event.index==_touch_index:
			get_viewport().set_input_as_handled();_touch_index=-1
			if _mode=="touch": _update_direction(point);_finish()
			elif _mode=="placing":
				if point.distance_to(_touch_start)<20: _open_at(point,"click")
				else: _close()
	elif event is InputEventScreenDrag and event.index==_touch_index:
		var point := _local_point(event.position)
		if _mode=="placing":
			if point.distance_to(_pointer)>5: _stable_at=Time.get_ticks_msec()
			_pointer=point;queue_redraw()
		elif _mode=="touch": _update_direction(point)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT and not _mode.is_empty():
		_close();get_viewport().set_input_as_handled()

func _diameter() -> float:
	return 260.0 if _mobile else 224.0

func _wheel_position(point: Vector2) -> Vector2:
	return (point-Vector2.ONE*_diameter()/2.0).clamp(Vector2(8,8),size-Vector2.ONE*(_diameter()+8))

func _open() -> void:
	_open_at(size/2.0,"click")

func _open_at(point: Vector2, gesture: String) -> void:
	_close();opened.emit();_anchor=point.clamp(Vector2.ZERO,size);_mode=gesture;_selected=-1
	_wheel_overlay=Control.new();_wheel_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(_wheel_overlay)
	var shade := ColorRect.new();shade.color=Color(0.02,0.04,0.03,0.14);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_wheel_overlay.add_child(shade)
	shade.gui_input.connect(func(event): if _mode=="click" and event is InputEventMouseButton and event.pressed: _close())
	_wheel=Wheel.new();_wheel.compact=true;_wheel.service=service;_wheel.slots=service.slots.duplicate();_wheel.size=Vector2.ONE*_diameter();_wheel.position=_wheel_position(_anchor)
	if gesture=="key" and not service.repeat_id().is_empty(): _wheel.center_text="重发上次"
	_wheel_overlay.add_child(_wheel)
	_wheel.canceled.connect(_close)
	_wheel.picked.connect(func(index):
		if _mode=="click": _selected=index;_finish())
	_hint=Label.new();_hint.text="滑向表情，松手发送" if gesture=="touch" else ("移动鼠标，松开 %s 发送"%OS.get_keycode_string(service.shortcut) if gesture=="key" else "点击表情发送")
	_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_hint.add_theme_font_size_override("font_size",14);_hint.position=Vector2(_wheel.position.x,maxf(6,_wheel.position.y-30));_hint.size=Vector2(_diameter(),24);_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE;_wheel_overlay.add_child(_hint)
	queue_redraw()

func _update_direction(point: Vector2) -> void:
	_pointer=point
	if is_instance_valid(_wheel): _selected=_wheel.set_direction(point-_anchor)

func _finish() -> void:
	var index := _selected
	var id: String=service.repeat_id() if _mode=="key" and index<0 else (str(service.slots[index]) if index>=0 and index<8 else "")
	var at := _anchor/size
	if me==1: at.y=1.0-at.y
	_close()
	if id.is_empty():
		return
	service.last_sent_id=id;_due=Time.get_ticks_msec()+80;send_requested.emit(id,at)

func _close() -> void:
	if is_instance_valid(_wheel_overlay): remove_child(_wheel_overlay);_wheel_overlay.queue_free()
	_wheel_overlay=null;_wheel=null;_hint=null;_mode="";_selected=-1;queue_redraw()

func _draw() -> void:
	if _mode=="placing":
		draw_circle(_pointer,22,Color(0.9,0.78,0.45,0.25))
		draw_arc(_pointer,22,0,TAU,40,Color("dcc27b"),2.0,true)
		draw_string(get_theme_default_font(),Vector2(clampf(_pointer.x-150,8,size.x-308),maxf(28,_pointer.y-36)),"停留后选择表情",HORIZONTAL_ALIGNMENT_CENTER,300,20,Color("efe6bf"))

func _bubble_at(player: int, point: Vector2=Vector2(-1,-1), extent: float=72.0) -> Vector2:
	if point.is_finite() and point.x>=0 and point.x<=1 and point.y>=0 and point.y<=1:
		if me==1: point.y=1.0-point.y
		return (point*size-Vector2.ONE*extent/2.0).clamp(Vector2(8,8),(size-Vector2.ONE*(extent+8)).max(Vector2(8,8)))
	return Vector2(22,size.y-396) if player==me else Vector2(size.x-178,86)

func show_emote(player: int, id: String, point: Vector2=Vector2(-1,-1), display_scale: float=-1.0) -> void:
	if player not in [0,1] or (player!=me and service.mute_opponent): return
	var entry: Dictionary=service.entry(id)
	if entry.is_empty(): return
	while _bubbles.size()>=32:
		var old: Control=_bubbles.pop_front();old.queue_free()
	var sprite := Sprite.new();sprite.entry=entry;sprite.origin=service.origin
	sprite.set_meta("display_scale",(preload("res://scripts/ui/emote_cache.gd").entry_scale(entry) if display_scale<0 else preload("res://scripts/ui/emote_cache.gd").display_scale(display_scale)))
	sprite.size=Vector2.ONE*hq_width*float(sprite.get_meta("display_scale"));sprite.pivot_offset=sprite.size/2.0
	sprite.set_meta("point",point);sprite.set_meta("player",player)
	sprite.set_meta("offset",Vector2(_visual_rng.randf_range(-12,12),_visual_rng.randf_range(-8,8)))
	sprite.set_meta("rise",_visual_rng.randf_range(24,34));sprite.set_meta("born",Time.get_ticks_msec())
	sprite.rotation=_visual_rng.randf_range(-0.14,0.14)
	add_child(sprite);_bubbles.append(sprite);_animate_bubbles()

func _animate_bubbles() -> void:
	for sprite in _bubbles.duplicate():
		var age: float=(Time.get_ticks_msec()-int(sprite.get_meta("born")))/1000.0
		if age>=1.9: _bubbles.erase(sprite);sprite.queue_free();continue
		var progress: float=clampf(age/1.9,0.0,1.0)
		sprite.size=Vector2.ONE*hq_width*float(sprite.get_meta("display_scale"));sprite.pivot_offset=sprite.size/2.0
		sprite.position=_bubble_at(int(sprite.get_meta("player")),sprite.get_meta("point"),sprite.size.x)+sprite.get_meta("offset")+Vector2(0,-float(sprite.get_meta("rise"))*progress)
		sprite.modulate.a=minf(clampf(age/0.06,0.0,1.0),1.0-smoothstep(0.30,1.9,age))

func _cancel_gesture() -> void:
	_close();_touch_index=-1
