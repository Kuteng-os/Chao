extends SceneTree
func _initialize() -> void:
	for p in ClassDB.class_get_property_list("SystemFont"):
		if "oversampl" in p.name or "subpixel" in p.name or "antialias" in p.name:print(p)
	quit()
