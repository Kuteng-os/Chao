class_name CardArtCache
extends RefCounted
const GITHUB_RAW := "https://raw.githubusercontent.com/xiangwu738-design/Chao/main/"
static var remote_root := GITHUB_RAW
static var running: Dictionary = {}
static var origin := "https://wzb.rainplay.cn:36410"
static var directory := "user://card-art"
static var textures: Dictionary = {}
static var failures: Dictionary = {}

static func valid_id(id: String) -> bool:
	if id.length() != 64: return false
	for c in id:
		if not c in "0123456789abcdef": return false
	return true

static func valid_token_art_ids(value: Variant, definition: Dictionary) -> bool:
	if not value is Dictionary or value.size() > 12: return false
	var names := {}
	for token in definition.get("tokens", []): names[token.token_id] = true
	for key in value:
		if not names.has(key) or not value[key] is String or not valid_id(value[key]): return false
	return true

static func record_token_art_ids(record: Dictionary) -> Dictionary:
	var result := {}
	var art: Variant = record.get("token_art", {})
	if not art is Dictionary: return result
	for token in record.get("definition", {}).get("tokens", []):
		var entry: Variant = art.get(token.token_id, {})
		if entry is Dictionary and entry.get("id") is String and valid_id(entry.id): result[token.token_id] = entry.id
	return result

## Downloads a content-addressed asset published on GitHub; callers verify its SHA-256.
static func download(path: String, limit: int, tree: SceneTree) -> PackedByteArray:
	var http := HTTPRequest.new()
	http.timeout = 30
	http.max_redirects = 0
	http.body_size_limit = limit
	tree.root.add_child(http)
	var bytes := PackedByteArray()
	if http.request(remote_root+path) == OK:
		var response: Array = await http.request_completed
		if response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 200: bytes = response[3]
	http.queue_free()
	return bytes

static func load_art(id: String, tree: SceneTree) -> Texture2D:
	if not valid_id(id): return null
	if textures.has(id): return textures[id]
	if running.has(id):
		while running.has(id): await tree.process_frame
		return textures.get(id)
	if int(failures.get(id, 0)) > Time.get_ticks_msec(): return null
	var bundled := "res://data/art/"+id+".bin"
	var cached := directory.path_join(id+".png")
	var bytes := FileAccess.get_file_as_bytes(bundled) if FileAccess.file_exists(bundled) else FileAccess.get_file_as_bytes(cached) if FileAccess.file_exists(cached) else PackedByteArray()
	var downloaded := bytes.is_empty()
	if downloaded:
		running[id] = true
		bytes = await download("data/art/"+id+".bin", 5*1024*1024, tree)
		running.erase(id)
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	var picture := Image.new()
	if bytes.size() < 33 or digest.finish().hex_encode() != id or picture.load_png_from_buffer(bytes) != OK or picture.get_width() > 1024 or picture.get_height() > 1024:
		failures[id] = Time.get_ticks_msec()+30000
		return null
	if downloaded:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		var file := FileAccess.open(cached, FileAccess.WRITE)
		if file: file.store_buffer(bytes)
	if maxi(picture.get_width(), picture.get_height()) > 512:
		var scale := 512.0/maxi(picture.get_width(), picture.get_height())
		picture.resize(maxi(1, int(picture.get_width()*scale)), maxi(1, int(picture.get_height()*scale)), Image.INTERPOLATE_LANCZOS)
	if textures.size() >= 96: textures.erase(textures.keys()[0])
	textures[id] = ImageTexture.create_from_image(picture)
	return textures[id]
