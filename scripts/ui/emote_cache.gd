extends RefCounted
static var textures: Dictionary = {}
static var failed: Dictionary = {}
const LIMIT := 12
const DEFAULT_SCALE := 0.46

static func display_scale(value: Variant) -> float:
	if (value is int or value is float) and is_finite(float(value)) and float(value)>=0.25 and float(value)<=2.0: return float(value)
	return DEFAULT_SCALE

static func entry_scale(e: Dictionary) -> float:
	var percent: Variant=e.get("scale_percent",46)
	return display_scale(float(percent)/100.0) if percent is int or percent is float else DEFAULT_SCALE

static func valid(e: Variant) -> bool:
	if not e is Dictionary: return false
	for key in ["emote_id","asset_id","name"]:
		if not e.get(key) is String: return false
	if e.emote_id.length()!=36 or e.asset_id.length()!=64: return false
	for c in e.asset_id:
		if not c in "0123456789abcdef": return false
	for key in ["frame_width","frame_height","columns"]:
		if not e.get(key) is float and not e.get(key) is int: return false
		if float(e[key])!=int(e[key]) or int(e[key])<1: return false
	if e.frame_width>160 or e.frame_height>160 or e.columns>8: return false
	if not e.get("durations") is Array or e.durations.is_empty() or e.durations.size()>120: return false
	for d in e.durations:
		if not d is float and not d is int: return false
		if d<20 or d>10000: return false
	return true

static func load_atlas(e: Dictionary, _origin: String, _tree: SceneTree) -> Texture2D:
	if not valid(e): return null
	var id: String=e.asset_id
	if textures.has(id): return textures[id]
	if Time.get_ticks_msec()-int(failed.get(id,-60000))<15000: return null
	var bundled := "res://data/emotes/"+id+".bin"
	var bytes := FileAccess.get_file_as_bytes(bundled) if FileAccess.file_exists(bundled) else PackedByteArray()
	var texture: Texture2D
	if _matches(bytes,id):
		var image := Image.new()
		if image.load_png_from_buffer(bytes)==OK and image.get_width()==int(e.frame_width)*int(e.columns) and image.get_height()==int(e.frame_height)*ceili(float(e.durations.size())/float(e.columns)):
			texture=ImageTexture.create_from_image(image)
	if texture:
		while textures.size()>=LIMIT: textures.erase(textures.keys()[0])
		textures[id]=texture
	else: failed[id]=Time.get_ticks_msec()
	return texture

static func _matches(bytes: PackedByteArray, id: String) -> bool:
	if bytes.is_empty() or bytes.size()>8*1024*1024: return false
	var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	return hash.finish().hex_encode()==id
