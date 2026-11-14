class_name VTubeRig
extends RefCounted
## Plays a model the way its author set it up for VTube Studio, from the model's *.vtube.json:
## - ParameterSettings map tracking inputs (FaceAngleX, EyeRightX, ...) to model parameters with the author's ranges and
##   smoothing. On the home page the pointer stands in for face tracking.
## - IdleAnimationWhenTrackingLost is what VTube Studio plays with nobody in front of the camera. Authors often make it a
##   gag (a "signal lost" face), so it only plays on the home page after the pointer has rested for a while.
## - Auto-breathing settings drive their parameter.
## - Hotkeys give the author's names for animations and expressions, so character.json can refer to them.
## Head and eye parameters reached this way are written with GDCubismParameter.hold, after the model's own motion.

## Pointer → tracking inputs, in the units VTube Studio's face tracker reports.
const POINTER_INPUTS := {"FaceAngleX": 30.0, "FaceAngleY": 20.0, "EyeRightX": -0.6, "EyeLeftX": -0.6, "EyeRightY": 0.7, "EyeLeftY": 0.7}
const LOST_BLEND := 0.8
const BREATH_SECONDS := 3.6

var mappings: Array = []
var lost_motion: Dictionary = {}
var hotkeys: Dictionary = {}
var _values: Dictionary = {}
var _lost_weight := 0.0
var _lost_time := 0.0
var _time := 0.0
var _held: Dictionary = {}

## path: the *.vtube.json; model_dir: where its animations and expressions live.
static func load_rig(path: String, model_dir: String) -> VTubeRig:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not parsed is Dictionary: return null
	var rig := VTubeRig.new()
	for setting in parsed.get("ParameterSettings", []):
		if not setting is Dictionary or str(setting.get("OutputLive2D", "")).is_empty(): continue
		var input := str(setting.get("Input", ""))
		var breathing := bool(setting.get("UseBreathing", false))
		if not POINTER_INPUTS.has(input) and not breathing: continue
		rig.mappings.append({
			"input": input, "output": str(setting.OutputLive2D), "breathing": breathing,
			"in": Vector2(float(setting.get("InputRangeLower", 0.0)), float(setting.get("InputRangeUpper", 1.0))),
			"out": Vector2(float(setting.get("OutputRangeLower", 0.0)), float(setting.get("OutputRangeUpper", 1.0))),
			"smoothing": clampf(float(setting.get("Smoothing", 0.0)), 0.0, 100.0)})
	var references: Variant = parsed.get("FileReferences", {})
	if references is Dictionary:
		rig.lost_motion = Live2DGesture.load_motion(find_file(model_dir, str(references.get("IdleAnimationWhenTrackingLost", ""))))
	for hotkey in parsed.get("Hotkeys", []):
		if not hotkey is Dictionary: continue
		var file := str(hotkey.get("File", ""))
		if file.is_empty(): continue
		rig.hotkeys[str(hotkey.get("Name", ""))] = {"action": str(hotkey.get("Action", "")), "file": file, "path": find_file(model_dir, file)}
	return rig

## VTube Studio refers to files by name and finds them anywhere in the model folder.
static func find_file(model_dir: String, file_name: String) -> String:
	if file_name.is_empty() or "/" in file_name or "\\" in file_name: return ""
	if FileAccess.file_exists(model_dir.path_join(file_name)): return model_dir.path_join(file_name)
	var directory := DirAccess.open(model_dir)
	if directory == null: return ""
	for sub in directory.get_directories():
		var path := model_dir.path_join(sub).path_join(file_name)
		if FileAccess.file_exists(path): return path
	return ""

## The motion3.json behind an animation hotkey, "" when the name is not an animation.
func hotkey_motion(name: String) -> String:
	var hotkey: Dictionary = hotkeys.get(name, {})
	return str(hotkey.get("path", "")) if hotkey.get("action", "") == "TriggerAnimation" else ""

## The expression name behind an expression hotkey (its file name without .exp3.json), or the name itself.
func hotkey_expression(name: String) -> String:
	var hotkey: Dictionary = hotkeys.get(name, {})
	if hotkey.get("action", "") == "ToggleExpression": return str(hotkey.file).trim_suffix(".exp3.json")
	return name

## pointer: -1..1 relative to the face (y up), or null to face forward; lost: play the tracking-lost animation;
## params: id → GDCubismParameter.
func update(delta: float, pointer: Variant, lost_tracking: bool, params: Dictionary) -> void:
	_time += delta
	var tracking := pointer is Vector2
	_lost_weight = move_toward(_lost_weight, 1.0 if lost_tracking else 0.0, delta / LOST_BLEND)
	if _lost_weight <= 0.0: _lost_time = 0.0
	var inputs := {}
	var point: Vector2 = pointer if tracking else Vector2.ZERO
	for input in POINTER_INPUTS:
		var axis := point.x if input.ends_with("X") else point.y
		inputs[input] = axis * float(POINTER_INPUTS[input])
	var lost := {}
	if not lost_motion.is_empty() and _lost_weight > 0.0:
		_lost_time = fmod(_lost_time + delta, float(lost_motion.duration))
		for id in lost_motion.curves: lost[id] = Live2DGesture.evaluate(lost_motion.curves[id], _lost_time)
	var written := {}
	for mapping in mappings:
		var output: String = mapping.output
		if not params.has(output): continue
		var target: float
		if mapping.breathing:
			target = lerpf(mapping.out.x, mapping.out.y, (sin(_time * TAU / BREATH_SECONDS) + 1.0) / 2.0)
		else:
			var weight := inverse_lerp(mapping.in.x, mapping.in.y, float(inputs.get(mapping.input, 0.0)))
			target = lerpf(mapping.out.x, mapping.out.y, weight)
		# VTube Studio smoothing: 0 follows at once, 100 barely moves.
		var rate := 25.0 * (1.0 - float(mapping.smoothing) / 100.0) + 1.0
		var current := float(_values.get(output, target))
		_values[output] = lerpf(current, target, 1.0 - exp(-delta * rate))
		var value := float(_values[output])
		if lost.has(output) and not mapping.breathing: value = lerpf(value, float(lost[output]), _lost_weight)
		written[output] = value
	# Parameters only the tracking-lost animation moves fade in with it and are let go once it is gone.
	for id in lost:
		if written.has(id) or not params.has(id): continue
		if _lost_weight >= 0.999: written[id] = lost[id]
		elif _lost_weight > 0.001: written[id] = lerpf(float(params[id].get("default_value")), float(lost[id]), _lost_weight)
	for id in written:
		params[id].set("value", written[id])
		params[id].call("set_hold", true)
	for id in _held:
		if not written.has(id) and params.has(id): params[id].call("set_hold", false)
	_held = written

func tracking_lost_weight() -> float:
	return _lost_weight
