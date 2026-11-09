extends Control
## The shade intercepts only background clicks; holes pass through to legal cards.
signal finished
signal canceled
signal card_chosen(index: int)
var card_scroll: ScrollContainer
var card_row: HBoxContainer
var options_key := ""
var read_only := false
var allowed_rects: Array = []
var can_cancel := false
var prompt: PanelContainer
var message: Label
var cancel_button: Button
var finish_button: Button

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	z_index=60
	prompt=PanelContainer.new()
	prompt.z_index=10
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("171717f5")
	style.set_corner_radius_all(12)
	style.border_color=Color("d4d4d455")
	style.set_border_width_all(0)
	style.set_content_margin_all(16)
	prompt.add_theme_stylebox_override("panel",style)
	add_child(prompt)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",18)
	prompt.add_child(row)
	message=Label.new()
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	message.max_lines_visible=2
	message.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	message.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	message.add_theme_font_size_override("font_size",22)
	message.add_theme_color_override("font_color",ChaoUI.TEXT)
	row.add_child(message)
	cancel_button=Button.new()
	cancel_button.text="取消"
	ChaoUI.skin_button(cancel_button)
	cancel_button.custom_minimum_size=Vector2(80,44)
	cancel_button.pressed.connect(func(): canceled.emit())
	row.add_child(cancel_button)
	finish_button=Button.new()
	finish_button.text="完成选择"
	ChaoUI.skin_button(finish_button,true)
	finish_button.custom_minimum_size=Vector2(120,44)
	finish_button.pressed.connect(func():finished.emit())
	finish_button.visible=false
	row.add_child(finish_button)
	card_scroll = ScrollContainer.new()
	card_scroll.z_index = 10
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(card_scroll)
	card_row = HBoxContainer.new()
	card_row.add_theme_constant_override("separation",24)
	card_scroll.add_child(card_row)
	card_scroll.visible = false
	visible=false

func configure(text: String, holes: Array, cancelable: bool) -> void:
	visible=not text.is_empty()
	allowed_rects=holes
	can_cancel=cancelable
	if not visible: return
	message.text=text
	cancel_button.visible=cancelable
	var width:=minf(880,size.x-60)
	prompt.size=Vector2(width,84)
	prompt.position=Vector2((size.x-width)*0.5,18)
	queue_redraw()

func _has_point(point: Vector2) -> bool:
	if not visible: return false
	if read_only: return card_scroll.visible and card_scroll.get_rect().has_point(point)
	if is_instance_valid(prompt) and prompt.get_rect().has_point(point): return true
	for rect in allowed_rects:
		if rect.has_point(point): return false
	return Rect2(Vector2.ZERO,size).has_point(point)

func _draw() -> void:
	if read_only: return
	# 3D cards live beneath this canvas: leave genuine holes for legal targets.
	var xs:Array[float]=[0.0,size.x]
	var ys:Array[float]=[0.0,size.y]
	for rect in allowed_rects:
		var cut:Rect2=rect.intersection(Rect2(Vector2.ZERO,size))
		if cut.has_area():xs.append(cut.position.x);xs.append(cut.end.x);ys.append(cut.position.y);ys.append(cut.end.y)
	xs.sort();ys.sort()
	for x in xs.size()-1:
		for y in ys.size()-1:
			var tile:=Rect2(xs[x],ys[y],xs[x+1]-xs[x],ys[y+1]-ys[y])
			if not tile.has_area():continue
			var hole:=false
			for rect in allowed_rects:
				if rect.has_point(tile.get_center()):hole=true;break
			if not hole:draw_rect(tile,Color(0.015,0.025,0.04,0.68))

func _gui_input(event: InputEvent) -> void:
	if can_cancel and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed: canceled.emit()
	accept_event()

func show_cards(choice: Dictionary, hand_sin: String = "") -> void:
	var options: Array = choice.get("options",[])
	card_scroll.visible = visible and not options.is_empty()
	var key: String = str(choice.get("choice_id",""))+":"+str(options.hash())+":"+str(read_only)+":"+hand_sin if card_scroll.visible else ""
	if key != options_key:
		options_key = key
		for node in card_row.get_children(): card_row.remove_child(node); node.queue_free()
		for index in options.size():
			var column := VBoxContainer.new()
			column.custom_minimum_size.x = 252
			column.add_theme_constant_override("separation",12)
			card_row.add_child(column)
			var effect_choice: bool = choice.get("kind") == "effect"
			var hidden_choice: bool = choice.get("kind") == "intel"
			var face: Button
			if hidden_choice:
				face = preload("res://scripts/ui/battle_props.gd").new()
				face.kind = "back"
				face.sin_id = hand_sin
				face.custom_minimum_size = CardFace.FULL_CARD_SIZE
			else:
				face = preload("res://scripts/ui/card_face.gd").new()
				if effect_choice:
					face.spec = {"name":options[index].label,"kind":"order","cost":0,"unit_class":null,"operation_cost":0,"attack":0,"health":0,"keywords":[],"abilities":[],"tokens":[],"play_target":null,"appearance":{"emblem":"order"},"faction_id":choice.get("source_faction_id",""),"sin":choice.get("source_sin",null),"_keyword_info":choice.get("keyword_info",[])}
					face.choice_mode = true
					face.subtitle = CardRuntime.short_text(options[index].rules_text)
				else:
					face.spec = CardRuntime.display_definition(options[index])
					face.art_id = options[index].get("art_id","")
				face.custom_minimum_size = face.full_size(252)
				face.use_tooltip = false
				face.touch_gate.hold_required = false
			face.disabled = read_only
			face.pressed.connect(_select.bind(str(choice.choice_id),index))
			column.add_child(face)
			if not hidden_choice: face.refresh_art()
			var choose := Button.new()
			choose.text = "查看第 %d 张手牌" % (int(options[index].hand_position)+1) if hidden_choice else "选择此效果" if effect_choice else "弃置这张" if choice.get("kind") == "discard" else "选择这张"
			choose.visible = not read_only
			choose.custom_minimum_size = Vector2(252,52)
			choose.add_theme_font_size_override("font_size",22)
			choose.pressed.connect(_select.bind(str(choice.choice_id),index))
			column.add_child(choose)
	var width := minf(size.x-80, float(options.size())*276-24)
	var top := maxf(140,prompt.position.y+prompt.size.y+16)
	card_scroll.size = Vector2(maxf(252,width),maxf(80,size.y-top-20))
	card_scroll.position = Vector2((size.x-card_scroll.size.x)*0.5,top)

func _select(choice_id: String, index: int) -> void:
	if read_only: return
	if not visible or not options_key.begins_with(choice_id+":"): return
	card_chosen.emit(index)
