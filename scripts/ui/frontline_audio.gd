extends Node
signal sound_played(key: String)
## Client-only presentation service. Created by main, compatible with PCK updates.
const CONFIG := "user://audio.cfg"
const SOUNDS := ["click","open","close","card","draw","deploy","move","attack","damage","death","counter","order","heal","turn","victory","defeat"]
const DEFAULTS := {"master":0.8,"music":0.32,"effects":0.7,"muted":false,"background_mute":true,"animations":true}
var preferences: Dictionary = DEFAULTS.duplicate()
var enabled := DisplayServer.get_name() != "headless"
var config_path := CONFIG
var scene := ""
var field_music := ""
var music_revision := 0
var suspended := false
var music_players: Array[AudioStreamPlayer] = []
var voices: Array[AudioStreamPlayer] = []
var gains := [0.0,0.0]
var targets := [0.0,0.0]
var tracks: Dictionary = {}
var sounds: Dictionary = {}
var cooldowns: Dictionary = {}
var _voice := 0
var _music_slot := 0
var _save_due := -1.0

static func service(context: Node) -> Node:
	if not is_instance_valid(context) or not context.is_inside_tree(): return null
	return context.get_tree().get_first_node_in_group("frontline_audio")

static func cue(context: Node, key: String) -> void:
	var manager := service(context)
	if manager != null: manager.sound(key)

static func reveal(context: Node, control: Control) -> void:
	var manager := service(context)
	if manager != null: manager.fade_in(control)

func _ready() -> void:
	add_to_group("frontline_audio")
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_preferences()
	for key in SOUNDS: sounds[key] = load("res://assets/audio/"+key+".ogg")
	for key in ["menu","battle"]: tracks[key] = load("res://assets/audio/"+key+".ogg")
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.volume_db = -80
		add_child(player)
		music_players.append(player)
	for i in 10:
		var player := AudioStreamPlayer.new()
		add_child(player)
		voices.append(player)
	get_tree().node_added.connect(_node_added)
	for node in get_parent().find_children("*", "BaseButton", true, false): _wire_button(node)

func load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(config_path) != OK: return
	for key in DEFAULTS:
		var value: Variant = config.get_value("audio",key,DEFAULTS[key])
		if DEFAULTS[key] is bool:
			if value is bool: preferences[key] = value
		elif (value is float or value is int) and is_finite(float(value)):
			preferences[key] = clampf(float(value),0,1)

func set_preference(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key): return
	if DEFAULTS[key] is bool:
		if not value is bool: return
	elif not (value is float or value is int) or not is_finite(float(value)): return
	else: value = clampf(float(value),0,1)
	preferences[key] = value
	_save_due = 0.25
	_apply_volumes()

func save_preferences() -> void:
	var config := ConfigFile.new()
	for key in preferences: config.set_value("audio",key,preferences[key])
	config.save(config_path)
	_save_due = -1

func _exit_tree() -> void:
	if _save_due >= 0: save_preferences()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		suspended = true
		_apply_volumes()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_APPLICATION_RESUMED]:
		suspended = false
		_apply_volumes()

func silent() -> bool:
	return not enabled or bool(preferences.muted) or float(preferences.master)<=0 or (suspended and bool(preferences.background_mute))

func set_scene(next: String) -> void:
	if next != "battle": field_music=""; music_revision+=1
	if next == scene or not tracks.has(next): return
	scene = next
	_crossfade(tracks[next])

func _crossfade(stream: AudioStream) -> void:
	_music_slot = 1-_music_slot
	var player := music_players[_music_slot]
	player.stop()
	player.stream = stream
	player.volume_db = -80
	gains[_music_slot] = 0.0
	targets = [0.0,0.0]
	targets[_music_slot] = 1.0
	if enabled: player.play()
	_apply_volumes()

func sound(key: String) -> bool:
	if silent() or float(preferences.effects)<=0 or not sounds.has(key): return false
	var now := Time.get_ticks_msec()
	# Bound simultaneous area damage and double-click spam without dropping later actions.
	var gap := 65 if key in ["damage","death","draw","deploy"] else 45
	if now-int(cooldowns.get(key,-1000)) < gap: return false
	cooldowns[key] = now
	var player := voices[_voice]
	_voice = (_voice+1)%voices.size()
	player.stop()
	player.stream = sounds[key]
	player.volume_db = linear_to_db(maxf(0.0001,float(preferences.master)*float(preferences.effects)))
	player.play()
	sound_played.emit(key)
	return true

func _apply_volumes() -> void:
	var quiet := silent()
	for i in music_players.size():
		var player := music_players[i]
		player.stream_paused = quiet or float(preferences.music)<=0
		player.volume_db = linear_to_db(maxf(0.0001,float(gains[i])*float(preferences.master)*float(preferences.music)))
	for player in voices:
		if quiet or float(preferences.effects)<=0: player.stop()
		else: player.volume_db = linear_to_db(maxf(0.0001,float(preferences.master)*float(preferences.effects)))

func _process(delta: float) -> void:
	if _save_due >= 0:
		_save_due -= delta
		if _save_due < 0: save_preferences()
	if silent(): return
	for i in music_players.size():
		gains[i] = move_toward(float(gains[i]),float(targets[i]),delta/0.9)
		var player := music_players[i]
		if targets[i] == 0.0 and gains[i] == 0.0:
			player.stop()
		elif targets[i] > 0 and float(preferences.music)>0:
			# Non-looping recordings end naturally, then fade back in on the next pass.
			if not player.playing:
				gains[i] = 0.0
				player.play()
			elif player.get_playback_position() > player.stream.get_length()-1.4:
				gains[i] = minf(float(gains[i]),maxf(0.0,(player.stream.get_length()-player.get_playback_position())/1.4))
	_apply_volumes()

func fade_in(control: Control) -> void:
	if not bool(preferences.animations) or not is_instance_valid(control): return
	if control.has_meta("ui_fade"):
		var previous: Tween = control.get_meta("ui_fade")
		if previous.is_valid(): previous.kill()
	control.modulate.a = 0.0
	var tween := control.create_tween()
	control.set_meta("ui_fade",tween)
	tween.tween_property(control,"modulate:a",1.0,0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _node_added(node: Node) -> void:
	if node is BaseButton: _wire_button.call_deferred(node)

func _wire_button(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or not get_parent().is_ancestor_of(node) or node.has_meta("feedback_wired"): return
	var button := node as BaseButton
	button.set_meta("feedback_wired",true)
	button.button_down.connect(func():
		if not button.disabled: card_sound("select",button.spec.get("media",{}),"card") if button.has_method("effect_badges") else sound("click")
	)
	# Card motion is owned by battle_view. Only ordinary buttons get a tint tween.
	if button.has_method("effect_badges") or button.get_script() == preload("res://scripts/ui/battle_props.gd"): return
	button.mouse_entered.connect(func(): _tint(button,Color(1.10,1.08,1.04)))
	button.mouse_exited.connect(func(): _tint(button,Color.WHITE))
	button.button_down.connect(func(): _tint(button,Color(0.82,0.85,0.82)))
	button.button_up.connect(func(): _tint(button,Color.WHITE))
	if button is OptionButton: button.item_selected.connect(func(_index): sound("click"))

func _tint(button: BaseButton, color: Color) -> void:
	if not is_instance_valid(button) or button.disabled: return
	if button.has_meta("ui_tint"):
		var previous: Tween = button.get_meta("ui_tint")
		if previous.is_valid(): previous.kill()
	if not bool(preferences.animations): button.self_modulate = Color.WHITE; return
	var tween := button.create_tween()
	button.set_meta("ui_tint",tween)
	tween.tween_property(button,"self_modulate",color,0.12)

static func card_cue(context: Node, key: String, media: Dictionary, fallback: String) -> void:
	var manager:=service(context)
	if manager!=null: manager.card_sound(key,media,fallback)

func preload_media(media: Dictionary) -> void:
	for id in media.get("sounds",{}).values(): CardSoundCache.fetch(str(id),get_tree())

func card_sound(key: String, media: Dictionary, fallback: String) -> bool:
	var id:=str(media.get("sounds",{}).get(key,""))
	var stream:=CardSoundCache.cached(id)
	if stream==null:
		if not id.is_empty(): CardSoundCache.fetch(id,get_tree())
		return sound(fallback)
	if silent() or float(preferences.effects)<=0: return false
	var now:=Time.get_ticks_msec()
	if now-int(cooldowns.get(id,-1000))<65:return false
	cooldowns[id]=now
	var player:=voices[_voice]
	_voice=(_voice+1)%voices.size()
	player.stop()
	player.stream=stream
	player.volume_db=linear_to_db(maxf(0.0001,float(preferences.master)*float(preferences.effects)))
	player.play()
	sound_played.emit(key)
	return true

func set_field_music(id: String) -> void:
	if scene!="battle" or id==field_music:return
	field_music=id
	music_revision+=1
	var revision:=music_revision
	# Always discard the previous field immediately, even during a slow download.
	_crossfade(tracks.battle)
	if id.is_empty():return
	var stream:=await CardSoundCache.fetch(id,get_tree())
	if not is_inside_tree() or revision!=music_revision or scene!="battle" or stream==null:return
	_crossfade(stream)
