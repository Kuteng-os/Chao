extends SceneTree
const Audio=preload("res://scripts/ui/frontline_audio.gd")
var failures:=0
var checks:=0
func _initialize() -> void: call_deferred("_run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1;push_error(message)
func _run() -> void:
	var host:=Node.new()
	root.add_child(host)
	var manager:=Audio.new()
	manager.config_path="user://qa-unused-media.cfg"
	host.add_child(manager)
	manager.enabled=true
	manager.preferences=Audio.DEFAULTS.duplicate()
	var pcm:=AudioStreamWAV.new()
	pcm.format=AudioStreamWAV.FORMAT_16_BITS
	pcm.mix_rate=22050
	var data:=PackedByteArray()
	data.resize(44100)
	pcm.data=data
	var id:="a".repeat(64)
	CardSoundCache.streams[id]=pcm
	check(manager.card_sound("play",{"sounds":{"play":id}},"deploy"),"custom sound accepted")
	check(manager.voices[0].stream==pcm,"custom stream selected")
	check(not manager.card_sound("play",{"sounds":{"play":id}},"deploy"),"duplicate effects rate limited")
	check(manager.card_sound("play",{},"deploy"),"unset event uses default")
	check(manager.voices[1].stream==manager.sounds.deploy,"default deployment stream selected")
	manager.preferences.muted=true
	check(not manager.card_sound("attack",{"sounds":{"attack":id}},"attack"),"custom obeys mute")
	manager.preferences.muted=false
	manager.set_scene("battle")
	await manager.set_field_music(id)
	check(manager.music_players[manager._music_slot].stream==pcm,"field replaces music")
	var slot:int=manager._music_slot
	await manager.set_field_music(id)
	check(manager._music_slot==slot,"same snapshot does not restart music")
	await manager.set_field_music("")
	check(manager.music_players[manager._music_slot].stream==manager.tracks.battle,"empty replacement restores battle default")
	await manager.set_field_music(id)
	manager.set_scene("menu")
	check(manager.field_music.is_empty() and manager.music_players[manager._music_slot].stream==manager.tracks.menu,"leaving battle clears custom music")
	manager.preferences.effects=0
	check(not manager.card_sound("play",{"sounds":{"play":id}},"deploy"),"effect volume zero silences custom")
	manager.enabled=false
	for player in manager.voices+manager.music_players: player.stop()
	CardSoundCache.streams.clear()
	host.queue_free()
	await create_timer(0.2).timeout
	print("CARD MEDIA TESTS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
