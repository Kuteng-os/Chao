class_name BattleSceneCatalog
extends RefCounted
## Presentation-only registry. New scenes can add a JSON preset and an optional PackedScene.
static var _entries: Array = []
static var _selected := ""
static var quality := "balanced"
static func entries() -> Array:
	if _entries.is_empty():
		var index: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/battle_scenes/catalog.json"))
		for path in index.get("scenes",[]):
			var preset: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
			if preset is Dictionary and preset.has("id") and preset.has("name"): _entries.append(preset)
	return _entries
static func selected() -> String:
	if _selected.is_empty():
		var config:=ConfigFile.new()
		config.load("user://visuals.cfg")
		_selected=str(config.get_value("visuals","scene","rooftop"))
		quality=str(config.get_value("visuals","quality","balanced"))
	return _selected
static func preset(id: String = "") -> Dictionary:
	if id.is_empty(): id=selected()
	for item in entries():
		if item.id==id:return item
	return entries()[0]
static func choose(id: String, next_quality := "") -> void:
	_selected=str(preset(id).id)
	if next_quality in ["balanced","high","low"]: quality=next_quality
	var config:=ConfigFile.new()
	config.set_value("visuals","scene",_selected)
	config.set_value("visuals","quality",quality)
	config.save("user://visuals.cfg")
