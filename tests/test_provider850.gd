extends SceneTree
func _initialize() -> void:
 var cases: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/provider850.json"))
 var failures:=0
 for item in cases:
  var compiled:=CardRuntime.compile_card(item.card,CardRuntime.builtin_keywords())
  if not compiled.ok:
   failures+=1;printerr(item.label, ": ",compiled)
 print("LIVE_PROVIDER_NATIVE_COMPILE ",cases.size()," cases, failures=",failures)
 quit(1 if failures else 0)
