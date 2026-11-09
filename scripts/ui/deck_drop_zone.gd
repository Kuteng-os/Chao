extends PanelContainer
## Drop destinations are also active above their nested card/list controls.
signal card_dropped(card_id: String)
var accepted_type := "deck_add"
var active := false

func forward_children(parent: Node = self) -> void:
	for child in parent.get_children():
		if child is Control:
			child.set_drag_forwarding(
				func(at): return child._get_drag_data(at) if child.has_method("_get_drag_data") else null,
				func(_at, data): return _can_drop_data(Vector2.ZERO, data),
				func(_at, data): _drop_data(Vector2.ZERO, data)
			)
		forward_children(child)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(true)

func _process(_delta: float) -> void:
	var data: Variant = get_viewport().gui_get_drag_data()
	var next: bool = get_viewport().gui_is_dragging() and data is Dictionary and data.get("type") == accepted_type and get_global_rect().has_point(get_global_mouse_position())
	if next != active:
		active = next
		queue_redraw()

func _draw() -> void:
	if active: draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Color("d4b76f"), false, 2)

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type") == accepted_type and data.get("card_id") is String

func _drop_data(_position: Vector2, data: Variant) -> void:
	if _can_drop_data(_position, data):
		_finish_drop.call_deferred(str(data.card_id),data.get("_touch_valid",Callable()))

func _finish_drop(id: String, valid: Callable) -> void:
	if not valid.is_valid() or valid.call(): card_dropped.emit(id)
