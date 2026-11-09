extends Button
## Desk objects. Hidden cards use their owner's selected sin, never hidden card identities.
var kind := "back"
var value := 20
var maximum := 20
var friendly := true
var active := false
var title := ""
var faction_id := ""
var sin_id := ""
var back_icon: Texture2D
var hq_art: Texture2D
var hq_art_id := ""
var _loaded_hq_art := ""
var back_color := Color("333f33")
const PAPER := Color("e7e7e7")
const INK := Color("191919")
const GOLD := Color("d2d2d2")

func _ready() -> void:
	flat = true
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	resized.connect(queue_redraw)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if kind in ["back","deck"]:
		refresh_back()

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
		var accent:=ChaoUI.ACCENT if friendly else Color("d4a9a6")
		var name_line:=TextLine.new();name_line.add_string(title,font,15);name_line.width=w-32;name_line.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		name_line.draw_outline(get_canvas_item(),Vector2(16,11),3,Color(0,0,0,0.5))
		name_line.draw(get_canvas_item(),Vector2(16,10),ChaoUI.TEXT)
		draw_string_outline(font,Vector2(16,76),str(value),HORIZONTAL_ALIGNMENT_LEFT,66,38,3,Color(0,0,0,0.5))
		draw_string(font,Vector2(16,75),str(value),HORIZONTAL_ALIGNMENT_LEFT,66,38,accent)
		draw_string(font,Vector2(77,70),"/ "+str(maximum),HORIZONTAL_ALIGNMENT_LEFT,72,16,ChaoUI.MUTED)
		draw_string(font,Vector2(w-68,69),"指挥点",HORIZONTAL_ALIGNMENT_RIGHT,52,11,ChaoUI.MUTED)
		var width:=w-32
		draw_style_box(ChaoUI.style(Color("d2d2d218"),Color.TRANSPARENT,2,0),Rect2(16,88,width,3))
		if maximum>0:draw_style_box(ChaoUI.style(accent,Color.TRANSPARENT,2,0),Rect2(16,88,width*clampf(float(value)/maximum,0,1),3))
		return
	if kind == "end":
		var fill:=ChaoUI.ACCENT if active else Color("272727d9")
		var border:=Color("ededed") if is_hovered() and active else Color("a5a5a555")
		draw_style_box(ChaoUI.style(fill,border,12,0),Rect2(0,4,w,h-8))
		draw_string(font,Vector2(0,h/2+6),title,HORIZONTAL_ALIGNMENT_CENTER,w,18,INK if active else ChaoUI.MUTED)
		return
	if kind == "deck":
		for layer in range(5):
			var rect := Rect2(Vector2(layer * 2, layer * -2 + 10), size - Vector2(10, 18))
			_box(rect, Color("303030"), Color("757575"), 1)
		_back(Rect2(8, 2, w - 10, h - 18))
		var counter:=Rect2(w/2-22,h-34,44,27)
		_box(counter,Color("191919"),Color("999999"),1)
		draw_string(font,counter.position+Vector2(0,21),str(value),HORIZONTAL_ALIGNMENT_CENTER,counter.size.x,21,PAPER)
		return
	if kind == "back":
		_back(Rect2(Vector2.ZERO, size))
		return
	# Headquarters uses the same footprint as a unit, centered in its support row.
	_box(Rect2(Vector2(3, 4), size), Color(0, 0, 0, 0.3), Color.TRANSPARENT, 0)
	_box(Rect2(Vector2.ZERO, size), INK, Color.TRANSPARENT, 0)
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
