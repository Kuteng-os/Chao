extends RefCounted
## Screen pixels and canvas coordinates are different under content scaling.
## Keep art full-bleed; apply the safe rectangle only to interactive content.
static func configure(window: Window, mobile: bool) -> void:
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if mobile:
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.content_scale_size = Vector2i(1280, 800)
		if OS.get_name() in ["Android", "iOS"]:
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)

static func safe_rect(control: Control) -> Rect2:
	var full := Rect2(Vector2.ZERO, control.size)
	if OS.get_name() not in ["Android", "iOS"]: return full
	# CanvasItem.get_screen_transform omits root content scaling on Android.
	# Use the viewport transform, as native touch events do, before local mapping.
	var to_screen := control.get_viewport().get_screen_transform() * control.get_global_transform_with_canvas()
	return canvas_safe_rect(control.size, to_screen, Rect2(DisplayServer.get_display_safe_area()))

static func canvas_safe_rect(canvas_size: Vector2, to_screen: Transform2D, screen_safe: Rect2) -> Rect2:
	var full := Rect2(Vector2.ZERO, canvas_size)
	if not screen_safe.has_area() or is_zero_approx(to_screen.determinant()): return full
	var safe: Rect2 = (to_screen.affine_inverse() * screen_safe).intersection(full)
	return safe if safe.has_area() else full
