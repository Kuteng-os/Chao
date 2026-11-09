extends Control
## Decorative local shuffle; never touches deck selection or the battle RNG.
signal card_selected(record: Dictionary)
const Face = preload("res://scripts/ui/card_face.gd")
const Audio = preload("res://scripts/ui/frontline_audio.gd")
const READ_SECONDS := 5.0
const CHANGE_SECONDS := 0.55
var blocked: Callable
var records: Array = []
var resolve_definition: Callable
var rng := RandomNumberGenerator.new()
var bag: Array[int] = []
var current_index := -1
var pending_index := -1
var current: CardFace
var pending: CardFace
var caption: Label
var card_size := Face.full_size(270)
var elapsed := 0.0
var transition := -1.0
var waiting := 0.0
var app_paused := false

func _ready() -> void:
	rng.randomize()
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	caption = Label.new()
	caption.text = "随机卡牌 · 点击查看"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",12)
	caption.add_theme_color_override("font_color",Color("a3a3a3"))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	resized.connect(_layout)

func configure(catalog: Array, definition: Callable, width: float) -> void:
	records = catalog.filter(func(r):return CardArtCache.valid_id(str(r.get("art",{}).get("id",""))))
	resolve_definition = definition
	card_size = Face.full_size(width)
	custom_minimum_size = card_size+Vector2(32,60)
	visible = not records.is_empty()
	if records.is_empty(): return
	current_index = _take_index()
	current = _make_face(current_index)
	current.mouse_filter = Control.MOUSE_FILTER_STOP
	current.focus_mode = Control.FOCUS_ALL
	_prefetch()
	_layout()

func _take_index() -> int:
	if bag.is_empty():
		for i in records.size(): bag.append(i)
		for i in range(bag.size()-1,0,-1):
			var j := rng.randi_range(0,i)
			var swap := bag[i]; bag[i] = bag[j]; bag[j] = swap
		# A new shuffle cycle must not repeat the card just shown.
		if bag.size()>1 and bag[-1]==current_index:
			var swap := bag[0]; bag[0] = bag[-1]; bag[-1] = swap
	return bag.pop_back()

func _make_face(index: int) -> CardFace:
	var face := Face.new()
	face.spec = resolve_definition.call(records[index])
	face.art_id = str(records[index].art.id)
	face.use_tooltip = false
	face.custom_minimum_size = card_size
	face.size = card_size
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.focus_mode = Control.FOCUS_NONE
	face.touch_gate.hold_required = false
	face.pressed.connect(func():
		if transition < 0 and face==current: card_selected.emit(records[index]))
	add_child(face)
	face.pivot_offset = card_size*0.5
	return face

func _prefetch() -> void:
	if records.size()<2: return
	pending_index = _take_index()
	pending = _make_face(pending_index)
	pending.hide()
	waiting = 0.0

func _layout() -> void:
	if not is_instance_valid(caption): return
	caption.position = Vector2(0,card_size.y+25)
	caption.size = Vector2(size.x,20)
	if transition < 0 and is_instance_valid(current): current.position = Vector2((size.x-card_size.x)*0.5,12)
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree() or records.size()<2 or app_paused or (blocked.is_valid() and blocked.call()): return
	if transition >= 0:
		transition += delta
		var t := clampf(transition/CHANGE_SECONDS,0,1)
		var eased := t*t*(3-2*t)
		var base := Vector2((size.x-card_size.x)*0.5,12)
		current.position = base+Vector2(-36*eased,0)
		current.modulate.a = 1-eased
		current.scale = Vector2.ONE*(1-0.015*eased)
		pending.position = base+Vector2(36*(1-eased),0)
		pending.modulate.a = eased
		pending.scale = Vector2.ONE*(0.985+0.015*eased)
		if t>=1: _finish_change()
	else:
		# Hover, keyboard focus and touch hold retain the readable card.
		if get_global_rect().has_point(get_global_mouse_position()) or current.has_focus() or current.is_pressed(): return
		elapsed = minf(READ_SECONDS,elapsed+delta)
		if elapsed>=READ_SECONDS:
			if pending.artwork != null:
				current.mouse_filter = Control.MOUSE_FILTER_IGNORE
				current.focus_mode = Control.FOCUS_NONE
				pending.show(); pending.modulate.a = 0
				transition = 0
				var audio := Audio.service(self)
				if audio != null and not audio.preferences.animations: _finish_change()
			else:
				# Leave the current artwork in place while the next image loads.
				waiting += delta
				if waiting>=5:
					pending.queue_free()
					_prefetch()
	queue_redraw()

func _finish_change() -> void:
	current.hide(); current.queue_free()
	current = pending
	current_index = pending_index
	current.modulate = Color.WHITE
	current.scale = Vector2.ONE
	current.mouse_filter = Control.MOUSE_FILTER_STOP
	current.focus_mode = Control.FOCUS_ALL
	transition = -1
	elapsed = 0
	_prefetch()
	_layout()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]: app_paused = true
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_APPLICATION_RESUMED]: app_paused = false

func _draw() -> void:
	if records.size()<2: return
	var from := Vector2((size.x-64)*0.5,card_size.y+51)
	draw_line(from,from+Vector2(64,0),Color(1,1,1,0.10),2,true)
	draw_line(from,from+Vector2(64*elapsed/READ_SECONDS,0),Color(1,1,1,0.40),2,true)
