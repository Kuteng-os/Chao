extends SceneTree
func _initialize() -> void:
	var folder := "res://.runtime/update-fixture"
	DirAccess.make_dir_recursive_absolute(folder)
	var f := FileAccess.open(folder + "/probe.txt", FileAccess.WRITE)
	f.store_string("PATCH_ACTIVATED")
	f.close()
	var p := PCKPacker.new()
	assert(p.pck_start(folder + "/patch.pck") == OK)
	assert(p.add_file("res://patch_probe.txt", folder + "/probe.txt") == OK)
	assert(p.flush() == OK)
	quit()
