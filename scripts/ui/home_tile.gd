class_name HomeTile
extends Button
## One tile of the home menu board: a large condensed English title over a Chinese caption, drawn as a flat slab.
## kind: "light" (pale slab, dark ink), "dark", "cyan" (the highlighted tile). A tile may carry a big count on its
## left (the battle tile shows the deck size), a top strip and a bottom bar in orange, and a faint line icon.
var en := ""
var zh := ""
var note := ""
var kind := "light"
var count := ""
var count_caption := ""
var chip := ""
var strip := false
var bar := false
var glyph := ""
var title_size := 60
## Small tiles (EMOTE, SCENE, ...) pack title and caption tightly.
var compact := false

func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

func _fill() -> Color:
	var colour: Color = {"light": ChaoUI.SLAB_LIGHT, "dark": Color("25282d"), "cyan": ChaoUI.CYAN}.get(kind, ChaoUI.SLAB_LIGHT)
	if is_pressed() or button_pressed: return colour.darkened(0.12)
	if is_hovered(): return colour.lightened(0.08) if kind != "light" else Color.WHITE
	return colour

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(Rect2(Vector2(4, 8), size), Color(0, 0, 0, 0.35))
	draw_rect(rect, _fill())
	# Fine diagonal hatching gives the slabs their printed texture.
	var hatch := Color(0, 0, 0, 0.03) if kind == "light" else Color(1, 1, 1, 0.04)
	var step := 11.0
	var x := -size.y
	while x < size.x:
		draw_line(Vector2(x, size.y), Vector2(x + size.y, 0), hatch, 1.0)
		x += step
	var ink := ChaoUI.INK if kind == "light" else ChaoUI.TEXT
	var sub := ChaoUI.INK_MUTED if kind == "light" else (Color("d7f0ff") if kind == "cyan" else ChaoUI.MUTED)
	var font := ChaoUI.display_font()
	var body := get_theme_default_font()
	var left := 14.0 if compact else 24.0
	if not count.is_empty():
		var block := Rect2(0, 0, minf(230.0, size.x * 0.33), size.y)
		draw_rect(block, Color("2b2e33"))
		draw_string(font, Vector2(26, size.y * 0.62), count, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size.y * 0.52), ChaoUI.TEXT)
		draw_line(Vector2(26, size.y * 0.72), Vector2(block.size.x - 40, size.y * 0.72), Color("8a8e94"), 1.0)
		draw_string(font, Vector2(26, size.y * 0.72 + 24), count_caption, HORIZONTAL_ALIGNMENT_LEFT, block.size.x - 40, 18, Color("c9cdd2"))
		left = block.size.x + 30.0
	if not glyph.is_empty():
		var texture := ChaoUI.icon(glyph)
		if texture != null:
			var side := minf(size.y * 0.9, 150.0)
			draw_texture_rect(texture, Rect2(Vector2(size.x - side * 0.82, size.y - side * 0.78), Vector2(side, side)), false, Color(ink, 0.09))
	var top := 9.0 if compact else 22.0
	if strip:
		draw_rect(Rect2(0, 0, size.x, 5), ChaoUI.ORANGE)
	var title_px := mini(title_size, int(size.y * 0.42))
	draw_string(font, Vector2(left, top + title_px * 0.86), en, HORIZONTAL_ALIGNMENT_LEFT, size.x - left - 16, title_px, ink)
	draw_string(body, Vector2(left + 2, top + title_px + (14 if compact else 22)), zh, HORIZONTAL_ALIGNMENT_LEFT, size.x - left - 16, 12 if compact else 15, sub)
	if not chip.is_empty():
		var chip_y := top + title_px + 40
		var chip_width := body.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18
		draw_rect(Rect2(left + 2, chip_y, chip_width, 22), Color("222222") if kind == "light" else Color("ffffff"))
		draw_string(body, Vector2(left + 11, chip_y + 16), chip, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ChaoUI.TEXT if kind == "light" else ChaoUI.INK)
		draw_string(body, Vector2(left + chip_width + 12, chip_y + 16), note, HORIZONTAL_ALIGNMENT_LEFT, size.x - left - chip_width - 30, 13, sub)
	elif not note.is_empty():
		draw_string(body, Vector2(left + 2, top + title_px + 44), note, HORIZONTAL_ALIGNMENT_LEFT, size.x - left - 16, 13, sub)
	if bar:
		var start := 0.0 if count.is_empty() else minf(230.0, size.x * 0.33)
		draw_rect(Rect2(start, size.y - 7, size.x - start, 7), ChaoUI.ORANGE)
	if has_focus():
		draw_rect(rect.grow(-2), ChaoUI.CYAN, false, 2.0)
