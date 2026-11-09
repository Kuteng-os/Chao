extends Node
const Cache = preload("res://scripts/ui/emote_cache.gd")
signal changed
signal progress(text: String)
var store: Node
var catalog: Array = []
var slots: Array = ["","","","","","","",""]
var origin := ""
var scope := ""
var mute_opponent := false
var shortcut := KEY_T
var syncing := false
var last_error := ""
var last_sent_id := ""
var _epoch := 0
var _edit_serial := 0
var _preferences: Dictionary = {}
var _catalogs: Dictionary = {}
const FILE := "user://emotes/config.json"
const BUNDLED := "res://data/emotes.json"

func _ready() -> void:
	var saved: Variant=JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
	if saved is Dictionary:
		_preferences=saved.get("preferences",{}) if saved.get("preferences") is Dictionary else {}
		_catalogs=saved.get("catalogs",{}) if saved.get("catalogs") is Dictionary else {}
		mute_opponent=bool(saved.get("mute_opponent",false))
		var key := int(saved.get("shortcut",KEY_T))
		if key in range(KEY_A,KEY_Z+1) or key in range(KEY_F1,KEY_F12+1): shortcut=key

func bind_store(api: Node) -> bool:
	store=api
	var next_origin: String=str(api.settings.backend_url).trim_suffix("/")
	var next_scope := next_origin+"|"+str(api.settings.get("owner_id","guest"))
	if next_scope==scope: return false
	_epoch+=1;syncing=false;origin=next_origin;scope=next_scope;last_sent_id=""
	catalog=_clean_catalog(_catalogs.get(origin,[]))
	var pref: Dictionary=_preferences.get(scope,{})
	slots=_clean_slots(pref.get("slots",[]),false)
	changed.emit()
	return true

func _clean_catalog(value: Variant) -> Array:
	var result: Array=[]
	if value is Array:
		for e in value.slice(0,4096):
			if Cache.valid(e): result.append(e)
	return result

func _clean_slots(value: Variant, check_catalog: bool=true) -> Array:
	var result: Array=["","","","","","","",""]
	if value is Array and value.size()==8:
		for i in 8:
			if value[i] is String and (value[i].is_empty() or (value[i].length()==36 and (not check_catalog or not entry(value[i]).is_empty()))): result[i]=value[i]
	return result

func entry(id: String) -> Dictionary:
	for e in catalog:
		if e.emote_id==id: return e
	return {}

func repeat_id() -> String:
	return last_sent_id if slots.has(last_sent_id) and not entry(last_sent_id).is_empty() else ""

func refresh() -> bool:
	if not is_instance_valid(store): return false
	bind_store(store);last_error=""
	var bundled: Variant=JSON.parse_string(FileAccess.get_file_as_string(BUNDLED)) if FileAccess.file_exists(BUNDLED) else null
	if not bundled is Dictionary or not bundled.get("emotes") is Array:
		last_error="内置表情库缺失";return false
	catalog=_clean_catalog(bundled.emotes);_catalogs[origin]=catalog
	slots=_clean_slots(slots)
	_save();changed.emit()
	return true

func save_slots(value: Array) -> String:
	_edit_serial+=1
	slots=_clean_slots(value);_preferences[scope]={"slots":slots.duplicate(),"dirty":true}
	if not _save(): return "本地保存失败，请检查存储空间。"
	changed.emit()
	return "轮盘已保存"

func preload_slots() -> bool:
	var ids: Array=[]
	for id in slots:
		if not str(id).is_empty() and not ids.has(id) and not entry(id).is_empty(): ids.append(id)
	var state := {"pending":ids.size(),"total":ids.size(),"failed":false}
	var serial := _epoch
	for id in ids: _preload_one(entry(id),origin,state,serial)
	while state.pending>0 and serial==_epoch: await get_tree().process_frame
	return serial==_epoch and not state.failed

func _preload_one(e: Dictionary, server: String, state: Dictionary, serial: int) -> void:
	var texture: Texture2D=await Cache.load_atlas(e,server,get_tree())
	state.pending-=1
	if not texture: state.failed=true
	if serial==_epoch: progress.emit("正在加载表情 · %d / %d"%[state.total-state.pending,state.total])

func set_muted(value: bool) -> void:
	mute_opponent=value;_save();changed.emit()

func _save() -> bool:
	DirAccess.make_dir_recursive_absolute("user://emotes")
	var file := FileAccess.open(FILE+".tmp",FileAccess.WRITE)
	if not file: return false
	file.store_string(JSON.stringify({"preferences":_preferences,"catalogs":_catalogs,"mute_opponent":mute_opponent,"shortcut":shortcut}));file.close()
	return DirAccess.rename_absolute(FILE+".tmp",FILE)==OK

func set_shortcut(key: int) -> void:
	if key not in range(KEY_A,KEY_Z+1) and key not in range(KEY_F1,KEY_F12+1): return
	shortcut=key;_save();changed.emit()
