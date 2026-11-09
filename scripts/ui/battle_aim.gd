extends Control
## Board-space interaction ink; never decides whether an action is legal.
var origin := Vector2.ZERO
var pointer := Vector2.ZERO
var destination := Rect2()
var region := Rect2()
var insertion := Rect2()
var legal_rects: Array = []
var active := false
var valid := false
var attack := false
var rendered_end := Vector2.ZERO
var was_active := false
var hint := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 65

func _process(delta: float) -> void:
	if active:
		var endpoint := destination.get_center() if valid and destination.has_area() else pointer
		# Ease only the target snap. Free pointing stays attached to mouse/finger.
		rendered_end = rendered_end.lerp(endpoint,1-exp(-40*delta)) if was_active and valid and destination.has_area() else endpoint
		queue_redraw()
	was_active = active

func _draw() -> void:
	if not active and legal_rects.is_empty() and not region.has_area() and not insertion.has_area() and hint.is_empty(): return
	var ink := Color("d76a59") if attack else Color("d2d2d2")
	for rect in legal_rects:
		_corners(rect.grow(4),Color(ink,0.5),2)
	if region.has_area():
		draw_rect(region,Color(ink,0.055))
		_corners(region.grow(-3),Color(ink,0.55),2)
	if insertion.has_area():
		draw_rect(insertion.grow(3),Color(ink,0.22))
		draw_rect(insertion,ink)
	if not hint.is_empty():
		var font:=get_theme_default_font()
		var width:=font.get_string_size(hint,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x
		var position:=Vector2(clampf(origin.x,100,size.x-100),maxf(48,origin.y-22))
		draw_style_box(ChaoUI.style(Color("181818dd"),Color.TRANSPARENT,8,0),Rect2(position-Vector2(width/2+12,25),Vector2(width+24,35)))
		draw_string(font,position-Vector2(width/2,0),hint,HORIZONTAL_ALIGNMENT_LEFT,-1,17,ink)
	if not active: return
	var end := rendered_end
	var direction := end-origin
	if direction.length()<24: return
	var normal := direction.normalized().orthogonal()
	var bend := minf(85,direction.length()*0.16)
	var mid := (origin+end)*0.5+normal*bend
	var points := PackedVector2Array()
	for i in 33:
		var t := float(i)/32.0
		points.append(origin.lerp(mid,t).lerp(mid.lerp(end,t),t))
	var color := ink if valid else Color("9c937d")
	draw_polyline(points,Color(0,0,0,0.45),15,true)
	draw_polyline(points,Color(color,0.95 if valid else 0.7),9,true)
	var tangent := (end-points[29]).normalized()
	var side := tangent.orthogonal()
	draw_colored_polygon(PackedVector2Array([end+tangent*9,end-tangent*29+side*17,end-tangent*22,end-tangent*29-side*17]),color)
	draw_arc(origin,9,0,TAU,32,Color(color,0.9),2,true)
	if valid and destination.has_area():
		_corners(destination.grow(5),Color(ink,0.8),3)
		draw_arc(end,22,0,TAU,40,Color(ink,0.6),1.5,true)

func _corners(rect: Rect2,color: Color,width: float) -> void:
	for corner in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
		var dx := 1.0 if corner.x==rect.position.x else -1.0
		var dy := 1.0 if corner.y==rect.position.y else -1.0
		draw_polyline(PackedVector2Array([corner+Vector2(dx*16,0),corner,corner+Vector2(0,dy*16)]),color,width,true)
