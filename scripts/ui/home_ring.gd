class_name HomeRing
extends Control
## The ring on the home screen: a large count inside a white circle with a yellow arc, as a level badge would be.
var value := "0"
var caption := "CARDS"
var fraction := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(130, 130)

func _draw() -> void:
	var centre := size / 2
	var radius := minf(size.x, size.y) / 2 - 12
	draw_circle(centre, radius, Color(0.04, 0.05, 0.06, 0.42))
	draw_arc(centre, radius, 0, TAU, 72, Color(1, 1, 1, 0.88), 3.0, true)
	draw_arc(centre, radius + 8, -PI / 2, -PI / 2 + TAU * clampf(fraction, 0.0, 1.0), 72, ChaoUI.YELLOW, 4.0, true)
	var font := ChaoUI.display_font()
	draw_string(font, Vector2(0, centre.y + 14), value, HORIZONTAL_ALIGNMENT_CENTER, size.x, 54, ChaoUI.TEXT)
	draw_string(font, Vector2(0, centre.y + 36), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color("cfd3d8"))
