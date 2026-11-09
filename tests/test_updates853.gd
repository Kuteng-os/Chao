extends SceneTree
const Updater=preload("res://scripts/client_update.gd")
var checks:=0
var failures:=0
class MockTransport extends "res://scripts/client_update.gd":
 var response_envelope:Dictionary={}
 var download_requests:=0
 func _request(_path:String,output:String="") -> Array:
  if not output.is_empty():download_requests+=1
  return [HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify(response_envelope).to_utf8_buffer()]
func _initialize() -> void: run.call_deferred()
func check(value:bool,message:String) -> void:
 checks+=1
 if not value:failures+=1;push_error(message)
func run() -> void:
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/updates853.json"))
 var updater:=MockTransport.new()
 updater.public_key=CryptoKey.new()
 updater.public_key.load_from_string(fixture.public_key,true)
 check(not updater.verify(fixture.older).is_empty(),"valid older signed release is not a bad signature")
 check(not updater.verify(fixture.current).is_empty(),"current signed release validates")
 check(not updater.verify(fixture.newer).is_empty(),"newer signed release validates")
 check(updater.verify(fixture.invalid_minimum).is_empty(),"minimum base cannot exceed release")
 check(updater.verify(fixture.invalid_build).is_empty(),"invalid release build rejected")
 var modified:Dictionary=fixture.newer.duplicate(true);modified.payload+=" "
 check(updater.verify(modified).is_empty(),"tampered payload still rejected")
 modified=fixture.newer.duplicate(true);modified.signature="AAAA"
 check(updater.verify(modified).is_empty(),"forged signature still rejected")
 for kind in ["older","current","newer"]:
  updater.response_envelope=fixture[kind]
  await updater.check()
  check(updater.status==("发现新版本 0.8.54" if kind=="newer" else "已是最新版本"),"correct status for "+kind)
 updater.response_envelope=fixture.older
 await updater.check()
 await updater.download()
 check(updater.download_requests==0,"old signed release cannot be downloaded as a downgrade")
 updater.directory="user://update853-%d/" % Time.get_ticks_usec()
 DirAccess.make_dir_recursive_absolute(updater.directory)
 var active:=updater.directory+"active.json"
 var f:=FileAccess.open(active,FileAccess.WRITE);f.store_string(JSON.stringify(fixture.older));f.close()
 f=FileAccess.open(updater.directory+"boot_pending",FileAccess.WRITE);f.store_string("852");f.close()
 updater._restore_patch()
 check(updater.current_build==853,"old active patch cannot override new complete installer")
 check(not FileAccess.file_exists(updater.directory+"boot_pending"),"stale patch marker cannot poison the next update")
 check(FileAccess.file_exists(active),"historical record retained without loading it")
 DirAccess.remove_absolute(active);DirAccess.remove_absolute(updater.directory)
 updater.free()
 print("UPDATES 853: %d checks, %d failures" % [checks,failures])
 quit(0 if failures==0 else 1)
