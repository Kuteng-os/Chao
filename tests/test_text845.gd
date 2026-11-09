extends "res://tests/test_text844.gd"
func _initialize() -> void:
 var cases=JSON.parse_string(FileAccess.get_file_as_string("res://tests/text845-cases.json"))
 for pair in cases:
  _check(Runtime.short_text(pair[0])==pair[1],"compact phrase: "+Runtime.short_text(pair[0]))
 super._initialize()
