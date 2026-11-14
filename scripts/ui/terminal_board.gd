class_name TerminalBoard
extends Control
## The pale board behind secondary pages: a soft grey field with faint specks, a vignette and a large outlined page
## code in the corner (LB, WS, ...). Dark slabs sit on top of it; text placed straight on it uses ChaoUI.INK.
const PAGE_CODES := {"network": ["BT", "BATTLE · LOBBY"], "library": ["LB", "CARD · LIBRARY"], "workshop": ["WS", "CARD · WORKSHOP"],
	"keywords": ["CX", "KEYWORD · CODEX"], "settings": ["ST", "SYSTEM · SETTINGS"], "profile": ["PF", "COMMANDER · PROFILE"],
	"statistics": ["AN", "BATTLE · ANALYSIS"]}
var page := ""
var _specks := PackedVector2Array()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_scatter)
	_scatter()

func set_page(next: String) -> void:
	page = next
	visible = PAGE_CODES.has(page)
	queue_redraw()

func _scatter() -> void:
	var noise := RandomNumberGenerator.new()
	noise.seed = 1107
	_specks.clear()
	for i in int(size.x * size.y / 2600.0):
		_specks.append(Vector2(noise.randf() * size.x, noise.randf() * size.y))
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color("dededb"))
	# Brighter middle, darker rim.
	var centre := size * Vector2(0.48, 0.42)
	var reach := size.length() * 0.62
	for ring in 12:
		var t := float(ring) / 11.0
		draw_circle(centre, reach * (1.0 - t * 0.85), Color(0.97, 0.97, 0.96, 0.11))
	for point in _specks: draw_rect(Rect2(point, Vector2(1.2, 1.2)), Color(0, 0, 0, 0.14))
	# Hairline frame like a terminal screen.
	draw_rect(Rect2(Vector2(10, 10), size - Vector2(20, 20)), Color(0, 0, 0, 0.08), false, 1.0)
	var code: Array = PAGE_CODES.get(page, [])
	if code.is_empty(): return
	var font := ChaoUI.display_font()
	var box := Rect2(Vector2(size.x - 470, 104), Vector2(330, 330))
	draw_rect(box, Color(1, 1, 1, 0.7), false, 12.0)
	draw_string(font, box.position + Vector2(0, 222), str(code[0]), HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 178, Color(1, 1, 1, 0.72))
	draw_string(font, box.position + Vector2(0, 290), str(code[1]), HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 24, Color(1, 1, 1, 0.8))
