extends SceneTree
const Audio=preload("res://scripts/ui/frontline_audio.gd")
var failures:=0
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var parent:=Node.new();root.add_child(parent)
	var manager:=Audio.new();manager.config_path="user://audio846-test.cfg";parent.add_child(manager)
	manager.enabled=true;manager.preferences=Audio.DEFAULTS.duplicate()
	check(absf(manager.tracks.menu.get_length()-128.935)<.1,"Menu plays selected full Touhou arrangement")
	check(absf(manager.tracks.battle.get_length()-95.659)<.1,"Battle plays selected full Touhou arrangement")
	manager.set_scene("menu");check(manager.music_players[manager._music_slot].playing,"Menu starts")
	var previous:=manager._music_slot
	manager.set_scene("battle");check(manager._music_slot!=previous and manager.targets[previous]==0,"Scene change crossfades")
	previous=manager._music_slot;manager.set_scene("battle");check(previous==manager._music_slot,"Snapshot does not restart battle song")
	manager.music_players[previous].stop();manager._process(.1)
	check(manager.music_players[previous].playing,"Completed song restarts")
	manager.set_preference("muted",true);check(manager.music_players[previous].stream_paused,"Mute applies to replacement music")
	manager.set_preference("muted",false);check(not manager.music_players[previous].stream_paused,"Music resumes")
	for key in Audio.SOUNDS:check(manager.sounds[key].get_length()>0,"Sound effect retained: "+key)
	manager.set_process(false)
	for player in manager.music_players+manager.voices:player.stop();player.stream=null
	await create_timer(.2).timeout
	manager._save_due=-1;parent.queue_free();await create_timer(.2).timeout
	print("MUSIC846: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
