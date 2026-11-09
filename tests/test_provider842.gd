extends "res://tests/test_reports842.gd"
func _initialize() -> void:
 fixtures=JSON.parse_string(FileAccess.get_file_as_string("res://tests/provider842.json")).cards
 for r in fixtures:
  var c:=_compile(r.definition)
  _check(c.definition_hash==r.definition_hash and c.compiled_program_hash==r.compiled_program_hash,"actual provider parity")
 _kill();_faction();_choice();_return()
 print("PROVIDER842: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
