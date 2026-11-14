extends Button
## Desk objects. Hidden cards use their owner's selected sin, never hidden card identities.
var kind := "back"
var value := 20:
	set(next):
		value = next
		if is_instance_valid(overlay): overlay.queue_redraw()
var maximum := 20
var friendly := true
var active := false:
	set(next):
		active = next
		if is_instance_valid(overlay): overlay.queue_redraw()
var title := ""
var faction_id := ""
var sin_id := ""
var back_icon: Texture2D
var hq_art: Texture2D
var hq_art_id := ""
var _loaded_hq_art := ""
## Headquarters show the player's commander character and hit points only; name and rules live in the tooltip and inspector.
var figure: CommanderFigure
var overlay: Control
var back_color := Color("333f33")
const PAPER := Color("e7e7e7")
const INK := Color("191919")
const GOLD := Color("d2d2d2")

func _ready() -> void:
	flat = true
	mouse_entered.connect(_hover_changed)
	mouse_exited.connect(_hover_changed)
	resized.connect(queue_redraw)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if kind in ["back","deck"]:
		refresh_back()

func _hover_changed() -> void:
	queue_redraw()
	if is_instance_valid(overlay): overlay.queue_redraw()

func refresh_back() -> void:
	back_color = SinCatalog.color_for({"sin":sin_id})
	back_icon = SinCatalog.icon(sin_id)
	queue_redraw()

func update_headquarters_art() -> void:
	back_color=SinCatalog.color_for({"sin":sin_id})
	if hq_art_id==_loaded_hq_art: return
	_loaded_hq_art=hq_art_id
	hq_art=null
	if CardArtCache.valid_id(hq_art_id):
		var requested:=hq_art_id
		var image: Texture2D=await CardArtCache.load_art(requested,get_tree())
		if hq_art_id==requested: hq_art=image
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	var font := get_theme_default_font()
	if kind == "credits":
		# Terminal-style counter: a dark slab with a white rule, the commander's name, a big condensed number.
		var accent:=ChaoUI.YELLOW if friendly else Color("e0594d")
		var display:=ChaoUI.display_font()
		draw_rect(Rect2(0,0,w,h-8),Color("10121580"))
		draw_rect(Rect2(0,0,3,h-8),Color.WHITE)
		var name_line:=TextLine.new();name_line.add_string(title,font,14);name_line.width=w-30;name_line.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		name_line.draw(get_canvas_item(),Vector2(16,9),ChaoUI.TEXT)
		draw_string(display,Vector2(15,79),str(value),HORIZONTAL_ALIGNMENT_LEFT,-1,52,ChaoUI.TEXT)
		var number_width:=display.get_string_size(str(value),HORIZONTAL_ALIGNMENT_LEFT,-1,52).x
		draw_string(display,Vector2(21+number_width,77),"/ "+str(maximum),HORIZONTAL_ALIGNMENT_LEFT,72,20,Color("aab0b8"))
		draw_string(display,Vector2(w-80,77),"COST",HORIZONTAL_ALIGNMENT_RIGHT,64,13,Color("8a9098"))
		draw_string(font,Vector2(w-80,58),"指挥点",HORIZONTAL_ALIGNMENT_RIGHT,64,11,Color("8a9098"))
		var width:=w-30
		draw_rect(Rect2(15,88,width,4),Color("ffffff1c"))
		if maximum>0:draw_rect(Rect2(15,88,width*clampf(float(value)/maximum,0,1),4),accent)
		return
	if kind == "end":
		# The main action of the table, in the accent colour while it is yours.
		var display:=ChaoUI.display_font()
		var fill:=ChaoUI.CYAN if active else Color("1d1f23d9")
		if active and is_hovered(): fill=fill.lightened(0.1)
		draw_rect(Rect2(4,10,w,h-8),Color(0,0,0,0.35))
		draw_rect(Rect2(0,4,w,h-8),fill)
		if active:
			draw_string(display,Vector2(16,h/2+8),"END TURN",HORIZONTAL_ALIGNMENT_LEFT,w-24,28,ChaoUI.TEXT)
			draw_string(font,Vector2(0,h/2+8),title,HORIZONTAL_ALIGNMENT_RIGHT,w-14,13,Color("d7f0ff"))
		else:
			draw_rect(Rect2(0,4,3,h-8),Color("ffffff55"))
			draw_string(font,Vector2(0,h/2+6),title,HORIZONTAL_ALIGNMENT_CENTER,w,16,ChaoUI.MUTED)
		return
	if kind == "deck":
		for layer in range(5):
			var rect := Rect2(Vector2(layer * 2, layer * -2 + 10), size - Vector2(10, 18))
			_box(rect, Color("303030"), Color("757575"), 1)
		_back(Rect2(8, 2, w - 10, h - 18))
		var counter:=Rect2(w/2-26,h-36,52,30)
		draw_rect(counter,Color("16181c"))
		draw_rect(Rect2(counter.position,Vector2(counter.size.x,2)),Color.WHITE)
		draw_string(ChaoUI.display_font(),counter.position+Vector2(0,25),str(value),HORIZONTAL_ALIGNMENT_CENTER,counter.size.x,26,PAPER)
		return
	if kind == "back":
		_back(Rect2(Vector2.ZERO, size))
		return
	# Headquarters use the same footprint as a unit, centered in its support row.
	_box(Rect2(Vector2(3, 4), size), Color(0, 0, 0, 0.3), Color.TRANSPARENT, 0)
	_box(Rect2(Vector2.ZERO, size), INK, Color.TRANSPARENT, 0)
	if figure != null:
		var inner := Rect2(5, 5, w - 10, h - 10)
		draw_rect(inner, back_color.darkened(0.55))
		draw_rect(Rect2(inner.position.x, inner.end.y - inner.size.y * 0.45, inner.size.x, inner.size.y * 0.45), Color(back_color.darkened(0.2), 0.35))
		return
	# The character is turned off in the settings: the plain headquarters card with its name, art and hit points.
	if active:draw_circle(Vector2(w/2,17),3,GOLD)
	var art_rect:=Rect2(7,39,w-14,h-46)
	draw_rect(art_rect,back_color.lerp(Color("999999"),0.16))
	if hq_art!=null:
		var dimensions:=hq_art.get_size()
		var crop:=art_rect.size/maxf(art_rect.size.x/dimensions.x,art_rect.size.y/dimensions.y)
		draw_texture_rect_region(hq_art,art_rect,Rect2((dimensions-crop)/2,crop))
	draw_rect(Rect2(7,7,w-14,29),back_color.darkened(0.2))
	var fs:=19
	while fs>11 and font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x>w-18: fs-=1
	var shown:=title
	while shown.length()>1 and font.get_string_size(shown,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x>w-18: shown=shown.left(shown.length()-2)+"…"
	draw_string(font, Vector2(9,27), shown, HORIZONTAL_ALIGNMENT_CENTER,w-18,fs,PAPER)
	var c := Vector2(w / 2, h - 50)
	var shield := PackedVector2Array([c + Vector2(-30, -22), c + Vector2(30, -22), c + Vector2(30, 13), c + Vector2(0, 32), c + Vector2(-30, 13)])
	draw_colored_polygon(shield, INK)
	draw_string(font, c + Vector2(-30, 13), str(value), HORIZONTAL_ALIGNMENT_CENTER, 60, 34, Color("ca5d44") if value < maximum else PAPER)

func update_character(id: String) -> void:
	if not CharacterCatalog.hq_enabled():
		if figure != null:
			figure.queue_free()
			overlay.queue_free()
			figure = null
			overlay = null
			queue_redraw()
		return
	if figure == null:
		figure = CommanderFigure.new()
		figure.name = "Character"
		add_child(figure)
		overlay = Control.new()
		overlay.name = "Overlay"
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(overlay)
		overlay.draw.connect(_draw_hq_overlay)
		if not resized.is_connected(_layout_character): resized.connect(_layout_character)
		queue_redraw()
	_layout_character()
	figure.configure(id, "hq", back_color)
	overlay.queue_redraw()

func _layout_character() -> void:
	if figure == null: return
	figure.position = Vector2(5, 5)
	figure.size = size - Vector2(10, 10)
	overlay.position = Vector2.ZERO
	overlay.size = size

## Drawn above the character: the target marker, the frame edge and the hit-point badge.
func _draw_hq_overlay() -> void:
	var w := size.x
	var h := size.y
	var font := get_theme_default_font()
	var edge := StyleBoxFlat.new()
	edge.draw_center = false
	edge.set_border_width_all(2 if active or is_hovered() else 1)
	edge.border_color = GOLD if active else (Color("ededed") if is_hovered() else Color("a5a5a555"))
	edge.set_corner_radius_all(5)
	overlay.draw_style_box(edge, Rect2(Vector2.ZERO, size))
	if active: overlay.draw_circle(Vector2(w / 2, 14), 4, GOLD)
	var c := Vector2(w / 2, h - 34)
	var shield := PackedVector2Array([c + Vector2(-32, -24), c + Vector2(32, -24), c + Vector2(32, 12), c + Vector2(0, 30), c + Vector2(-32, 12)])
	overlay.draw_colored_polygon(shield, Color(INK, 0.92))
	overlay.draw_polyline(shield + PackedVector2Array([shield[0]]), back_color.lightened(0.2), 1.5, true)
	overlay.draw_string(ChaoUI.display_font(), c + Vector2(-32, 14), str(value), HORIZONTAL_ALIGNMENT_CENTER, 64, 40, Color("ff6a4d") if value < maximum else PAPER)

func _back(rect: Rect2) -> void:
	_box(rect, back_color, Color("999999"), 2)
	if back_icon != null:
		var available := rect.size * 0.56
		var dimensions := back_icon.get_size()
		var fitted := dimensions * minf(available.x/dimensions.x,available.y/dimensions.y)
		draw_texture_rect(back_icon,Rect2(rect.get_center()-fitted/2,fitted),false)

func _box(rect: Rect2, fill: Color, stroke: Color, border: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = stroke
	style.set_border_width_all(0)
	style.set_corner_radius_all(5)
	draw_style_box(style, rect)
