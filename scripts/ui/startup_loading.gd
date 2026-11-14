extends Control
## Start-up connection screen. Layout and motion follow the open-source ak-ui loading screen (MIT, YunYouJun/ak-ui,
## itself derived from mashirozx/arknights-ui): a teal field with dark top and bottom fades, a tip line in the top left,
## the title block right of centre, and at 69.72% height a thin white track along which a rounded square runs out,
## growing and turning, and back, every five seconds. No artwork or fonts from those projects are used.
signal continue_requested
signal retry_requested

const TEAL := Color("016d8d")
const TRACK_SECONDS := 5.0
const FADE_SECONDS := 0.42
const TIPS := [
	"卡库在启动时自动更新，离线时使用本地缓存。",
	"做好的卡在工坊打包，测试后一次提交。",
	"主界面的角色可以拖动摆放，滚轮缩放，双击复原。",
	"对局中总部格的角色可以在 设置 → 角色 里关闭。",
	"网络较慢时，可以先使用本地数据进入，更新会在后台继续。",
	"点击主界面的角色，会有不同的反应。",
]

var labels: Dictionary = {}
## Data source of the progress (one step per finished stage).
var progress_bar: ProgressBar
var continue_button: Button
var retry_button: Button
var note: Label
var _started := 0
var _finished := false
var _time := 0.0
var _tip_label: Label
var _tip := 0
var _brand: Control
var _mark: Control
var _progress: Control
var _runner_box := StyleBoxFlat.new()

func _ready() -> void:
	z_index = 1000
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); mouse_filter = Control.MOUSE_FILTER_STOP
	theme = ChaoUI.make_theme(OS.has_feature("mobile"))
	progress_bar = ProgressBar.new(); progress_bar.max_value = 3; progress_bar.visible = false; add_child(progress_bar)
	_runner_box.bg_color = Color.WHITE; _runner_box.anti_aliasing = true
	# Tip, top left.
	_tip = randi() % TIPS.size()
	_tip_label = _plain("Tips: " + TIPS[_tip]); _tip_label.add_theme_color_override("font_color", Color.WHITE)
	_tip_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65)); _tip_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_tip_label)
	# Title block: brand text and the mark beside it.
	_brand = VBoxContainer.new(); _brand.add_theme_constant_override("separation", 0); _brand.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_brand)
	var title := ChaoUI.display(_plain("CHAO TACTICAL TERMINAL"), 64, Color.WHITE); title.name = "Brand"; _brand.add_child(title)
	title.add_theme_font_override("font", ChaoUI.display_italic())
	var subtitle := ChaoUI.display(_plain("巢战 · 都市作战终端"), 22, Color.WHITE); subtitle.name = "Subtitle"; _brand.add_child(subtitle)
	subtitle.add_theme_font_override("font", ChaoUI.display_italic())
	# The mark is drawn by this screen (see _draw): an outlined hexagon, the "巢" glyph and a caption.
	_mark = Control.new(); _mark.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_mark)
	# Progress: the track is drawn; stages, note and buttons sit under it.
	_progress = VBoxContainer.new(); _progress.add_theme_constant_override("separation", 8); _progress.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_progress)
	var stages := HBoxContainer.new(); stages.alignment = BoxContainer.ALIGNMENT_CENTER; stages.add_theme_constant_override("separation", 28); _progress.add_child(stages)
	for key in ["cards", "emotes", "update"]:
		var label := Label.new(); label.text = {"cards": "卡库 · 同步中", "emotes": "表情 · 准备中", "update": "版本 · 检查中"}[key]
		label.add_theme_font_size_override("font_size", 13); label.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
		labels[key] = label; stages.add_child(label)
	note = _plain("正在连接都市终端……"); note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color.WHITE); note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _progress.add_child(note)
	var buttons := HBoxContainer.new(); buttons.alignment = BoxContainer.ALIGNMENT_CENTER; buttons.add_theme_constant_override("separation", 10); _progress.add_child(buttons)
	retry_button = Button.new(); retry_button.text = "重试"; ChaoUI.skin_light_button(retry_button); retry_button.visible = false; buttons.add_child(retry_button)
	retry_button.pressed.connect(func(): retry_requested.emit())
	continue_button = Button.new(); continue_button.text = "使用本地数据进入"; ChaoUI.skin_light_button(continue_button); continue_button.visible = false; buttons.add_child(continue_button)
	continue_button.pressed.connect(func(): continue_requested.emit())
	resized.connect(_layout)
	_layout.call_deferred()
	_started = Time.get_ticks_msec()

func _plain(text: String) -> Label:
	var label := Label.new(); label.text = text; label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _portrait() -> bool:
	return size.y > size.x and size.x < 896

## Track width: min(38.333% of the width, 528 px); in portrait 68% of the width.
func _track() -> Rect2:
	var width := size.x * 0.68 if _portrait() else minf(size.x * 0.38333, 528.0)
	var y := size.y * (0.66 if _portrait() else 0.6972)
	return Rect2(Vector2((size.x - width) / 2, y - 1), Vector2(width, 2))

func _runner_sizes() -> Vector2:
	if _portrait(): return Vector2(size.x * 0.11, size.x * 0.11)
	return Vector2(clampf(size.x * 0.04167, 40, 60), clampf(size.x * 0.10417, 100, 150))

func _layout() -> void:
	if not is_instance_valid(_brand): return
	var w := size.x; var h := size.y
	_tip_label.position = Vector2(w * 0.007 + 8, h * 0.011 + 4)
	_tip_label.add_theme_font_size_override("font_size", int(clampf(h * 0.02, 12, 18)))
	var title: Label = _brand.get_node("Brand"); var subtitle: Label = _brand.get_node("Subtitle")
	if _portrait():
		title.add_theme_font_size_override("font_size", int(clampf(w * 0.11, 32, 51)))
		subtitle.add_theme_font_size_override("font_size", int(clampf(w * 0.04, 13, 18)))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_brand.size = Vector2(w * 0.84, 0); _brand.reset_size(); _brand.position = Vector2(w * 0.08, h * 0.35)
		_mark.visible = false
	else:
		title.add_theme_font_size_override("font_size", int(clampf(w * 0.0465, 45, 67)))
		subtitle.add_theme_font_size_override("font_size", int(clampf(w * 0.0175, 16, 26)))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		# Identity block: from 36.25% to 96% of the width at 35% height; the mark takes 18% of the width on the right.
		var mark_size := w * 0.18
		var left := w * 0.3625
		var right := w * 0.96
		_brand.reset_size()
		_brand.position = Vector2(left, h * 0.35 + h * 0.02 + (mark_size * 0.86 - _brand.size.y) / 2)
		_mark.visible = true
		_mark.custom_minimum_size = Vector2(mark_size * 1.27, mark_size * 0.86); _mark.size = _mark.custom_minimum_size
		_mark.position = Vector2(right - mark_size - w * 0.031 - mark_size * 0.135, h * 0.35)
	var track := _track()
	_progress.size = Vector2(maxf(track.size.x, 460), 0); _progress.reset_size()
	_progress.position = Vector2((w - _progress.size.x) / 2, track.position.y + _runner_sizes().y / 2 + 24)

func _process(delta: float) -> void:
	_time += delta
	if not _finished and Time.get_ticks_msec() - _started > 8000 and not continue_button.visible:
		continue_button.visible = true; note.text = "网络较慢，可以先使用本地数据进入，更新会在后台继续。"
	if int(_time / 5.0) != int((_time - delta) / 5.0):
		_tip = (_tip + 1) % TIPS.size(); _tip_label.text = "Tips: " + TIPS[_tip]
	queue_redraw()

## CSS "ease", cubic-bezier(0.25, 0.1, 0.25, 1).
static func _ease(x: float) -> float:
	var lo := 0.0; var hi := 1.0; var t := x
	for i in 18:
		t = (lo + hi) / 2
		var bx := 3 * (1 - t) * (1 - t) * t * 0.25 + 3 * (1 - t) * t * t * 0.25 + t * t * t
		if bx < x: lo = t
		else: hi = t
	return 3 * (1 - t) * (1 - t) * t * 0.1 + 3 * (1 - t) * t * t * 1.0 + t * t * t

func _draw() -> void:
	var w := size.x; var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), TEAL)
	# Horizontal wash, then the dark fades at the top (to 18%) and bottom (from 72%).
	_gradient(Rect2(0, 0, w * 0.42, h), Color(0, 0.27, 0.38, 0.08), Color(0, 0.44, 0.59, 0.28), true)
	_gradient(Rect2(w * 0.42, 0, w * 0.58, h), Color(0, 0.44, 0.59, 0.28), Color(0, 0.07, 0.11, 0.24), true)
	_gradient(Rect2(0, 0, w, h * 0.18), Color(0, 0.027, 0.043, 0.9), Color(0, 0.027, 0.043, 0), false)
	_gradient(Rect2(0, h * 0.72, w, h * 0.28), Color(0, 0.027, 0.043, 0), Color(0, 0.027, 0.043, 0.96), false)
	# The track and its runner.
	var track := _track()
	draw_rect(track, Color.WHITE)
	var sizes := _runner_sizes()
	var phase := fmod(_time, TRACK_SECONDS) / TRACK_SECONDS
	var along := 0.0; var grow := 0.0; var turn := 0.0
	if phase < 0.5:
		var p := _ease(phase / 0.5); along = p; grow = p; turn = p * deg_to_rad(450)
	elif phase < 0.75:
		along = 1.0; grow = 1.0; turn = deg_to_rad(450)
	else:
		var p := _ease((phase - 0.75) / 0.25); along = 1.0 - p; grow = 1.0 - p; turn = (1.0 - p) * deg_to_rad(450)
	var side := lerpf(sizes.x, sizes.y, grow)
	var centre := Vector2(track.position.x + track.size.x * along, track.get_center().y)
	_runner_box.set_corner_radius_all(int(side * 0.3)); _runner_box.corner_detail = 8
	draw_set_transform(centre, turn, Vector2.ONE)
	draw_style_box(_runner_box, Rect2(-side / 2, -side / 2, side, side))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# "LOADING" sits at the right end of the track in the field colour, so it only shows on the runner when the
	# runner arrives there at full size (as in the reference).
	var font := ChaoUI.display_font()
	draw_string(font, Vector2(track.end.x + sizes.y / 2 - 112, track.position.y - 35 + 16), "READY" if _finished else "LOADING", HORIZONTAL_ALIGNMENT_RIGHT, 100, 16, TEAL)
	if _mark.visible: _draw_mark(Rect2(_mark.position, _mark.size))

func _draw_mark(area: Rect2) -> void:
	var centre := area.get_center() - Vector2(0, area.size.y * 0.08)
	var radius := minf(area.size.x, area.size.y) * 0.42
	if radius < 8.0: return
	var hexagon := PackedVector2Array()
	for i in 7: hexagon.append(centre + Vector2.from_angle(PI / 6 + i * PI / 3) * radius)
	draw_polyline(hexagon, Color.WHITE, maxf(radius * 0.06, 3.0), true)
	var inner := PackedVector2Array()
	for i in 7: inner.append(centre + Vector2.from_angle(PI / 6 + i * PI / 3) * radius * 0.8)
	draw_polyline(inner, Color(1, 1, 1, 0.45), 1.5, true)
	var glyph_size := int(radius * 0.95)
	var font := get_theme_default_font()
	draw_string(font, centre + Vector2(-radius, glyph_size * 0.36), "巢", HORIZONTAL_ALIGNMENT_CENTER, radius * 2, glyph_size, Color.WHITE)
	var caption_size := int(clampf(size.x * 0.0125, 12, 18))
	draw_string(ChaoUI.display_font(), Vector2(area.position.x, centre.y + radius + caption_size + 10), "CHAO / NEST", HORIZONTAL_ALIGNMENT_CENTER, area.size.x, caption_size, Color.WHITE)

func _gradient(rect: Rect2, from: Color, to: Color, horizontal: bool) -> void:
	var points := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var colours := PackedColorArray([from, to, to, from]) if horizontal else PackedColorArray([from, from, to, to])
	draw_polygon(points, colours)

func stage(key: String, text: String, ok: bool) -> void:
	if not labels.has(key): return
	labels[key].text = ("✓ " if ok else "· ") + text
	labels[key].add_theme_color_override("font_color", Color.WHITE if ok else Color("ffd6a0"))
	if not labels[key].has_meta("done"):
		labels[key].set_meta("done", true); progress_bar.value += 1

func finish(success: bool) -> void:
	_finished = true
	if success:
		note.text = "准备完成"
		# Fade out over 420 ms, as the reference screen does, then hand over.
		var tween := create_tween(); tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
		await tween.finished
		if is_inside_tree(): continue_requested.emit()
	else:
		note.text = "部分数据未能更新，本地卡库和轮盘仍可使用。"
		continue_button.visible = true; retry_button.visible = true
