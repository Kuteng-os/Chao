extends TextureRect
const Cache = preload("res://scripts/ui/emote_cache.gd")
var entry: Dictionary = {}
var origin := ""
var _frame := 0
var _elapsed := 0.0
var _atlas: AtlasTexture
var _started := false

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED

func _load() -> void:
	if not Cache.valid(entry): return
	var tree := get_tree()
	var loaded: Texture2D=await Cache.load_atlas(entry,origin,tree)
	if not is_inside_tree() or not loaded: return
	_atlas=AtlasTexture.new();_atlas.atlas=loaded;texture=_atlas;_paint()

func _paint() -> void:
	_atlas.region=Rect2((_frame%int(entry.columns))*int(entry.frame_width),(_frame/int(entry.columns))*int(entry.frame_height),entry.frame_width,entry.frame_height)

func _visible_area() -> bool:
	if not is_visible_in_tree(): return false
	var area := get_viewport_rect()
	var parent := get_parent()
	while parent is Control:
		if parent.clip_contents: area=area.intersection(parent.get_global_rect())
		parent=parent.get_parent()
	return area.intersects(get_global_rect())

func _process(delta: float) -> void:
	if not _started and _visible_area(): _started=true;_load()
	if not _atlas or entry.durations.size()<2 or not _visible_area(): return
	_elapsed+=minf(delta,0.25)*1000.0
	var previous := _frame
	while _elapsed>=float(entry.durations[_frame]):
		_elapsed-=float(entry.durations[_frame]);_frame=(_frame+1)%entry.durations.size()
	if previous!=_frame: _paint()
