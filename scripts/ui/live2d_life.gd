class_name Live2DLife
extends RefCounted
## Procedural movement added on top of a model's own motions, so a character never freezes between them.
## Each layer is a GDCubismEffectTargetPoint (it adds to parameters and eases toward its target) mapped onto different
## standard parameters and driven at a different speed: the eyes lead, the head follows and the body comes last.
## "drift" is a slow, always-on sway; the look layers follow the pointer, or glance around when it rests.
## Channel order: head_angle_x, head_angle_y, head_angle_z, body_angle_x, eyes_ball_x, eyes_ball_y.
## A channel's value is target.x / target.y / target.x * target.y / target.x scaled by the ranges below; "" leaves it out.
const LAYERS := {
	"eyes": {"ids": ["", "", "", "", "ParamEyeBallX", "ParamEyeBallY"], "head": 0.0, "body": 0.0, "eyes": 1.0, "speed": 16.0, "look": true},
	"head": {"ids": ["ParamAngleX", "ParamAngleY", "ParamAngleZ", "", "", ""], "head": 26.0, "body": 0.0, "eyes": 0.0, "speed": 6.0, "look": true},
	"body": {"ids": ["ParamBodyAngleX", "ParamBodyAngleY", "", "ParamBodyAngleZ", "", ""], "head": 9.0, "body": 3.5, "eyes": 0.0, "speed": 2.4, "look": true},
	"drift": {"ids": ["ParamAngleZ", "ParamAngleY", "", "ParamBodyAngleZ", "ParamEyeBallX", "ParamEyeBallY"], "head": 6.0, "body": 3.0, "eyes": 0.12, "speed": 2.0, "look": false},
}
const PROPERTIES := ["head_angle_x", "head_angle_y", "head_angle_z", "body_angle_x", "eyes_ball_x", "eyes_ball_y"]
## Seconds without pointer movement after which the character starts looking around on its own.
const POINTER_REST := 3.5

var look := false
var _effects := {}
var _points := {}
var _time := randf() * 100.0
var _wander := Vector2.ZERO
var _wander_left := 0.0
var _saccade := Vector2.ZERO
var _saccade_left := 0.0
var _nudge := Vector2.ZERO

## look: follow the pointer (home page). Without it only the drift layer runs (HQ slot, result stage).
func attach(model: Node, follow_pointer: bool) -> void:
	look = follow_pointer
	if not ClassDB.class_exists("GDCubismEffectTargetPoint"): return
	for name in LAYERS:
		var layer: Dictionary = LAYERS[name]
		if layer.look and not look: continue
		var effect: Node = ClassDB.instantiate("GDCubismEffectTargetPoint")
		effect.name = "Life_" + name
		for i in PROPERTIES.size(): effect.set(PROPERTIES[i], layer.ids[i])
		effect.set("head_range", layer.head)
		effect.set("body_range", layer.body)
		effect.set("eyes_range", layer.eyes)
		model.add_child(effect)
		_effects[name] = effect
		_points[name] = Vector2.ZERO

func layer_count() -> int:
	return _effects.size()

## A brief push of the drift layer, e.g. away from where the character was poked.
func nudge(direction: Vector2) -> void:
	_nudge = direction.limit_length(1.0)

## pointer: the pointer relative to the face in -1..1 (y up), or null when there is none; resting: seconds since it moved.
func update(delta: float, pointer: Variant, resting: float) -> void:
	_time += delta
	_nudge = _nudge.lerp(Vector2.ZERO, clampf(delta * 3.0, 0.0, 1.0))
	var drift := Vector2(_wave(0.31, 0.0) * 0.7, _wave(0.23, 2.1) * 0.5) + _nudge
	_steer("drift", drift, delta)
	if not look: return
	var target := Vector2.ZERO
	if pointer is Vector2 and resting < POINTER_REST:
		target = pointer
		_wander_left = randf_range(0.5, 1.5)
	else:
		# Glance somewhere now and then; often back at the viewer.
		_wander_left -= delta
		if _wander_left <= 0.0:
			_wander = Vector2.ZERO if randf() < 0.4 else Vector2(randf_range(-0.7, 0.7), randf_range(-0.35, 0.45))
			_wander_left = randf_range(1.6, 4.5)
		target = _wander
	# Small eye darts on top of where the head is pointed.
	_saccade_left -= delta
	if _saccade_left <= 0.0:
		_saccade = Vector2(randf_range(-0.12, 0.12), randf_range(-0.08, 0.08))
		_saccade_left = randf_range(0.6, 2.2)
	_steer("eyes", (target + _saccade).clamp(Vector2(-1, -1), Vector2(1, 1)), delta)
	_steer("head", target, delta)
	_steer("body", target, delta)

func _steer(name: String, target: Vector2, delta: float) -> void:
	if not _effects.has(name) or not is_instance_valid(_effects[name]): return
	var speed := float(LAYERS[name].speed)
	_points[name] = (_points[name] as Vector2).lerp(target, clampf(delta * speed, 0.0, 1.0))
	_effects[name].call("set_target", _points[name])

## Smooth noise from a few incommensurate sines, roughly -1..1.
func _wave(frequency: float, phase: float) -> float:
	var t := _time * frequency + phase
	return sin(t) * 0.6 + sin(t * 2.3 + 1.7) * 0.28 + sin(t * 5.1 + 0.6) * 0.12
