class_name Live2DGesture
extends RefCounted
## Reads Cubism motion3.json curves so a gesture (raise a hand, show a prop) can be layered over the idle motion.
## GDCubism plays one motion at a time; a gesture played through it would stop the idle breathing and sway, so
## CommanderFigure drives the gesture's parameters itself and leaves the idle motion running underneath.
static var _cache: Dictionary = {}

## {"duration": seconds, "curves": {parameter id: segments}}; empty when the file is missing or malformed.
static func load_motion(path: String) -> Dictionary:
	if path.is_empty(): return {}
	if _cache.has(path): return _cache[path]
	var result := {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if parsed is Dictionary and parsed.get("Meta") is Dictionary and parsed.get("Curves") is Array:
		var curves := {}
		for curve in parsed.Curves:
			if not curve is Dictionary or str(curve.get("Target", "")) != "Parameter": continue
			var segments: Variant = curve.get("Segments")
			if segments is Array and segments.size() >= 2: curves[str(curve.get("Id", ""))] = segments
		if not curves.is_empty(): result = {"duration": maxf(float(parsed.Meta.get("Duration", 0.0)), 0.01), "curves": curves}
	_cache[path] = result
	return result

## Value of a motion3 curve at time t (seconds). Segment kinds: 0 linear, 1 bezier, 2 stepped, 3 inverse stepped.
static func evaluate(segments: Array, t: float) -> float:
	var x0 := float(segments[0])
	var y0 := float(segments[1])
	if t <= x0: return y0
	var i := 2
	while i < segments.size():
		var kind := int(segments[i])
		var span := 6 if kind == 1 else 2
		if i + span >= segments.size(): break
		var x1 := float(segments[i + span - 1])
		var y1 := float(segments[i + span])
		if t <= x1:
			match kind:
				0: return lerpf(y0, y1, (t - x0) / maxf(x1 - x0, 0.0001))
				1: return _bezier(Vector2(x0, y0), Vector2(float(segments[i + 1]), float(segments[i + 2])), Vector2(float(segments[i + 3]), float(segments[i + 4])), Vector2(x1, y1), t)
				2: return y0
				3: return y1
		x0 = x1
		y0 = y1
		i += span + 1
	return y0

## Solves the curve's x for t by bisection (x is monotonic in Cubism curves), then returns its y.
static func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> float:
	var low := 0.0
	var high := 1.0
	var s := 0.5
	for step in 16:
		s = (low + high) / 2.0
		var x := _cubic(p0.x, p1.x, p2.x, p3.x, s)
		if x < t: low = s
		else: high = s
	return _cubic(p0.y, p1.y, p2.y, p3.y, s)

static func _cubic(a: float, b: float, c: float, d: float, s: float) -> float:
	var u := 1.0 - s
	return u * u * u * a + 3.0 * u * u * s * b + 3.0 * u * s * s * c + s * s * s * d
