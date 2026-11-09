extends "res://scripts/client_update.gd"
# Exercise installation and failure handling without accessing the public release server.
var source := ""
var corrupt := false
func _ready() -> void:
	pass
func _request(_path: String, output: String = "") -> Array:
	if corrupt:
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string("incomplete transfer")
		file.close()
	else:
		DirAccess.copy_absolute(source, output)
	return [HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), PackedByteArray()]
