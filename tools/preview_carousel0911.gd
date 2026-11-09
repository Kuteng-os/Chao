extends SceneTree
var carousel: Control
func _initialize() -> void: preview.call_deferred()
func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
func capture(label: String) -> void:
	await frame()
	root.get_texture().get_image().save_png("res://../../.runtime/carousel0911-"+label+".png")
func preview() -> void:
	root.size=Vector2i(800,620);root.min_size=Vector2i(640,540)
	var stage:=Control.new();stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);stage.theme=ChaoUI.make_theme(false);root.add_child(stage)
	var bg:=ColorRect.new();bg.color=Color("1c1f22");bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);stage.add_child(bg)
	var entries:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/visual090_assets/catalog.json"))
	var records:Array=[]
	var unit:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/examples/valid_unit.json"))
	for i in 4:
		var entry:Dictionary=entries[i];var spec:=unit.duplicate(true)
		spec.name=entry.name;spec["display_text"]=entry.text;spec["sin"]=["wrath","gloom","pride","envy"][i]
		CardArtCache.textures[entry.art_id]=load("res://tests/visual090_assets/"+entry.art_id+".png")
		records.append({"card_id":str(i),"definition":spec,"art":{"id":entry.art_id}})
	carousel=load("res://scripts/ui/home_card_carousel.gd").new();stage.add_child(carousel)
	carousel.configure(records,func(r):return r.definition,270)
	carousel.position=Vector2(245,70);carousel.size=carousel.custom_minimum_size
	carousel.set_process(false);carousel.app_paused=false;root.warp_mouse(Vector2(3,3))
	await frame();await capture("rest")
	var shown:Array=[carousel.current_index]
	carousel._process(5.01);carousel._process(0.26)
	await capture("transition")
	carousel._process(0.30);await capture("next")
	shown.append(carousel.current_index)
	for i in 6:
		carousel._process(5.01);carousel._process(0.60);shown.append(carousel.current_index);await frame()
	print("SHUFFLED_CARDS ",shown)
	var before:float=carousel.elapsed
	root.warp_mouse(carousel.get_global_rect().get_center());await frame();carousel._process(7)
	print("HOVER_TIMER ",before," -> ",carousel.elapsed)
	root.warp_mouse(Vector2(3,3));carousel.blocked=func():return true;carousel._process(7)
	print("DETAILS_TIMER ",carousel.elapsed)
	carousel.blocked=Callable();carousel.app_paused=true;carousel._process(7);print("BACKGROUND_TIMER ",carousel.elapsed)
	carousel.card_selected.connect(func(record):print("DETAILS_CARD ",record.card_id))
	carousel.current.pressed.emit()
	stage.queue_free();await frame();quit()
