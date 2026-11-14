class_name HomeParallax
extends Node
## Mouse parallax for the home page, after the open-source ak-ui dashboard depth (MIT, YunYouJun/ak-ui): with the
## pointer at -1..1 across the screen, a layer of depth d moves by -x * 130 * d, -y * 70 * d pixels, eased (about the
## 440 ms ease-out the reference uses) and back to centre when the pointer leaves the window. Layout keeps owning each layer's rest
## position: the offset applied last frame is taken off first, and a position changed by layout becomes the new rest.

const EASE := 7.0
const MAX := Vector2(130, 70)
var _layers: Array = []
var _input := Vector2.ZERO
## Small extra turn of the front board, in radians at the screen edge.
var tilt := 0.008
## Tests set this (-1..1 per axis) in place of the pointer.
var input_override: Variant = null

static func depth(value: float) -> Vector2:
	return MAX * value

func add_layer(node: Control, depth: Vector2, turns := false) -> void:
	_layers.append({"node": node, "depth": depth, "applied": Vector2.ZERO, "expected": node.position, "turns": turns, "turned": 0.0, "expected_turn": node.rotation})

func _process(delta: float) -> void:
	var viewport := get_viewport()
	if viewport == null: return
	var rect := viewport.get_visible_rect()
	var target := Vector2.ZERO
	var window := get_window()
	if not OS.has_feature("mobile") and window != null and window.has_focus():
		var mouse := viewport.get_mouse_position()
		if rect.has_point(mouse):
			target = ((mouse - rect.get_center()) / (rect.size / 2).max(Vector2.ONE)).clamp(-Vector2.ONE, Vector2.ONE)
	if input_override is Vector2: target = input_override
	_input = _input.lerp(target, 1.0 - exp(-delta * EASE))
	for layer in _layers:
		var node: Control = layer.node
		if not is_instance_valid(node): continue
		var rest: Vector2 = node.position - layer.applied
		if not node.position.is_equal_approx(layer.expected): rest = node.position
		var offset: Vector2 = -_input * layer.depth
		node.position = rest + offset
		layer.applied = offset
		layer.expected = node.position
		if layer.turns:
			var base: float = node.rotation - float(layer.turned)
			if not is_equal_approx(node.rotation, float(layer.expected_turn)): base = node.rotation
			var turn: float = _input.x * tilt
			node.rotation = base + turn
			layer.turned = turn
			layer.expected_turn = node.rotation
