class_name CharacterCatalog
extends RefCounted
## Commander characters are prepared by the maintainers; players only choose one.
## Each lives in res://assets/characters/<id>/character.json:
##   name       shown in menus
##   portrait   static image, used where Live2D is unavailable (Android, or no plugin)
##   model      optional *.model3.json, drawn with the GDCubism extension when it is installed
##   framing    {"home": {...}, "hq": {...}, "stage": {...}}; each {"zoom": model height / frame height, "focus": [x, y] in 0..1 of the model}.
##              Frame the upper body (head to waist); the defaults already do this for a typical full-body model.
##   portrait_framing  the same for the portrait, when it is cropped differently from the model
##   actions    {"idle"|"play"|"attack"|"hit"|"turn"|"win"|"lose": {"motion": [group, no], "expression": id, "hold": seconds}}
##   home       {"idle"|"touch_head"|"touch_body": [action, ...]} for the home page: idle actions while the player is away,
##              and reactions to clicks on the head or body. Missing lists fall back to the match actions above.
## For local testing of models that may not be distributed, CHAO_CHARACTER_DIR may name a folder laid out the same way;
## it is read only in debug builds and its files never enter the repository or an export.
const DEFAULT_ID := "commander"
const ACTIONS := ["idle", "play", "attack", "hit", "turn", "win", "lose"]
const ID_PATTERN := "^[a-z0-9_-]{1,32}$"
static var _entries: Dictionary = {}
static var _order: Array = []
static var _selected := ""
static var _model_settings: Dictionary = {}

static func _scan(root: String, local: bool) -> void:
	var directory := DirAccess.open(root)
	if directory == null: return
	var folders := Array(directory.get_directories())
	folders.sort()
	for folder in folders:
		var id := str(folder)
		if not valid_id(id) or _entries.has(id): continue
		var path := root.path_join(id).path_join("character.json")
		if not FileAccess.file_exists(path): continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary: continue
		var entry: Dictionary = parsed
		entry["id"] = id
		entry["root"] = root.path_join(id)
		entry["local"] = local
		entry["name"] = str(entry.get("name", id)).left(24)
		_entries[id] = entry
		_order.append(id)

static func _load() -> void:
	if not _entries.is_empty(): return
	_scan("res://assets/characters", false)
	var local := OS.get_environment("CHAO_CHARACTER_DIR")
	if OS.is_debug_build() and not local.is_empty(): _scan(local, true)
	if not _entries.has(DEFAULT_ID):
		_entries[DEFAULT_ID] = {"id": DEFAULT_ID, "name": "指挥官", "root": "", "local": false}
		_order.push_front(DEFAULT_ID)

static func reload() -> void:
	_model_settings.clear()
	_entries.clear()
	_order.clear()
	_load()

static func valid_id(id: String) -> bool:
	var pattern := RegEx.create_from_string(ID_PATTERN)
	return pattern.search(id) != null

static func entries() -> Array:
	_load()
	return _order.map(func(id): return _entries[id])

static func has(id: String) -> bool:
	_load()
	return _entries.has(id)

## Unknown ids (an opponent's character this client does not have) fall back to the default commander.
static func info(id: String = "") -> Dictionary:
	_load()
	if id.is_empty(): id = selected()
	return _entries.get(id, _entries[DEFAULT_ID])

static func selected() -> String:
	if _selected.is_empty():
		var config := ConfigFile.new()
		config.load("user://visuals.cfg")
		_selected = str(config.get_value("character", "id", DEFAULT_ID))
	return _selected if has(_selected) else DEFAULT_ID

static func choose(id: String) -> void:
	if not has(id): return
	_selected = id
	var config := ConfigFile.new()
	config.load("user://visuals.cfg")
	config.set_value("character", "id", id)
	config.save("user://visuals.cfg")

## Players may keep the HQ slot as the plain headquarters card; the home page and the result stage still show the character.
static func hq_enabled() -> bool:
	var config := ConfigFile.new()
	config.load("user://visuals.cfg")
	return bool(config.get_value("character", "hq", true))

static func set_hq_enabled(on: bool) -> void:
	var config := ConfigFile.new()
	config.load("user://visuals.cfg")
	config.set_value("character", "hq", on)
	config.save("user://visuals.cfg")

## Live2D update rate: "smooth" steps the home model every frame, "balanced" (default) every other frame, "saver" every
## third frame with smaller masks. Each step of a detailed model costs several milliseconds.
const LIVE2D_QUALITY := {
	"smooth": {"name": "流畅", "home": 1, "stage": 1, "hq": 2, "mask": 512},
	"balanced": {"name": "均衡", "home": 2, "stage": 2, "hq": 3, "mask": 512},
	"saver": {"name": "省电", "home": 3, "stage": 3, "hq": 4, "mask": 256},
}

static func live2d_quality() -> String:
	var config := ConfigFile.new()
	config.load("user://visuals.cfg")
	var value := str(config.get_value("character", "quality", "balanced"))
	return value if LIVE2D_QUALITY.has(value) else "balanced"

static func set_live2d_quality(value: String) -> void:
	if not LIVE2D_QUALITY.has(value): return
	var config := ConfigFile.new()
	config.load("user://visuals.cfg")
	config.set_value("character", "quality", value)
	config.save("user://visuals.cfg")

## The player's own placement of a character on the home screen: offset as a fraction of the frame, and a zoom factor.
static func home_layout(id: String) -> Dictionary:
	var config := ConfigFile.new()
	config.load("user://visuals.cfg")
	var value: Variant = config.get_value("character_layout", id, [])
	if value is Array and value.size() == 3:
		return {"offset": Vector2(float(value[0]), float(value[1])), "zoom": clampf(float(value[2]), 0.4, 3.0)}
	return {"offset": Vector2.ZERO, "zoom": 1.0}

static func set_home_layout(id: String, offset: Vector2, zoom: float) -> void:
	var config := ConfigFile.new()
	config.load("user://visuals.cfg")
	if offset == Vector2.ZERO and is_equal_approx(zoom, 1.0):
		if config.has_section_key("character_layout", id): config.erase_section_key("character_layout", id)
	else: config.set_value("character_layout", id, [snappedf(offset.x, 0.0001), snappedf(offset.y, 0.0001), snappedf(zoom, 0.0001)])
	config.save("user://visuals.cfg")

static func file(entry: Dictionary, key: String) -> String:
	var name := str(entry.get(key, ""))
	if name.is_empty() or str(entry.get("root", "")).is_empty(): return ""
	# Local test characters may point at a model kept wherever its licence allows; bundled ones stay in their folder.
	var path := name if entry.get("local", false) and name.is_absolute_path() else str(entry.root).path_join(name)
	return path if FileAccess.file_exists(path) else ""

## "framing" positions the Live2D model; "portrait_framing", when present, positions the static portrait instead.
static func framing(entry: Dictionary, place: String, portrait := false) -> Dictionary:
	# Characters are shown half-length everywhere. Zoom and focus refer to the model's canvas, which for a typical full-body
	# (VTube Studio style) model is a good deal taller than the figure itself; the defaults crop such a model to head-to-waist.
	# Portraits (and the drawn default) are already busts and are framed as they are.
	var defaults := {"home": {"zoom": 2.7, "focus": [0.5, 0.28]}, "hq": {"zoom": 4.0, "focus": [0.5, 0.22]}, "stage": {"zoom": 2.8, "focus": [0.5, 0.27]}}
	if portrait: defaults = {"home": {"zoom": 0.8, "focus": [0.5, 0.5]}, "hq": {"zoom": 1.2, "focus": [0.5, 0.56]}, "stage": {"zoom": 0.85, "focus": [0.5, 0.5]}}
	var source: Variant = entry.get("portrait_framing" if portrait and entry.has("portrait_framing") else "framing", {})
	var value: Variant = source.get(place, defaults.get(place, defaults.home)) if source is Dictionary else defaults.home
	if not value is Dictionary: value = defaults.home
	var focus: Variant = value.get("focus", [0.5, 0.5])
	var point := Vector2(0.5, 0.5)
	if focus is Array and focus.size() == 2: point = Vector2(float(focus[0]), float(focus[1]))
	return {"zoom": clampf(float(value.get("zoom", 1.0)), 0.2, 8.0), "focus": point}

## Path of the motion3.json registered as Motions[group][no] in the character's model3.json, or "" when there is none.
static func motion_file(entry: Dictionary, group: String, no: int) -> String:
	var model_path := file(entry, "model")
	if model_path.is_empty(): return ""
	if not _model_settings.has(model_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(model_path))
		_model_settings[model_path] = parsed if parsed is Dictionary else {}
	var references: Variant = _model_settings[model_path].get("FileReferences", {})
	var motions: Variant = references.get("Motions", {}) if references is Dictionary else {}
	var listed: Variant = motions.get(group, []) if motions is Dictionary else []
	if not listed is Array or no < 0 or no >= listed.size() or not listed[no] is Dictionary: return ""
	var relative := str(listed[no].get("File", ""))
	if relative.is_empty() or relative.is_absolute_path() or ".." in relative.split("/"): return ""
	var path := model_path.get_base_dir().path_join(relative)
	return path if FileAccess.file_exists(path) else ""

static func home_actions(entry: Dictionary, kind: String) -> Array:
	var home: Variant = entry.get("home", {})
	var listed: Variant = home.get(kind, []) if home is Dictionary else []
	var result := []
	if listed is Array:
		for item in listed:
			if item is Dictionary: result.append(item)
	if not result.is_empty(): return result
	var fallback := {"idle": ["turn", "play"], "touch_head": ["turn"], "touch_body": ["play", "attack"]}
	for name in fallback.get(kind, []):
		result.append(action(entry, name))
	return result

static func action(entry: Dictionary, name: String) -> Dictionary:
	var value: Variant = entry.get("actions", {}).get(name, {})
	return value if value is Dictionary else {}

## The Live2D extension is optional: Android and builds without it show the portrait instead.
static func live2d_available() -> bool:
	return ClassDB.class_exists("GDCubismUserModel")
