class_name CommanderFigure
extends Control
## Draws a commander character inside its rect: a Live2D model when the GDCubism extension and a model exist,
## otherwise the static portrait, otherwise a drawn silhouette. act() plays the reaction for a match moment.
## On the home page ("home") the figure is interactive: the model looks toward the pointer, plays an idle action now and
## then while the player is inactive, and reacts when its head or body is clicked.
## Motions crossfade into each other: the idle motion rotates through its group, and an action hands back to idle
## shortly before it ends instead of dropping to the rest pose. Live2DLife adds procedural sway and gaze on top.
const PRIORITY_IDLE := 1
const PRIORITY_NORMAL := 2
const PRIORITY_FORCE := 3
const IDLE_SECONDS := Vector2(14.0, 26.0)
## Clicks above this fraction of the frame height count as the head (the home framing puts the head in the top part).
const HEAD_LINE := 0.42
const KICK_SECONDS := {"play": 0.45, "attack": 0.4, "hit": 0.5, "turn": 0.6, "win": 1.6, "lose": 1.6}
## Seconds a layered gesture takes to blend in from, and back out to, the idle pose.
const GESTURE_BLEND := 0.35
## The next motion starts this long before the current one ends, so the two crossfade.
const MOTION_HANDOVER := 0.6
## The model is advanced by this node (manual playback), every few frames as set by the Live2D quality setting
## (CharacterCatalog.LIVE2D_QUALITY), so its motion stays in step with the frames; a figure off screen costs nothing.

var character_id := ""
var place := "home"
var tint := Color("9a8f7a")
var entry: Dictionary = {}
var portrait: Texture2D
var model: Node2D
var _kick := ""
var _kick_age := 0.0
var _expression_left := 0.0
var _idle := []
var _life: Live2DLife
## The author's VTube Studio setup, when the character ships one; it then replaces Live2DLife and the breath effect.
var _rig: VTubeRig
## Last pointer position in viewport coordinates, from mouse motion events; cleared when the pointer leaves the window.
var _pointer: Variant = null
var _pointer_rest := 0.0
## The motion currently driving the body: {"kind": "idle" | "action", "left": seconds, "group": name, "no": index}.
var _main := {}
## Home screen only: the player drags the character to move it and scrolls to resize it; double-click resets.
var layout_offset := Vector2.ZERO
var layout_zoom := 1.0
var _press: Variant = null
var _dragging := false
const DRAG_THRESHOLD := 6.0
var _idle_left := 0.0
var _last_touch := {}
## The layered gesture in progress: {"out", "back": motions, "hold", "phase", "t", "base": {id: value}, "last": {id: value}}.
var _gesture := {}
var _params := {}
var _since_step := 0.0
var _frames_since_step := 0
## When above zero, replaces STEP_FRAMES for this figure.
var step_frames := 0
var _quality_steps := 2

func _ready() -> void:
	clip_contents = not interactive()
	_update_input()
	resized.connect(_fit_model)
	var window := get_window()
	if window != null and not window.mouse_exited.is_connected(_pointer_left): window.mouse_exited.connect(_pointer_left)

func _pointer_left() -> void:
	_pointer = null

func interactive() -> bool:
	return place == "home"

func _update_input() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive() else Control.MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if interactive() else Control.CURSOR_ARROW
	_idle_left = randf_range(IDLE_SECONDS.x, IDLE_SECONDS.y)

## Rebuilding is skipped when nothing changed, so battle redraws keep the running model and its motion.
func configure(id: String, next_place: String = "home", next_tint: Color = tint) -> void:
	tint = next_tint
	if id == character_id and next_place == place and (model != null or portrait != null or entry.get("id", "") == id):
		queue_redraw()
		return
	character_id = id
	place = next_place
	entry = CharacterCatalog.info(id)
	apply_quality()
	_update_input()
	clip_contents = not interactive()
	var layout := CharacterCatalog.home_layout(id) if interactive() else {"offset": Vector2.ZERO, "zoom": 1.0}
	layout_offset = layout.offset
	layout_zoom = layout.zoom
	if is_instance_valid(model): model.queue_free()
	model = null
	_life = null
	_rig = null
	_main = {}
	_gesture = {}
	_params = {}
	portrait = null
	var model_path := CharacterCatalog.file(entry, "model")
	if CharacterCatalog.live2d_available() and not model_path.is_empty():
		model = ClassDB.instantiate("GDCubismUserModel")
		# Clip masks are rendered in SubViewports at the model's native resolution (thousands of pixels) unless capped;
		# 512 is plenty for a figure that is at most a few hundred pixels wide on screen.
		var quality: Dictionary = CharacterCatalog.LIVE2D_QUALITY[CharacterCatalog.live2d_quality()]
		model.set("mask_viewport_size", 256 if place == "hq" else int(quality.mask))
		model.set("playback_process_mode", 2)
		model.set("assets", model_path)
		var vtube := CharacterCatalog.file(entry, "vtube")
		if not vtube.is_empty(): _rig = VTubeRig.load_rig(vtube, model_path.get_base_dir())
		var effects := ["GDCubismEffectEyeBlink"] if _rig != null else ["GDCubismEffectEyeBlink", "GDCubismEffectBreath"]
		for effect in effects:
			if ClassDB.class_exists(effect): model.add_child(ClassDB.instantiate(effect))
		if _rig == null:
			# Without the author's setup: sway everywhere, and on the home page eyes, head and body follow the pointer.
			_life = Live2DLife.new()
			_life.attach(model, interactive())
		# The bundled GDCubism is patched to keep draw order as child order rather than z_index,
		# so the HQ overlay, dragged cards and dialogs still draw on top of the model.
		add_child(model)
		var idle: Variant = CharacterCatalog.action(entry, "idle").get("motion", [])
		_idle = idle if idle is Array and idle.size() in [1, 2] else []
		_start_idle()
		_fit_model()
	else:
		portrait = _texture(CharacterCatalog.file(entry, "portrait"))
	queue_redraw()

func uses_live2d() -> bool:
	return is_instance_valid(model)

func _texture(path: String) -> Texture2D:
	if path.is_empty(): return null
	if path.begins_with("res://"): return load(path) as Texture2D
	var image := Image.load_from_file(path)
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null

## The idle motion. [group] alone picks a different entry of the group each time, so idles rotate.
func _start_idle() -> void:
	if not is_instance_valid(model) or _idle.is_empty(): return
	if not _play_main(_idle, PRIORITY_FORCE, "idle"): _main = {}

## Starts a motion on the model; [group] or [group, -1] picks one of the group at random (not the one just played).
## Returns false when the model refused it (an action of the same priority is already playing) or it does not exist.
func _play_main(spec: Array, priority: int, kind: String) -> bool:
	var group := str(spec[0])
	var count := int(model.call("get_motions").get(group, 0))
	if count <= 0: return false
	var no := int(spec[1]) if spec.size() == 2 else -1
	if no < 0:
		no = randi() % count
		if count > 1 and group == _main.get("group", "") and no == int(_main.get("no", -1)): no = (no + 1) % count
	if no >= count: return false
	var handle: Variant = model.call("start_motion", group, no, priority)
	if handle == null or int(handle.get("error")) != 0: return false
	var motion := Live2DGesture.load_motion(CharacterCatalog.motion_file(entry, group, no))
	_main = {"kind": kind, "left": float(motion.get("duration", 3.0)), "group": group, "no": no}
	return true

func _fit_model() -> void:
	if not is_instance_valid(model) or size.y <= 0: return
	var canvas: Dictionary = model.call("get_canvas_info")
	if canvas.is_empty(): return
	var frame := CharacterCatalog.framing(entry, place)
	var pixels: Vector2 = canvas.size_in_pixels
	var scale_value := size.y * float(frame.zoom) * layout_zoom / maxf(pixels.y, 1.0)
	model.scale = Vector2.ONE * scale_value
	# The model's origin is its canvas centre; move it so the framing focus lands in the middle of this rect.
	var focus: Vector2 = frame.focus
	var focus_offset: Vector2 = (focus - Vector2(0.5, 0.5)) * pixels * scale_value
	var anchor := size / 2 + layout_offset * size
	model.position = anchor - focus_offset + _model_offset()
	model.set_meta("rest", anchor - focus_offset)

## name: play / attack / hit / turn / win / lose. Unknown names and missing motions are ignored.
func act(name: String) -> void:
	if not name in CharacterCatalog.ACTIONS: return
	# Routine moments do not cut into an action that is still playing; being hit and the result do.
	_perform(CharacterCatalog.action(entry, name), name, PRIORITY_FORCE if name in ["hit", "win", "lose"] else PRIORITY_NORMAL)

## Plays one action spec; kick names the fallback movement used by portraits and the drawn default.
##   motion     [group, no]  replaces the idle motion until it ends (whole-body performances)
##   gesture    [group, no]  layered over the idle motion; the end pose is held for "hold" seconds,
##   release    [group, no]  then this motion brings it back (e.g. raise a hand / lower it)
##   expression id           kept for "hold" seconds, then faded out
func _perform(spec: Dictionary, kick: String, priority: int) -> void:
	_kick = kick
	_kick_age = 0.0
	if is_instance_valid(model):
		var motion: Variant = spec.get("motion", [])
		if motion is Array and motion.size() in [1, 2]: _play_main(motion, priority, "action")
		var hold := float(spec.get("hold", 2.5))
		if spec.has("gesture"): _start_gesture(spec.gesture, spec.get("release", []), hold)
		var expression := str(spec.get("expression", ""))
		if _rig != null and not expression.is_empty(): expression = _rig.hotkey_expression(expression)
		if not expression.is_empty():
			model.call("start_expression", expression)
			_expression_left = hold if not kick in ["win", "lose"] else 999.0
	set_process(true)

## [group, no] from model3.json, or (with a VTube Studio setup) the name of one of the author's animation hotkeys.
func _gesture_file(spec: Variant) -> String:
	if spec is String: return _rig.hotkey_motion(spec) if _rig != null else ""
	if spec is Array and spec.size() == 2: return CharacterCatalog.motion_file(entry, str(spec[0]), int(spec[1]))
	return ""

func _ensure_params() -> void:
	if _params.is_empty() and is_instance_valid(model):
		for parameter in model.call("get_parameters"): _params[str(parameter.get("id"))] = parameter

## A gesture already under way finishes first; overlapping ones would fight over the same parameters.
func _start_gesture(gesture: Variant, release: Variant, hold: float) -> void:
	if not _gesture.is_empty(): return
	var out := Live2DGesture.load_motion(_gesture_file(gesture))
	if out.is_empty(): return
	var back := Live2DGesture.load_motion(_gesture_file(release))
	_ensure_params()
	var base := {}
	for id in out.curves.keys() + (back.get("curves", {}).keys()):
		if _params.has(id) and not base.has(id): base[id] = float(_params[id].get("value"))
	_gesture = {"out": out, "back": back, "hold": maxf(hold, 0.0), "phase": "out", "t": 0.0, "base": base, "last": {}}

## Drives the gesture's parameters on top of whatever the idle motion produced this frame.
func _update_gesture(delta: float) -> void:
	if _gesture.is_empty(): return
	_gesture.t += delta
	var values: Dictionary = _gesture.last
	var weight := 1.0
	match _gesture.phase:
		"out":
			values = _sample(_gesture.out, _gesture.t)
			weight = smoothstep(0.0, GESTURE_BLEND, _gesture.t)
			if _gesture.t >= _gesture.out.duration: _next_phase("hold")
		"hold":
			if _gesture.t >= _gesture.hold: _next_phase("back" if not _gesture.back.is_empty() else "fade")
		"back":
			values = values.merged(_sample(_gesture.back, _gesture.t), true)
			if _gesture.t >= _gesture.back.duration: _next_phase("fade")
		"fade":
			weight = 1.0 - smoothstep(0.0, GESTURE_BLEND, _gesture.t)
			if _gesture.t >= GESTURE_BLEND:
				for id in _gesture.base: _params[id].call("set_hold", false)
				_gesture = {}
				return
	_gesture.last = values
	for id in values:
		if not _gesture.base.has(id): continue
		_params[id].set("value", lerpf(float(_gesture.base[id]), float(values[id]), weight))
		_params[id].call("set_hold", true)

func _next_phase(phase: String) -> void:
	_gesture.phase = phase
	_gesture.t = 0.0

func _sample(motion: Dictionary, t: float) -> Dictionary:
	var values := {}
	var time := minf(t, float(motion.duration))
	for id in motion.curves: values[id] = Live2DGesture.evaluate(motion.curves[id], time)
	return values

## kind: "idle", "touch_head" or "touch_body". Picks a different entry from last time when there is more than one.
func perform_home(kind: String) -> void:
	var choices := CharacterCatalog.home_actions(entry, kind)
	_idle_left = randf_range(IDLE_SECONDS.x, IDLE_SECONDS.y)
	if choices.is_empty(): return
	var index := randi() % choices.size()
	if choices.size() > 1 and index == int(_last_touch.get(kind, -1)): index = (index + 1) % choices.size()
	_last_touch[kind] = index
	_perform(choices[index], "turn" if kind == "idle" else "play", PRIORITY_NORMAL if kind == "idle" else PRIORITY_FORCE)

func _gui_input(event: InputEvent) -> void:
	if not interactive(): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.double_click:
			set_layout(Vector2.ZERO, 1.0)
			_press = null
			accept_event()
		elif event.pressed:
			_press = event.position
			_dragging = false
			accept_event()
		elif _press != null:
			# A press that did not move is a touch; one that moved was a drag and only repositions the character.
			if _dragging: CharacterCatalog.set_home_layout(character_id, layout_offset, layout_zoom)
			else: _touch(_press)
			_press = null
			_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _press != null and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if not _dragging and (event.position - (_press as Vector2)).length() > DRAG_THRESHOLD: _dragging = true
		if _dragging:
			set_layout(layout_offset + event.relative / size.max(Vector2.ONE), layout_zoom, false)
			accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var factor := 1.06 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.06
		zoom_at(event.position, factor)
		accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_at(event.position, event.factor)
		accept_event()

## Resizes around a point of the frame, so what is under the pointer stays under it.
func zoom_at(point: Vector2, factor: float) -> void:
	var next := clampf(layout_zoom * factor, 0.4, 3.0)
	var applied := next / layout_zoom
	var anchor := size / 2 + layout_offset * size
	var moved := point + (anchor - point) * applied
	set_layout((moved - size / 2) / size.max(Vector2.ONE), next)

func set_layout(offset: Vector2, zoom: float, save := true) -> void:
	layout_offset = offset.clamp(Vector2(-0.9, -0.9), Vector2(0.9, 0.9))
	layout_zoom = clampf(zoom, 0.4, 3.0)
	_fit_model()
	queue_redraw()
	if save and interactive(): CharacterCatalog.set_home_layout(character_id, layout_offset, layout_zoom)

func _touch(local: Vector2) -> void:
	var zone := touched_zone(local)
	if zone.is_empty(): return
	if _life != null: _life.nudge((local - Vector2(size.x / 2, size.y * 0.3)).normalized() * Vector2(-0.6, 0.4))
	perform_home("touch_" + zone)

## "head" / "body" from the model's HitAreas when it declares them, "" for a click outside them;
## models without hit areas (and portraits) split the frame at HEAD_LINE.
func touched_zone(local: Vector2) -> String:
	if is_instance_valid(model):
		var areas: Array = model.call("get_hit_areas")
		if not areas.is_empty():
			var meshes: Dictionary = model.call("get_meshes")
			var point: Vector2 = model.get_global_transform_with_canvas().affine_inverse() * (get_global_transform_with_canvas() * local)
			var found := ""
			for area in areas:
				var mesh: Variant = meshes.get(str(area.get("id", "")))
				if not mesh is MeshInstance2D or mesh.mesh == null: continue
				var box: AABB = mesh.mesh.get_aabb()
				if Rect2(box.position.x, box.position.y, box.size.x, box.size.y).has_point(point):
					var name := str(area.get("name", "")).to_lower()
					if "head" in name: return "head"
					found = "body"
			return found
	return "head" if local.y < size.y * HEAD_LINE else "body"

## Any click or key press anywhere counts as activity, so idle actions only play while the player is away.
func _input(event: InputEvent) -> void:
	if interactive() and event is InputEventMouseMotion:
		_pointer = event.position
		_pointer_rest = 0.0
	if interactive() and (event is InputEventMouseButton or event is InputEventKey or event is InputEventScreenTouch) and event.is_pressed():
		_idle_left = maxf(_idle_left, IDLE_SECONDS.x)

## The pointer relative to the face in -1..1 (y up), or null; a pointer 0.6 frames away turns the head fully.
func pointer_target() -> Variant:
	if not _pointer is Vector2: return null
	var face := get_global_transform_with_canvas() * Vector2(size.x * 0.5, size.y * 0.3)
	var reach := Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0)) * 0.6
	var target: Vector2 = ((_pointer as Vector2 - face) / reach).clamp(Vector2(-1, -1), Vector2(1, 1))
	return Vector2(target.x, -target.y)

func _process(delta: float) -> void:
	_pointer_rest += delta
	if _life != null and is_visible_in_tree(): _life.update(delta, pointer_target() if interactive() else null, _pointer_rest)
	if _rig != null and is_instance_valid(model):
		_ensure_params()
		# On the home page the pointer stands in for face tracking; after it has rested for "tracking_lost_after" seconds
		# the author's tracking-lost animation plays. Elsewhere the character faces forward.
		var lost_after := float(entry.get("tracking_lost_after", 20.0))
		var lost := interactive() and lost_after >= 0.0 and _pointer_rest >= lost_after
		_rig.update(delta, pointer_target() if interactive() else null, lost, _params)
	if interactive() and is_visible_in_tree():
		_idle_left -= delta
		if _idle_left <= 0.0 and _kick.is_empty() and _gesture.is_empty(): perform_home("idle")
	if not _kick.is_empty():
		_kick_age += delta
		if _kick_age >= float(KICK_SECONDS.get(_kick, 0.5)) and not _kick in ["win", "lose"]: _kick = ""
		queue_redraw()
	if is_instance_valid(model):
		_update_gesture(delta)
		if model.has_meta("rest"): model.position = model.get_meta("rest") + _model_offset()
		model.modulate = _kick_modulate()
		if _expression_left > 0.0:
			_expression_left -= delta
			if _expression_left <= 0.0: model.call("stop_expression")
		if not _main.is_empty():
			_main.left -= delta
			if _main.left <= MOTION_HANDOVER: _start_idle()
		elif model.call("get_cubism_motion_queue_entries").is_empty(): _start_idle()
		_step_model(delta)

## Re-reads the Live2D quality setting (step rate; mask size applies to models built afterwards).
func apply_quality() -> void:
	_quality_steps = int(CharacterCatalog.LIVE2D_QUALITY[CharacterCatalog.live2d_quality()].get(place, 2))

func _step_model(delta: float) -> void:
	_since_step += delta
	if not is_visible_in_tree():
		# Resume without a jump when the figure shows again.
		_since_step = minf(_since_step, 0.1)
		return
	_frames_since_step += 1
	if _frames_since_step < (step_frames if step_frames > 0 else _quality_steps): return
	model.call("advance", minf(_since_step, 0.1))
	_since_step = 0.0
	_frames_since_step = 0

func _envelope() -> float:
	var length := float(KICK_SECONDS.get(_kick, 0.5))
	return sin(clampf(_kick_age / length, 0.0, 1.0) * PI)

## A Live2D model moves through its own motions; the whole figure only gives a small shake when hit.
func _model_offset() -> Vector2:
	return _kick_offset() * 0.4 if _kick == "hit" else Vector2.ZERO

func _kick_offset() -> Vector2:
	var strength := _envelope()
	match _kick:
		"play": return Vector2(0, -10 * strength)
		"attack": return Vector2(0, -6 * strength)
		"hit": return Vector2(sin(_kick_age * 70.0) * 7.0 * strength, 0)
		"turn": return Vector2(0, -5 * strength)
	return Vector2.ZERO

func _kick_modulate() -> Color:
	match _kick:
		"hit": return Color(1, 1, 1).lerp(Color(1.0, 0.55, 0.5), _envelope())
		"lose": return Color(0.62, 0.62, 0.66)
	return Color.WHITE

func _draw() -> void:
	if is_instance_valid(model):
		if _kick == "win": _draw_glow()
		return
	var offset := _kick_offset()
	var colour := _kick_modulate()
	if _kick == "win": _draw_glow()
	if portrait != null:
		var frame := CharacterCatalog.framing(entry, place, true)
		var image := portrait.get_size()
		var scale_value := size.y * float(frame.zoom) * layout_zoom / maxf(image.y, 1.0)
		var drawn := image * scale_value
		var focus: Vector2 = frame.focus
		var origin: Vector2 = size / 2 + layout_offset * size - focus * drawn + offset
		draw_texture_rect(portrait, Rect2(origin, drawn), false, colour)
		return
	_draw_silhouette(offset, colour)

func _draw_glow() -> void:
	var centre := Vector2(size.x / 2, size.y * 0.45)
	var radius := minf(size.x, size.y) * 0.5
	for ring in 8:
		draw_circle(centre, radius * (1.0 - ring * 0.1), Color(0.95, 0.88, 0.68, 0.035))

## The default commander: a drawn bust in the player's sin colour, framed like a portrait.
func _draw_silhouette(offset: Vector2, colour: Color) -> void:
	var frame := CharacterCatalog.framing(entry, place, true)
	var unit := size.y * float(frame.zoom) * layout_zoom / 2.6
	var focus: Vector2 = frame.focus
	var centre: Vector2 = size / 2 + layout_offset * size - (focus - Vector2(0.5, 0.5)) * Vector2(unit * 1.6, unit * 2.6) + offset
	var body := tint.darkened(0.35) * colour
	var edge := tint.lightened(0.25) * colour
	var head: Vector2 = centre + Vector2(0, -unit * 0.62)
	var shoulders := PackedVector2Array([
		centre + Vector2(-unit * 0.95, unit * 1.3), centre + Vector2(-unit * 0.86, unit * 0.32),
		centre + Vector2(-unit * 0.42, unit * 0.02), centre + Vector2(0, unit * 0.22),
		centre + Vector2(unit * 0.42, unit * 0.02), centre + Vector2(unit * 0.86, unit * 0.32),
		centre + Vector2(unit * 0.95, unit * 1.3)])
	draw_colored_polygon(shoulders, body)
	draw_polyline(shoulders, edge, 2.0, true)
	var collar := PackedVector2Array([centre + Vector2(-unit * 0.24, unit * 0.04), centre + Vector2(0, unit * 0.42), centre + Vector2(unit * 0.24, unit * 0.04)])
	draw_polyline(collar, edge, 2.0, true)
	draw_circle(head, unit * 0.4, body)
	draw_arc(head, unit * 0.4, 0, TAU, 48, edge, 2.0, true)
	# Cap brim, so the default reads as a commander rather than a placeholder.
	draw_line(head + Vector2(-unit * 0.5, -unit * 0.18), head + Vector2(unit * 0.5, -unit * 0.18), edge, 3.0, true)
