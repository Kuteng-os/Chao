class_name CardFace
extends Button
signal drag_started(data: Dictionary)
var drag_allowed: Callable
var drag_press_global := Vector2.ZERO
var touch_gate = preload("res://scripts/ui/touch_drag_gate.gd").new(self)

const Audio = preload("res://scripts/ui/frontline_audio.gd")
const Typography = preload("res://scripts/ui/card_typography.gd")
const TitleLayout = preload("res://scripts/ui/card_title.gd")
const FIELD_SIZE := Vector2(150, 178)
const FIELD_BODY := Vector2(130, 178)
const FULL_CARD_SIZE := Vector2(252, 354)
const RARITY_FOOTER_HEIGHT := 20.0
const RULES_FONT_MAX := 18
const RULES_FONT_MIN := 13
const RULES_WIDTH := 214.0
const RULES_HEIGHT := 78.0
const UNIT_RULES_HEIGHT := 101.0
## Units share a continuous title/cost band above the artwork.

var spec: Dictionary = {}
var compact := false
var choice_mode := false
var hand_mode := false
var battle_drag := false
var highlighted := false
var enemy := false
var caption := ""
var current_attack := -1
var current_health := -1
var current_operation_cost := -1
var current_armor := 0
var current_custom_stacks: Dictionary = {}
var field_effects: Array = []
var subtitle := ""
var can_act := false
var is_target := false
var base_attack := -1
var base_health := -1
var max_health := -1
var drag_payload: Dictionary = {}
var use_tooltip := true
var extended_hover := false
var hand_hit_owner: Callable
var author_name := ""
var art_id := ""
var artwork: Texture2D
var faction_icon: Texture2D
var _print_font: FontVariation
var _order_name_font: FontVariation
var _loaded_art_id := ""
var _loaded_icon_id := ""
var _rules_layout_cache := {}
static var _shared_rules_layouts: Dictionary = {}
const RULES_LAYOUT_CACHE_LIMIT := 128
var _rules_source: Array = []
var _rules_cache := ""
var _keyword_labels: Array = []
var watermark: TextureRect
static var _art_shade: GradientTexture2D
static var _art_fade: GradientTexture2D
var _metal_finish: ShaderMaterial


func _has_point(point: Vector2) -> bool:
	if hand_mode and hand_hit_owner.is_valid():
		return hand_hit_owner.call(get_global_transform_with_canvas()*point)==self
	# Keep the original hand footprint clickable while its visual is raised.
	var hit_size := size + (Vector2(0, 32) if hand_mode and extended_hover else Vector2.ZERO)
	return Rect2(Vector2.ZERO, hit_size).has_point(point)
const PAPER := Color("d8d0b7")
const GOLD := Color("d4b76f")
const INK := Color("302f28")
const RED := Color("e17160")
const GREEN := Color("a4c27e")
const CLASS_NAMES := {"infantry":"步兵", "tank":"坦克", "artillery":"炮兵", "fighter":"战斗机", "bomber":"轰炸机", "order":"指令", "counter":"反制", "field":"场地", "hq":"总部", "<null>":"指令"}

func _ready() -> void:
	set_process(false)
	var print_font := Typography.card_font(get_theme_default_font())
	if print_font != get_theme_default_font():
		var print_theme := Theme.new()
		print_theme.default_font = print_font
		print_theme.default_font_size = get_theme_default_font_size()
		theme = print_theme
	gui_input.connect(touch_gate.gui_input)
	gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			drag_press_global = get_global_transform() * event.position
	)

	var audio:=preload("res://scripts/ui/frontline_audio.gd").service(self)
	if audio!=null: audio.preload_media(spec.get("media",{}))
	flat = true
	clip_contents = true
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = FIELD_SIZE if compact else full_size(166 if hand_mode else 174)
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	resized.connect(queue_redraw)
	pivot_offset = size / 2.0
	_refresh_tooltip()
	refresh_art()

func refresh_art() -> void:
	if not is_inside_tree(): return
	var icon_id := str(FactionCatalog.info(spec).get("icon_id", ""))
	if icon_id != _loaded_icon_id:
		_loaded_icon_id = icon_id
		faction_icon = null
		if CardArtCache.valid_id(icon_id):
			var texture := await CardArtCache.load_art(icon_id,get_tree())
			if icon_id == _loaded_icon_id: faction_icon = texture
		queue_redraw()
	var display_art := "" if choice_mode else art_id if CardArtCache.valid_id(art_id) else str(FactionCatalog.info(spec).get("background_id",""))
	if display_art != _loaded_art_id:
		var requested := display_art
		_loaded_art_id = requested
		artwork = null
		if CardArtCache.valid_id(requested):
			var texture := await CardArtCache.load_art(requested,get_tree())
			if requested == _loaded_art_id: artwork = texture
		queue_redraw()

func _refresh_tooltip() -> void:
	if not use_tooltip:
		tooltip_text = ""
		return
	if spec.is_empty(): return
	var title := str(spec.get("name", "未命名"))
	var kind := str((spec.get("unit_class") if spec.get("unit_class") != null else spec.get("kind", "order")))
	var summary := "%s · 费用 %d" % [CLASS_NAMES.get(kind, "指令"), int(spec.get("cost", 0))]
	if spec.get("kind", "unit") == "unit":
		summary += " · 行动 %d · 攻击 %d · 生命 %d" % [_operation_cost(), _attack(), _health()]
	var rules := _ability_text(CardRuntime.detailed_rules_text(spec))
	tooltip_text = title + "\n" + SinCatalog.label(SinCatalog.id_of(spec)) + "\n" + str(FactionCatalog.info(spec).get("name", "未指定阵营")) + "\n" + summary + ("\n" + rules if not rules.is_empty() else "") + ("\n作者 · " + author_name if not author_name.is_empty() else "")

func _attack() -> int:
	return current_attack if current_attack >= 0 else int(spec.get("attack", 0))

func _health() -> int:
	return current_health if current_health >= 0 else int(spec.get("health", 0))

func _operation_cost() -> int:
	return current_operation_cost if current_operation_cost >= 0 else int(spec.get("operation_cost", 0))

func _drag_preview() -> Control:
	if battle_drag:
		var marker := Control.new()
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return marker
	var preview := CardFace.new()
	preview.spec = spec.duplicate(true)
	preview.art_id = art_id
	preview.artwork = artwork
	preview.compact = not battle_drag and spec.get("kind", "unit") == "unit" and drag_payload.get("type") != "deck_add"
	preview.enemy = enemy
	preview.current_attack = current_attack
	preview.current_health = current_health
	preview.current_operation_cost = current_operation_cost
	preview.current_armor = current_armor
	preview.current_custom_stacks = current_custom_stacks.duplicate(true)
	preview.field_effects = field_effects.duplicate(true)
	preview.base_attack = base_attack
	preview.base_health = base_health
	preview.max_health = max_health
	preview.highlighted = true
	preview.can_act = can_act
	var preview_size := full_size(220) if battle_drag else (FIELD_SIZE if preview.compact else full_size(126))
	preview.custom_minimum_size = preview_size
	preview.size = preview_size
	preview.position = Vector2(-preview_size.x*0.5,-preview_size.y-35) if battle_drag else -preview_size*0.5
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return preview

func can_begin_drag() -> bool:
	return not disabled and not drag_payload.is_empty() and (not drag_allowed.is_valid() or drag_allowed.call())

func _drag_data() -> Dictionary:
	return touch_gate.protect_drop(drag_payload.duplicate(true))

func _get_drag_data(_position: Vector2) -> Variant:
	if not can_begin_drag() or not touch_gate.can_drag(): return null
	if not touch_gate.hold_required: touch_gate.cancel(true)
	Audio.cue(self,"card")
	set_drag_preview(_drag_preview())
	var data := _drag_data()
	drag_started.emit(data)
	return data

func begin_touch_drag() -> void:
	Audio.cue(self,"card")
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

func _draw() -> void:
	if size.x < 40 or size.y < 60: return
	var print_rect := _print_rect()
	var canvas := FIELD_SIZE if compact else FULL_CARD_SIZE
	if _metal_finish==null:
		_metal_finish=ShaderMaterial.new()
		_metal_finish.shader=preload("res://assets/shaders/card_finish.gdshader")
		_metal_finish.set_shader_parameter("surface_roughness",preload("res://assets/vendor/polyhaven/metal_plate_02_rough_1k.jpg"))
		material=_metal_finish
	var art_area:=printed_art_rect()
	_metal_finish.set_shader_parameter("face_size",FIELD_BODY if compact else FULL_CARD_SIZE)
	_metal_finish.set_shader_parameter("artwork_rect",Vector4(art_area.position.x,art_area.position.y,art_area.end.x,art_area.end.y))
	_metal_finish.set_shader_parameter("has_artwork",artwork!=null)
	draw_set_transform(print_rect.position, 0, Vector2.ONE * (print_rect.size.x / canvas.x))
	if compact: _draw_field_card()
	else: _draw_full_card()
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	_refresh_tooltip()

static func full_size(width: float) -> Vector2:
	return Vector2(width,width*(FULL_CARD_SIZE.y+RARITY_FOOTER_HEIGHT)/FULL_CARD_SIZE.x)

func _print_rect() -> Rect2:
	# Containers may grow taller for mobile text. Never stretch the printed face.
	var canvas := FIELD_SIZE if compact else FULL_CARD_SIZE
	var occupied := canvas if compact else Vector2(canvas.x,canvas.y+RARITY_FOOTER_HEIGHT)
	var factor := minf(size.x/occupied.x,size.y/occupied.y)
	return Rect2((size-occupied*factor)*0.5,canvas*factor)

func card_body_rect() -> Rect2:
	var rect := _print_rect()
	if compact: rect.size.x *= FIELD_BODY.x/FIELD_SIZE.x
	return rect

func card_top_in_parent() -> Vector2:
	var body := card_body_rect()
	return get_transform() * Vector2(body.get_center().x, body.position.y)

func card_center_in_parent() -> Vector2:
	return get_transform()*card_body_rect().get_center()

func _ability_text(value: String) -> String:
	return "" if value.strip_edges() in ["无额外能力", "无额外能力。"] else value

func _text_fit(value: String, rect: Rect2, font_size: int, color: Color, alignment: HorizontalAlignment, heavy: bool = false, custom_font: Font = null) -> void:
	var font := custom_font if custom_font != null else Typography.font_for(value,get_theme_default_font())
	if heavy:
		if _print_font == null or _print_font.base_font != font:
			_print_font = Typography.weighted_font(font,0.5)
		font = _print_font
	# Costs and combat values must remain numbers, including two-digit values.
	if value.is_valid_int():
		while font_size > 10 and font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > rect.size.x:
			font_size -= 1
	var fitted := _ellipsize(value, font, rect.size.x, font_size)
	var baseline := rect.position.y + (rect.size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	draw_string(font, Vector2(rect.position.x, baseline), fitted, alignment, rect.size.x, font_size, color)

func _ellipsize(value: String, font: Font, width: float, font_size: int) -> String:
	if font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width: return value
	var shortened := value
	while shortened.length() > 0 and font.get_string_size(shortened + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		shortened = shortened.left(shortened.length() - 1)
	return shortened + "…"

func _wrap(value: String, font: Font, width: float, fs: int) -> Array[String]:
	if Typography.is_latin(value): return Typography.wrap_words(value,font,width,fs)
	var result: Array[String] = []
	var line := ""
	for letter in value:
		if letter == "\n":
			if not line.is_empty(): result.append(line)
			line = ""
			continue
		if font.get_string_size(line + letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width and not line.is_empty():
			# Keep closing punctuation with the preceding character instead of
			# leaving a full line for a single Chinese full stop or comma.
			if letter in "，。；：！？、）》】」』,.!?;:%％" and line.length() > 1:
				result.append(line.left(line.length() - 1))
				line = line.right(1)
			else:
				result.append(line)
				line = ""
		line += letter
	if not line.is_empty(): result.append(line)
	return result

# Fixed design coordinates preserve the proportions in the library, hand and inspector.
const CARD_INK := Color("111b23")
const CARD_PAPER := Color("a1b4bd")
const PRINT := Color("edf3f5")
static var _paper_texture: Texture2D

static func _paper() -> Texture2D:
	if _paper_texture == null:
		var surface := Image.create(128, 128, false, Image.FORMAT_RGB8)
		for y in 128:
			for x in 128:
				var grain := float(((x * 73856093) ^ (y * 19349663) ^ (x * y * 97)) & 255) / 255.0
				var tint := (grain - 0.5) * 0.065
				surface.set_pixel(x, y, Color(0.837 + tint, 0.815 + tint, 0.733 + tint))
		_paper_texture = ImageTexture.create_from_image(surface)
	return _paper_texture

func _frame(canvas: Vector2) -> void:
	var rect:=Rect2(Vector2(2,2),canvas-Vector2(4,4))
	var color:=FactionCatalog.color_for(spec) if choice_mode else SinCatalog.color_for(spec)
	var style:=StyleBoxFlat.new()
	style.bg_color=color.darkened(0.08)
	style.set_border_width_all(0);style.set_corner_radius_all(5 if not compact else 3)
	style.shadow_color=Color(0.015,0.025,0.04,0.55);style.shadow_size=4;style.shadow_offset=Vector2(0,3)
	# Selection uses a soft halo, separate from the unoutlined printed face.
	if is_target or highlighted or is_hovered():
		style.shadow_color=Color(Color("f3c28b") if is_target else Color("eeeeee"),0.38)
		style.shadow_size=5;style.shadow_offset=Vector2.ZERO
	draw_style_box(style,rect)
	# The canvas finish handles the satin reflection without painted stripes.
	_update_watermark()

static var _playable_style: StyleBoxFlat
static func _playable_strip() -> StyleBoxFlat:
	if _playable_style == null:
		_playable_style=StyleBoxFlat.new();_playable_style.bg_color=Color("ecdfa8");_playable_style.set_corner_radius_all(2)
		_playable_style.shadow_color=Color(0.94,0.84,0.47,0.42);_playable_style.shadow_size=4
	return _playable_style

func _update_watermark() -> void:
	if watermark==null:
		watermark=TextureRect.new();watermark.mouse_filter=Control.MOUSE_FILTER_IGNORE
		watermark.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;watermark.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var shader:=ShaderMaterial.new();shader.shader=load("res://assets/shaders/monochrome_icon.gdshader");watermark.material=shader
		add_child(watermark)
	watermark.visible=not compact and faction_icon!=null and not choice_mode
	watermark.texture=faction_icon
	var area:=_print_rect();var scale_factor:=area.size.x/FULL_CARD_SIZE.x
	watermark.position=area.position+Vector2(126-62,288)*scale_factor
	watermark.size=Vector2(124,62)*scale_factor;watermark.self_modulate=Color(0.85,0.95,1,0.11*self_modulate.a)

func _blank_art(rect: Rect2) -> void:
	if artwork!=null:
		var dimensions:=artwork.get_size();var crop:=rect.size/maxf(rect.size.x/dimensions.x,rect.size.y/dimensions.y)
		draw_texture_rect_region(artwork,rect,Rect2((dimensions-crop)*0.5,crop))
	else:
		var color:=FactionCatalog.color_for(spec) if choice_mode else SinCatalog.color_for(spec)
		draw_rect(rect,color.darkened(0.25))
		if _art_shade==null:
			_art_shade=GradientTexture2D.new();_art_shade.gradient=Gradient.new();_art_shade.gradient.set_color(0,Color(0.6,0.78,0.88,0.06));_art_shade.gradient.set_color(1,Color.TRANSPARENT);_art_shade.fill_to=Vector2(0,1)
		draw_texture_rect(_art_shade,rect,false)
		if faction_icon!=null:
			var diameter:=minf(rect.size.x,rect.size.y)*0.34
			draw_texture_rect(faction_icon,Rect2(rect.get_center()-Vector2.ONE*diameter/2,Vector2.ONE*diameter),false,Color(1,1,1,0.19))

func _unit_kind() -> String:
	return str(spec.get("unit_class")) if spec.get("unit_class") != null else str(spec.get("kind", "order"))

func _is_unit() -> bool:
	return spec.get("kind", "unit") == "unit"

func _is_order_face() -> bool:
	return spec.get("kind") == "order" and not choice_mode

func _order_title_layout() -> Dictionary:
	var base := Typography.font_for(str(spec.get("name","")),get_theme_default_font())
	if _order_name_font == null or _order_name_font.base_font != base:
		_order_name_font = Typography.weighted_font(base,0.35)
	var lines := TitleLayout.lines(spec)
	var fs := 21
	# Keep names larger than the 17px body. Long names use two lines instead of
	# shrinking into the description; explicit author breaks are retained.
	while fs > 18:
		var fits := true
		for line in lines:
			if _order_name_font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x > RULES_WIDTH: fits = false
		if fits: break
		fs -= 1
	if lines.size() == 1 and _order_name_font.get_string_size(lines[0],HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x > RULES_WIDTH:
		for candidate in range(21,17,-1):
			var wrapped := _wrap(lines[0],_order_name_font,RULES_WIDTH,candidate)
			if wrapped.size() <= 2 or candidate == 18:
				lines = PackedStringArray(wrapped);fs = candidate;break
	if lines.size() > 2:
		lines = PackedStringArray([lines[0],lines[1]+"…"])
	var line_height := ceilf(_order_name_font.get_height(fs))
	var height := line_height*lines.size()
	return {"lines":lines,"font_size":fs,"line_height":line_height,"rect":Rect2(19,270-height,RULES_WIDTH,height),"font":_order_name_font}

func _header() -> void:
	if choice_mode:
		_draw_title(Rect2(16,18,220,34),22,14)
		return
	var cost_color:=Color("fff0b5") if can_act and hand_mode else PRINT
	if _is_unit():
		# Cost is typography inside the same band, not a separate box over the art.
		draw_rect(Rect2(3,3,246,32),SinCatalog.color_for(spec).darkened(0.16))
		_text_fit(str(spec.get("cost",0)),Rect2(5,3,27,31),27,cost_color,HORIZONTAL_ALIGNMENT_CENTER,true)
		_text_fit("K",Rect2(31,4,9,11),8,Color("adc1ca"),HORIZONTAL_ALIGNMENT_CENTER)
		_text_fit(str(_operation_cost()),Rect2(30,16,11,17),12,PRINT,HORIZONTAL_ALIGNMENT_CENTER)
		_draw_title(Rect2(46,4,178,29),18,11)
		_faction_emblem(Rect2(230,11,14,14))
	else:
		# Orders keep their lower title, with a small borderless cost tab.
		draw_rect(Rect2(3,3,34,33),Color(0.035,0.06,0.08,0.78))
		_text_fit("总" if spec.get("kind")=="hq" else str(spec.get("cost",0)),Rect2(5,3,25,31),27,cost_color,HORIZONTAL_ALIGNMENT_CENTER,true)
		if spec.get("kind")!="hq":_text_fit("K",Rect2(28,5,8,12),8,Color("b7cbd2"),HORIZONTAL_ALIGNMENT_CENTER)
		if _is_order_face():
			var title := _order_title_layout()
			for i in title.lines.size():
				_text_fit(title.lines[i],Rect2(title.rect.position+Vector2(0,i*title.line_height),Vector2(RULES_WIDTH,title.line_height)),title.font_size,PRINT,HORIZONTAL_ALIGNMENT_CENTER,false,title.font)
		else:
			_draw_title(Rect2(16,238,220,29),22,13)

func _draw_title(rect: Rect2, maximum: int, minimum: int) -> void:
	var font := Typography.font_for(str(spec.get("name","")),get_theme_default_font())
	var layout := TitleLayout.layout(spec,font,rect.size.x,rect.size.y,maximum,minimum)
	var line_height: float = rect.size.y / layout.lines.size()
	for i in layout.lines.size():
		_text_fit(layout.lines[i],Rect2(rect.position+Vector2(0,i*line_height),Vector2(rect.size.x,line_height)),layout.font_size,PRINT,HORIZONTAL_ALIGNMENT_LEFT,false,font)

func _stat_rect(rect: Rect2, value: String, ink: Color, defense: bool = false) -> void:
	if defense:
		var shape := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y - 11), Vector2(rect.get_center().x + 8, rect.end.y - 3), Vector2(rect.get_center().x, rect.end.y), Vector2(rect.get_center().x - 8, rect.end.y - 3), Vector2(rect.position.x, rect.end.y - 11)])
		draw_colored_polygon(shape, CARD_INK)
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = CARD_INK
		style.corner_radius_top_left = int(rect.size.x * 0.48)
		style.corner_radius_top_right = int(rect.size.x * 0.48)
		draw_style_box(style, rect)
	_text_fit(value, rect.grow(-2), 28 if rect.size.x > 35 else 25, ink, HORIZONTAL_ALIGNMENT_CENTER, true)

func _stats(center: Vector2, small: bool = false) -> void:
	var side := 29.0 if small else 40.0
	var gap := 5.0 if small else 8.0
	var attack_base := base_attack if base_attack >= 0 else int(spec.get("attack", 0))
	var health_base := base_health if base_health >= 0 else int(spec.get("health", 0))
	var health_cap := max_health if max_health >= 0 else health_base
	var attack_ink := GREEN if _attack() > attack_base else RED if _attack() < attack_base else PRINT
	var health_ink := RED if _health() < health_cap else GREEN if _health() > health_base else PRINT
	_stat_rect(Rect2(center + Vector2(-side * 1.5 - gap, -side * 0.5), Vector2(side, side)), str(_attack()), attack_ink)
	_stat_rect(Rect2(center + Vector2(side * 0.5 + gap, -side * 0.5), Vector2(side, side)), str(_health()), health_ink, true)
	var rect := Rect2(center - Vector2.ONE * side * 0.5, Vector2.ONE * side)
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_INK
	style.set_corner_radius_all(4)
	draw_style_box(style, rect)
	_class_icon(rect.grow(-6), _unit_kind(), PRINT)

func _icon_line(points: PackedVector2Array, rect: Rect2, color: Color, width: float = 2.0, filled: bool = false) -> void:
	var result := PackedVector2Array()
	for point in points: result.append(rect.get_center() + point * rect.size * 0.5)
	if filled: draw_colored_polygon(result, color)
	else: draw_polyline(result, color, width, true)

func _class_icon(rect: Rect2, kind: String, color: Color) -> void:
	match kind:
		"field":
			draw_colored_polygon(PackedVector2Array([rect.position+Vector2(rect.size.x/2,0),rect.end,rect.position+Vector2(0,rect.size.y)]),color)
		"order", "counter":
			_text_fit("!" if kind == "order" else "?",rect.grow(3),int(rect.size.y*1.5),color,HORIZONTAL_ALIGNMENT_CENTER,true)
		"tank":
			_icon_line(PackedVector2Array([Vector2(-0.95,0.15),Vector2(-0.5,-0.12),Vector2(0.5,-0.12),Vector2(0.95,0.3),Vector2(0.66,0.7),Vector2(-0.65,0.7)]), rect, color, 2, true)
			_icon_line(PackedVector2Array([Vector2(-0.25,-0.2),Vector2(-0.2,-0.62),Vector2(0.35,-0.62),Vector2(0.55,-0.1)]), rect, color, 2, true)
			_icon_line(PackedVector2Array([Vector2(0.28,-0.5),Vector2(0.96,-0.68)]), rect, color, 3)
		"artillery":
			draw_circle(rect.get_center()+Vector2(-rect.size.x*0.17,rect.size.y*0.2),rect.size.x*0.24,color)
			draw_circle(rect.get_center()+Vector2(-rect.size.x*0.17,rect.size.y*0.2),rect.size.x*0.09,CARD_INK)
			_icon_line(PackedVector2Array([Vector2(-0.65,0.12),Vector2(0.8,-0.73)]),rect,color,4)
			_icon_line(PackedVector2Array([Vector2(-0.15,0.18),Vector2(0.77,0.7)]),rect,color,2)
		"fighter", "bomber":
			var span := 0.85 if kind == "fighter" else 1.0
			_icon_line(PackedVector2Array([Vector2(0,-1),Vector2(0.14,-0.18),Vector2(span,0.17),Vector2(span,0.38),Vector2(0.13,0.19),Vector2(0.11,0.64),Vector2(0.42,0.84),Vector2(0.42,1),Vector2(0,0.86),Vector2(-0.42,1),Vector2(-0.42,0.84),Vector2(-0.11,0.64),Vector2(-0.13,0.19),Vector2(-span,0.38),Vector2(-span,0.17),Vector2(-0.14,-0.18)]),rect,color,2,true)
			if kind == "bomber":
				for side in [-1,1]: _icon_line(PackedVector2Array([Vector2(side*0.5,-0.24),Vector2(side*0.5,0.45)]),rect,color,2)
		"infantry":
			draw_circle(rect.get_center()+Vector2(rect.size.x*0.05,-rect.size.y*0.34),rect.size.x*0.13,color)
			_icon_line(PackedVector2Array([Vector2(0.08,-0.35),Vector2(-0.05,0.2),Vector2(-0.4,0.86)]),rect,color,3.4)
			_icon_line(PackedVector2Array([Vector2(-0.05,0.15),Vector2(0.3,0.8)]),rect,color,3.0)
			_icon_line(PackedVector2Array([Vector2(0,-0.23),Vector2(-0.48,0.14),Vector2(0.6,-0.28)]),rect,color,2.4)
			_icon_line(PackedVector2Array([Vector2(-0.5,0.32),Vector2(0.82,-0.55)]),rect,color,1.6)
		_:
			_icon_line(PackedVector2Array([Vector2(-0.65,-0.82),Vector2(0.65,-0.82),Vector2(0.65,0.82),Vector2(-0.65,0.82),Vector2(-0.65,-0.82)]),rect,color,1.5)
			for y in [-0.35,0.0,0.35]: _icon_line(PackedVector2Array([Vector2(-0.35,y),Vector2(0.35,y)]),rect,color,1.2)

func _rules_text() -> String:
	var source := [spec,subtitle]
	if source != _rules_source:
		_rules_source = source.duplicate(true)
		_rules_cache = _make_rules_text()
		_keyword_labels = CardRuntime.keyword_labels(spec)
		_keyword_labels.sort_custom(func(a,b):return a.length()>b.length())
	return _rules_cache

func _make_rules_text() -> String:
	if subtitle.is_empty() and not CardRuntime.custom_rules_text(spec).is_empty(): return CardRuntime.custom_rules_text(spec)
	var rule := _ability_text(subtitle if not subtitle.is_empty() else CardRuntime.short_rules_text(spec))
	if not _is_unit(): rule = rule.trim_prefix("部署：").trim_prefix("登场：")
	if spec.get("kind") == "counter":
		rule = rule.replace("伏置：", "").replace("触发一次。", "：").replace("触发时：", "")
		if spec.get("counter_trigger") == "enemy_order_played": rule = rule.replace("取消本次指令或总部攻击", "取消该指令")
		elif spec.get("counter_trigger") == "enemy_hq_attacked": rule = rule.replace("取消本次指令或总部攻击", "取消该次攻击")
	return rule

func _rules_has_orphan_tail(value: String, font: Font, fs: int) -> bool:
	if Typography.is_latin(value): return false
	for paragraph in value.split("\n",false):
		var wrapped := _wrap(paragraph,font,RULES_WIDTH,fs)
		if wrapped.size()>1 and wrapped.back().strip_edges().length()<=2: return true
	return false

func rules_layout() -> Dictionary:
	# Measure in printed-card coordinates so collection cards and enlarged
	# inspectors keep exactly the same text wrapping and proportions.
	var rule := _rules_text()
	if _is_order_face():
		var paragraphs := PackedStringArray()
		for paragraph in rule.replace("\r\n","\n").replace("\r","\n").split("\n"):
			# Display-only cleanup: generated indentation must not push the next
			# effect inward. The saved description and mechanics are untouched.
			while not paragraph.is_empty() and paragraph.left(1) in [" ","\t","　"," "]: paragraph = paragraph.substr(1)
			paragraphs.append(paragraph.strip_edges())
		rule = "\n".join(paragraphs)
	var font := Typography.font_for(rule,get_theme_default_font())
	var key := rule + "|" + str(font.get_instance_id()) + str(choice_mode) + str(spec.get("kind"))
	if _is_order_face(): key += str(spec.get("name","")) + str(spec.get("appearance",{}).get("name_break",0))
	if _rules_layout_cache.get("key") == key: return _rules_layout_cache
	# A drawn card has a source, a reading display and a 3D capture. Their
	# printed layout is identical; shape long CJK descriptions only once.
	if _shared_rules_layouts.has(key):
		_rules_layout_cache = _shared_rules_layouts[key]
		return _rules_layout_cache
	var available := 235.0 if choice_mode else UNIT_RULES_HEIGHT if _is_unit() else 72.0 if _is_order_face() else RULES_HEIGHT
	var fs := 17 if _is_order_face() else RULES_FONT_MAX
	var lines := _wrap(rule,font,RULES_WIDTH,fs)
	var line_height := maxf(ceilf(font.get_height(fs)),fs+2)
	while fs > RULES_FONT_MIN and (lines.size()*line_height > available or _rules_has_orphan_tail(rule,font,fs)):
		fs -= 1
		lines = _wrap(rule,font,RULES_WIDTH,fs)
		line_height = maxf(ceilf(font.get_height(fs)),fs+2)
	# 0.9 gives artwork a larger surface; long rules still fit or open in details.
	if _is_order_face():
		for i in lines.size(): lines[i] = lines[i].strip_edges().trim_prefix("　")
	var rect := Rect2(19,78 if choice_mode else 247 if _is_unit() else 276 if _is_order_face() else 270,RULES_WIDTH,available)
	var art_bottom: float = _order_title_layout().rect.position.y-20.0 if _is_order_face() else 218.0
	_rules_layout_cache = {"key":key,"rect":rect,"font_size":fs,"line_height":line_height,"lines":lines,"overflow":lines.size()*line_height>available,"art_bottom":art_bottom}
	if _shared_rules_layouts.size() >= RULES_LAYOUT_CACHE_LIMIT: _shared_rules_layouts.erase(_shared_rules_layouts.keys()[0])
	_shared_rules_layouts[key] = _rules_layout_cache
	return _rules_layout_cache

func _rules(layout: Dictionary) -> void:
	var font := Typography.font_for(_rules_text(),get_theme_default_font())
	var rect: Rect2 = layout.rect
	var fs: int = layout.font_size
	var lines: Array = layout.lines
	var line_height: float = layout.line_height
	var count := mini(lines.size(),int(rect.size.y/line_height))
	for i in count:
		var line: String = lines[i]
		if i == count - 1 and lines.size() > count: line = _ellipsize(line + "…", font, rect.size.x, fs)
		_draw_rule_line(line,Rect2(rect.position+Vector2(0,i*line_height),Vector2(rect.size.x,line_height)),fs)

func rarity_rect() -> Rect2:
	var count := 1 if spec.get("kind")=="hq" else DeckRules.limit(spec)
	var width := count * 7 + (count - 1) * 3
	return Rect2(126-width*0.5-8,357,width+16,13)

func _rarity() -> void:
	var count := 1 if spec.get("kind")=="hq" else DeckRules.limit(spec)
	var rect := rarity_rect()
	for i in count:
		draw_rect(Rect2(rect.position+Vector2(8+i*10,2),Vector2(7,8)), Color("ece0b9"))

func _draw_full_card() -> void:
	_frame(FULL_CARD_SIZE)
	var layout:=rules_layout()
	if choice_mode:
		_header();_rules(layout);return
	var art_bottom: float = layout.art_bottom
	_blank_art(printed_art_rect())
	if _art_fade == null:
		_art_fade=GradientTexture2D.new();_art_fade.gradient=Gradient.new()
		_art_fade.gradient.set_color(0,Color(0.025,0.05,0.07,0));_art_fade.gradient.set_color(1,Color(0.025,0.05,0.07,0.55))
		_art_fade.fill_to=Vector2(0,1)
	draw_texture_rect(_art_fade,Rect2(3,art_bottom-26,246,28),false)
	_header()
	if _is_unit():_stats(Vector2(126,218))
	elif spec.get("kind")=="hq":_stat_rect(Rect2(108,203,36,36),str(spec.health),PRINT,true)
	else:
		var marker:=Rect2(111,art_bottom-15,30,32)
		draw_rect(marker,CARD_INK)
		_class_icon(marker.grow(-5),str(spec.kind),PRINT)
	_rules(layout);_rarity()
	if hand_mode and can_act and not disabled:
		# A fixed light remains exposed in the hand fan, above artwork and header.
		draw_style_box(_playable_strip(),Rect2(8,3,FULL_CARD_SIZE.x-16,4))
	if disabled:draw_rect(Rect2(4,3,244,347),Color(0.06,0.1,0.14,0.18))

func printed_art_rect() -> Rect2:
	if compact:return Rect2(3,35,124,132)
	return Rect2(3,35,246,183) if _is_unit() else Rect2(3,3,246,float(rules_layout().art_bottom)-3)

func _faction_emblem(rect: Rect2) -> void:
	if FactionCatalog.info(spec).is_empty(): return
	if faction_icon != null: draw_texture_rect(faction_icon, rect, false)
	else:
		draw_rect(rect, FactionCatalog.color_for(spec).darkened(0.3))
		_text_fit(str(FactionCatalog.info(spec).name).left(1), rect, int(rect.size.y * 0.7), PRINT, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_field_card() -> void:
	_frame(FIELD_BODY)
	_blank_art(Rect2(3,35,124,132))
	draw_rect(Rect2(3,3,124,32), SinCatalog.color_for(spec).darkened(0.16))
	_faction_emblem(Rect2(104,11,14,15))
	var fee := Rect2(8,4,23,29)
	_text_fit(str(_operation_cost()), fee, 22, Color("e4c762") if can_act and not disabled else Color("b8b8aa"), HORIZONTAL_ALIGNMENT_CENTER)
	_draw_title(Rect2(34,5,67,27),13,9)
	if _is_unit(): _stats(Vector2(65,156),true)
	_draw_effect_rail()
	if disabled: draw_rect(Rect2(4,3,121,171),Color(0.13,0.15,0.12,0.17))

func effect_badges() -> Array:
	var badges := field_effects.duplicate(true)
	if current_armor > 0: badges.push_front({"id":"armor","mark":str(current_armor),"label":"重甲 %d" % current_armor})
	var counter_names: Array = current_custom_stacks.keys();counter_names.sort()
	for name in counter_names:
		if int(current_custom_stacks[name])>0:badges.append({"id":"stack_"+name,"mark":str(current_custom_stacks[name]),"label":"%s · %d层" % [name,int(current_custom_stacks[name])]})
	var timing := {"on_death":["†","阵亡"],"own_turn_start":["↻","回合开始"],"own_turn_end":["↺","回合结束"]}
	for ability in spec.get("abilities", []):
		var trigger: String = ability.trigger
		if timing.has(trigger) and not badges.any(func(b): return b.id==trigger):
			badges.append({"id":trigger,"mark":timing[trigger][0],"label":timing[trigger][1]})
	return badges

func _draw_effect_rail() -> void:
	var badges := effect_badges()
	for index in mini(badges.size(),6):
		var badge: Dictionary = badges[index]
		var rect := Rect2(128,39+index*22,20,21)
		draw_rect(rect,CARD_INK)
		var mark: String = "+" if index==5 and badges.size()>6 else str(badge.mark)
		_text_fit(mark,rect,14,GOLD if badge.id=="armor" else PRINT,HORIZONTAL_ALIGNMENT_CENTER,true)

func _draw_rule_line(line: String, rect: Rect2, fs: int, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var font:=Typography.font_for(_rules_text(),get_theme_default_font())
	var keyword_font := Typography.weighted_font(font,0.65)
	var labels:=_keyword_labels
	var runs:=[];var offset:=0;var width:=0.0
	while offset<line.length():
		var label:=""
		for candidate in labels:
			if line.substr(offset).begins_with(candidate): label=candidate;break
		var value:=label
		if label.is_empty():
			var end:=offset+1
			while end<line.length():
				var next_keyword:=false
				for candidate in labels:
					if line.substr(end).begins_with(candidate):next_keyword=true;break
				if next_keyword:break
				end+=1
			value=line.substr(offset,end-offset)
		var face: Font=keyword_font if not label.is_empty() else font
		var advance:=face.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
		runs.append({"value":value,"font":face,"width":advance});width+=advance;offset+=value.length()
	var inset := maxf(0,(rect.size.x-width)/2) if alignment == HORIZONTAL_ALIGNMENT_CENTER else 0.0
	var pos:=Vector2(rect.position.x+inset,rect.position.y+(rect.size.y-font.get_height(fs))/2+font.get_ascent(fs))
	for run in runs:
		draw_string(run.font,pos,run.value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,PRINT);pos.x+=run.width
