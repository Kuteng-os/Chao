extends "res://tests/test_ui.gd"
const Audio = preload("res://scripts/ui/frontline_audio.gd")
const Prop = preload("res://scripts/ui/battle_props.gd")
const Playback = preload("res://scripts/ui/battle_presentation.gd")

func _run() -> void:
	root.size = Vector2i(1440,900)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.store.settings.backend_url = "http://127.0.0.1:1"
	await process_frame
	var manager: Audio = app.audio_system
	manager.config_path = "user://audio-regression.cfg"
	manager.preferences = Audio.DEFAULTS.duplicate()
	manager.enabled = true
	manager.suspended = false
	manager.set_scene("battle")
	check(manager.music_players[manager._music_slot].playing,"Battle music starts")
	var slot := manager._music_slot
	manager.set_scene("battle")
	check(slot==manager._music_slot,"Repeated snapshot does not restart music")
	manager.set_scene("menu")
	check(slot!=manager._music_slot and manager.targets[slot]==0,"Music crossfades between scenes")
	for key in Audio.SOUNDS:
		check(manager.sounds[key] is AudioStream and manager.sounds[key].get_length()>0,"Playable sound: "+key)
	for key in manager.tracks:
		check(manager.tracks[key].get_length()>200,"Full music recording: "+key)
	check(manager.sound("damage"),"Effect plays")
	check(not manager.sound("damage"),"Simultaneous duplicate impacts are bounded")
	manager.set_preference("muted",true)
	check(not manager.sound("click") and manager.music_players[manager._music_slot].stream_paused,"Mute immediately pauses music and suppresses effects")
	for voice in manager.voices: check(not voice.playing,"Mute stops active effect voices")
	manager.set_preference("muted",false)
	manager._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(manager.silent() and not manager.sound("card"),"Background mute")
	manager._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not manager.silent(),"Audio resumes in foreground")
	manager.set_preference("music",0)
	check(manager.music_players[manager._music_slot].stream_paused,"Zero music volume suspends the recording")
	manager.set_preference("music",0.24)
	manager.set_preference("effects",0.43)
	manager.save_preferences()
	var restored := Audio.new()
	restored.config_path = manager.config_path
	restored.load_preferences()
	check(restored.preferences.music==0.24 and restored.preferences.effects==0.43,"Per-device audio preferences persist")
	restored.free()
	manager.set_preference("master",5)
	check(manager.preferences.master==1.0,"Volume clamped")
	manager.set_preference("master",NAN)
	check(manager.preferences.master==1.0,"NaN rejected")
	manager.set_preference("master",0.3)
	if capture:
		var recorder := AudioEffectCapture.new()
		recorder.buffer_length = 0.3
		var effect_index := AudioServer.get_bus_effect_count(0)
		AudioServer.add_bus_effect(0,recorder)
		manager.sound("deploy")
		await create_timer(0.18).timeout
		var samples := recorder.get_buffer(recorder.get_frames_available())
		var peak := 0.0
		for sample in samples: peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		check(peak>0.00001,"Native audio mixer produces a non-silent signal")
		manager.set_preference("muted",true)
		await create_timer(0.15).timeout
		recorder.clear_buffer()
		await create_timer(0.12).timeout
		peak = 0
		for sample in recorder.get_buffer(recorder.get_frames_available()): peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		check(peak<0.00001,"Native mixer is silent after mute")
		AudioServer.remove_bus_effect(0,effect_index)
		manager.set_preference("muted",false)
	# Use the actual presentation scheduler: one sound per cue, even across frames.
	var played: Array = []
	manager.sound_played.connect(func(key): played.append(key))
	manager.cooldowns.clear()
	var playback := Playback.new()
	app.add_child(playback)
	playback.play([{"kind":"counter_reveal","owner":1,"name":"伏击"},{"kind":"turn_start","owner":0}],{},{},[],0)
	playback._process(0.2)
	playback._process(0.02)
	check(played.count("counter")==1,"Counter sound fires once at its animation cue")
	playback._process(0.4)
	check(played.count("turn")==1,"Turn sound follows timeline")
	playback.finish()
	var count := played.size()
	playback._process(2)
	check(played.size()==count,"Finished/replayed frame has no repeated audio")
	playback.queue_free()
	for phone in [false,true]:
		app.mobile = phone
		root.size = Vector2i(1280,800) if phone else Vector2i(1440,900)
		app._audio_dialog()
		await create_timer(0.22).timeout
		var slider := app.overlay.find_child("Audio_music",true,false) as HSlider
		check(slider!=null,"Audio controls accessible")
		slider.value = 37
		check(manager.preferences.music==0.37,"Slider updates volume live")
		check(slider.get_global_rect().end.x<=root.get_visible_rect().size.x,"Audio controls fit screen")
		await snap("audio-mobile" if phone else "audio-desktop")
		app._close_modal()
	# Distinct colors/icons and a safe neutral fallback, without individual card IDs.
	root.size = Vector2i(1440,900)
	var canvas := ColorRect.new()
	canvas.color = Color("131c19")
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.add_child(canvas)
	var icon := Image.create(40,40,false,Image.FORMAT_RGBA8)
	icon.fill(Color.TRANSPARENT)
	icon.fill_rect(Rect2i(15,4,10,32),Color("f4dfb0"))
	icon.fill_rect(Rect2i(4,15,32,10),Color("f4dfb0"))
	var icon_id := "a".repeat(64)
	CardArtCache.textures[icon_id] = ImageTexture.create_from_image(icon)
	FactionCatalog.entries = {"red":{"color":"#9a4b3b","icon_id":icon_id},"blue":{"color":"#345e7a","icon_id":icon_id},"gold":{"color":"#b59b55","icon_id":null}}
	for i in 4:
		var back := Prop.new()
		back.faction_id = ["red","blue","gold","missing"][i]
		back.size = Vector2(185,276)
		back.position = Vector2(235+i*245,290)
		canvas.add_child(back)
		check(back.back_color==[Color("9a4b3b"),Color("345e7a"),Color("b59b55"),Color("333f33")][i],"Registered color or offline fallback")
		check((back.faction_icon!=null)==(i<2),"Registered icon or neutral insignia")
	await snap("faction-card-backs")
	manager.preferences = Audio.DEFAULTS.duplicate()
	manager.save_preferences()
	app.queue_free()
	await process_frame
	print("AUDIO_BACK_RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
