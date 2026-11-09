extends RefCounted
## Finger motion before the hold is scrolling, never card dragging.
const HOLD_SECONDS := 0.35
const INSPECT_SECONDS := 0.42
const MOVE_TOLERANCE := 18.0
var control: Control
var touching := false
var ready := false
var touch_mode := OS.has_feature("mobile")
var hold_required := true
var elapsed := 0.0
var start := Vector2.ZERO
var suppress_click_until := 0
var inspect_requested: Callable
var inspect_allowed: Callable
var inspected := false
var dragging := false
var finger := -1
var fingers := {}
var canceled_sequence := false
var gesture_id := 0
var gesture_aborted := false

func _init(node: Control) -> void:
	control = node

func gui_input(event: InputEvent) -> void:
	var raw_touch: bool = event is InputEventScreenTouch and event.pressed and not event.canceled
	var press: bool = raw_touch or event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	if not press: return
	if fingers.size() <= 1: canceled_sequence = false
	if raw_touch or event.device == InputEvent.DEVICE_ID_EMULATION: touch_mode = true
	if not touch_mode or touching or fingers.size() > 1: return
	if not hold_required and not inspect_requested.is_valid(): return
	gesture_id += 1
	gesture_aborted = false
	touching = true
	ready = false
	inspected = false
	dragging = false
	finger = int(event.index) if raw_touch else -1
	elapsed = 0.0
	start = control.get_global_transform_with_canvas() * event.position
	control.set_process(true)

func input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		touch_mode = true
		if event.pressed and not event.canceled: fingers[event.index] = true
		else: fingers.erase(event.index)
		# Godot can deliver the synthesized mouse release before the canceled
		# touch itself. Deferred click handlers must still see cancellation.
		if event.canceled:
			gesture_aborted = true
			cancel(true)
			return
		if touching and fingers.size() > 1:
			gesture_aborted = true
			cancel(true)
			return
	if not touching: return
	if event is InputEventScreenTouch and finger >= 0 and event.index != finger: return
	if event is InputEventScreenDrag and finger >= 0 and event.index != finger: return
	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		if inspect_requested.is_valid():
			# Battle cards drag as soon as the finger moves deliberately. Library
			# cards still require a hold first, so a quick swipe remains scrolling.
			if dragging or event.position.distance_to(start) <= MOVE_TOLERANCE: return
			if hold_required and elapsed < HOLD_SECONDS or not control.can_begin_drag():
				cancel(true)
				return
			dragging = true
			ready = true
			control.set_process(false)
			control.begin_touch_drag()
			return
		if not ready and event.position.distance_to(start) > MOVE_TOLERANCE:
			cancel(true)
	elif event is InputEventScreenTouch and (not event.pressed or event.canceled):
		cancel(ready or inspected or event.canceled)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		cancel(ready or inspected)

func tick(delta: float) -> void:
	if not touching or dragging: return
	elapsed += delta
	if inspect_requested.is_valid():
		if not control.is_visible_in_tree() or control.disabled:
			cancel(true)
			return
		if hold_required and elapsed >= HOLD_SECONDS: ready = true
		if inspected or elapsed < INSPECT_SECONDS: return
		if inspect_allowed.is_valid() and not inspect_allowed.call():
			cancel(true)
			return
		inspected = true
		inspect_requested.call()
		return
	if ready: return
	if elapsed < HOLD_SECONDS: return
	if control.disabled or not control.can_begin_drag(): cancel(true); return
	ready = true
	suppress_click_until = Time.get_ticks_msec() + 500
	control.begin_touch_drag()

func cancel(suppress: bool = false) -> void:
	if suppress:
		canceled_sequence = true
		suppress_click_until = Time.get_ticks_msec() + 250
	touching = false
	ready = false
	inspected = false
	dragging = false
	finger = -1
	control.set_process(false)

func reset() -> void:
	fingers.clear()
	gesture_aborted = true
	cancel(true)

func protect_drop(data: Dictionary) -> Dictionary:
	if touch_mode:
		var ticket := gesture_id
		data["_touch_valid"] = func(): return not gesture_aborted and ticket == gesture_id
	return data

func can_drag() -> bool:
	# Inspection gestures use force_drag after the touch tolerance is crossed,
	# avoiding Godot's smaller mouse drag threshold stealing a long press.
	if touch_mode and inspect_requested.is_valid(): return false
	return not hold_required or not touch_mode or touching and ready

func ignore_click() -> bool:
	return ready or inspected or canceled_sequence or Time.get_ticks_msec() < suppress_click_until
