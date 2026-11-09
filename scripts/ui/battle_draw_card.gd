extends Control
## Reading layer for one received card. Never handles input or owns card state.
const Face = preload("res://scripts/ui/card_face.gd")
const Back = preload("res://scripts/ui/battle_props.gd")
var front: CardFace
var back: Control
var shadow: StyleBoxFlat

func configure(source: CardFace, sin_id: String) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = source.size
	pivot_offset = size * 0.5
	front = Face.new()
	front.spec = source.spec.duplicate(true)
	front.art_id = source.art_id
	front.use_tooltip = false
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.focus_mode = Control.FOCUS_NONE
	front.custom_minimum_size = size
	front.size = size
	add_child(front)
	# Reuse the already requested art; a late cache completion is picked up below.
	front.artwork = source.artwork
	front.faction_icon = source.faction_icon
	back = Back.new()
	back.kind = "back"
	back.sin_id = sin_id
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.focus_mode = Control.FOCUS_NONE
	add_child(back)
	var body := front.card_body_rect()
	back.position = body.position
	back.size = body.size
	shadow = StyleBoxFlat.new()
	shadow.bg_color = Color(0,0,0,0.08)
	shadow.set_corner_radius_all(5)
	shadow.shadow_color = Color(0,0,0,0.32)
	shadow.shadow_size = 16
	shadow.shadow_offset = Vector2(5,9)
	pose(Vector2.ZERO,1.0,0.0,0.0)

func pose(center: Vector2, magnification: float, angle: float, flip: float) -> void:
	position = center - pivot_offset
	rotation = angle
	scale = Vector2(maxf(0.035,absf(cos(PI*flip))),1.0)*magnification
	front.visible = flip >= 0.5
	back.visible = not front.visible
	queue_redraw()

func sync_art(source: CardFace) -> void:
	if source.artwork != null and front.artwork != source.artwork:
		front.artwork = source.artwork
		front.queue_redraw()
	if source.faction_icon != null and front.faction_icon != source.faction_icon:
		front.faction_icon = source.faction_icon
		front.queue_redraw()

func _draw() -> void:
	if shadow != null: draw_style_box(shadow,front.card_body_rect())
