extends Control
var stage: BattleStage3D
var veil: Control
class Veil extends Control:
	var strength:=0.35
	func _draw() -> void:
		material.set_shader_parameter("strength",strength)
		draw_style_box(StyleBoxEmpty.new(),Rect2(Vector2.ZERO,size))
		draw_texture_rect(placeholder,Rect2(Vector2.ZERO,size),false)
	var placeholder:GradientTexture2D
	func _ready() -> void:
		placeholder=GradientTexture2D.new();placeholder.gradient=Gradient.new()
		var shader:=ShaderMaterial.new();shader.shader=preload("res://assets/shaders/menu_veil.gdshader");material=shader
		resized.connect(queue_redraw)

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	stage=BattleStage3D.new();stage.menu_mode=true
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(stage)
	veil=Veil.new();veil.mouse_filter=Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(veil)

func set_page(page: String) -> void:
	visible=page!="battle"
	veil.strength=0.08 if page=="home" else 0.64
	veil.queue_redraw()

func refresh_scene() -> void:
	stage.set_scene(BattleSceneCatalog.selected())
	stage._resize()
