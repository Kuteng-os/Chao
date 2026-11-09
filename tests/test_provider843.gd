extends "res://tests/test_engine.gd"
func _initialize() -> void:
 var fixtures: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/provider843.json")).cards
 for f in fixtures:
  var c:=_compile(f.definition)
  _check(c.definition_hash==f.definition_hash and c.compiled_program_hash==f.compiled_program_hash,"real provider cross runtime")
  _check(not "undefined" in Runtime.rules_text(c),"real result text")
 print("PROVIDER843: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
