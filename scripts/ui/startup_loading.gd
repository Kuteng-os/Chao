extends Control
signal continue_requested
signal retry_requested
var labels: Dictionary={}
var progress_bar: ProgressBar
var continue_button: Button
var retry_button: Button
var note: Label
var _started := 0
var _finished := false

func _ready() -> void:
	z_index=1000
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP
	theme=ChaoUI.make_theme(OS.has_feature("mobile"))
	var background:=ColorRect.new();background.color=Color(0.018,0.035,0.048,0.94);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(center)
	var box:=VBoxContainer.new();box.custom_minimum_size=Vector2(540,0);box.add_theme_constant_override("separation",22);center.add_child(box)
	var mark:=preload("res://scripts/ui/boot_mark.gd").new();mark.custom_minimum_size=Vector2(180,158);box.add_child(mark)
	var title:=Label.new();title.text="巢 战";title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_theme_font_size_override("font_size",42);box.add_child(title)
	note=Label.new();note.text="正在准备进入都市";note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;note.add_theme_font_size_override("font_size",14);note.add_theme_color_override("font_color",ChaoUI.MUTED);note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(note)
	progress_bar=ProgressBar.new();progress_bar.max_value=3;progress_bar.show_percentage=false;progress_bar.custom_minimum_size.y=3;box.add_child(progress_bar)
	for key in ["cards","emotes","update"]:
		var label:=Label.new();label.text={"cards":"卡库 · 同步中","emotes":"表情 · 准备中","update":"版本 · 检查中"}[key];label.add_theme_font_size_override("font_size",13);label.add_theme_color_override("font_color",ChaoUI.MUTED);labels[key]=label;box.add_child(label)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);box.add_child(row)
	retry_button=Button.new();retry_button.text="重试";ChaoUI.skin_button(retry_button);retry_button.visible=false;row.add_child(retry_button);retry_button.pressed.connect(func():retry_requested.emit())
	continue_button=Button.new();continue_button.text="使用本地数据进入";ChaoUI.skin_button(continue_button,true);continue_button.visible=false;continue_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(continue_button);continue_button.pressed.connect(func():continue_requested.emit())
	_started=Time.get_ticks_msec()

func _process(_delta: float) -> void:
	if not _finished and Time.get_ticks_msec()-_started>8000:
		continue_button.visible=true;note.text="网络较慢，可以先使用本地数据进入，更新会在后台继续。"

func stage(key: String, text: String, ok: bool) -> void:
	if not labels.has(key): return
	labels[key].text=("✓ " if ok else "· ")+text
	labels[key].add_theme_color_override("font_color",ChaoUI.ACCENT if ok else Color("dfb38b"))
	if not labels[key].has_meta("done"):
		labels[key].set_meta("done",true);progress_bar.value+=1

func finish(success: bool) -> void:
	_finished=true
	if success:
		note.text="准备完成"
		await get_tree().create_timer(0.3).timeout
		if is_inside_tree(): continue_requested.emit()
	else:
		note.text="部分数据未能更新，本地卡库和轮盘仍可使用。"
		continue_button.visible=true;retry_button.visible=true
