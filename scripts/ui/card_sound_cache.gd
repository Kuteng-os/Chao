class_name CardSoundCache
extends RefCounted
static var streams: Dictionary = {}
static var running: Dictionary = {}
static var failures: Dictionary = {}

static func cached(id: String) -> AudioStreamWAV:
	return streams.get(id)

static func fetch(id: String, tree: SceneTree) -> AudioStreamWAV:
	if not CardArtCache.valid_id(id): return null
	if streams.has(id): return streams[id]
	if running.has(id):
		while running.has(id): await tree.process_frame
		return streams.get(id)
	if int(failures.get(id,0)) > Time.get_ticks_msec(): return null
	var bundled := "res://data/sounds/"+id+".bin"
	var cached := CardArtCache.directory.get_base_dir().path_join("card-sounds").path_join(id+".wav")
	var bytes := FileAccess.get_file_as_bytes(bundled) if FileAccess.file_exists(bundled) else FileAccess.get_file_as_bytes(cached) if FileAccess.file_exists(cached) else PackedByteArray()
	var downloaded := bytes.is_empty()
	if downloaded:
		running[id]=true
		bytes=await CardArtCache.download("data/sounds/"+id+".bin",16*1024*1024,tree)
		running.erase(id)
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var stream: AudioStreamWAV=null
	if bytes.size()>=46 and bytes.size()<=16*1024*1024 and hash.finish().hex_encode()==id:
		stream=AudioStreamWAV.load_from_buffer(bytes)
	if stream==null:
		failures[id]=Time.get_ticks_msec()+30000
		return null
	if downloaded:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cached.get_base_dir()))
		var file:=FileAccess.open(cached,FileAccess.WRITE)
		if file: file.store_buffer(bytes)
	if streams.size()>=32: streams.erase(streams.keys()[0])
	streams[id]=stream
	return stream
