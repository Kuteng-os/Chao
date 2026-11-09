extends VBoxContainer
const Wheel = preload("res://scripts/ui/emote_wheel.gd")
const Sprite = preload("res://scripts/ui/emote_sprite.gd")
signal message(text: String)
var service: Node
var wheel: Control
var draft: Array=[]
var grid: GridContainer
var saving := false
var note: Label
var key_button: Button
var capturing := false
var page := 0
var page_label: Label
var previous: Button
var next: Button

func _ready() -> void:
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	draft=service.slots.duplicate()
	var row := HBoxContainer.new();row.size_flags_vertical=Control.SIZE_EXPAND_FILL;row.add_theme_constant_override("separation",22);add_child(row)
	var left := VBoxContainer.new();row.add_child(left)
	var caption:=Label.new();caption.text="轮盘配置";caption.add_theme_color_override("font_color",ChaoUI.MUTED);caption.add_theme_font_size_override("font_size",13);left.add_child(caption)
	wheel=Wheel.new();wheel.service=service;wheel.slots=draft;wheel.editing=true;wheel.compact=true;wheel.custom_minimum_size=Vector2(260,260);wheel.selected=0;left.add_child(wheel)
	wheel.picked.connect(func(index): wheel.selected=index;wheel.rebuild())
	var tools:=HBoxContainer.new();left.add_child(tools)
	var clear := Button.new();clear.text="清空此位置";tools.add_child(clear)
	clear.pressed.connect(func(): draft[wheel.selected]="";wheel.slots=draft;wheel.rebuild())
	key_button=Button.new();key_button.text="快捷键："+OS.get_keycode_string(service.shortcut);tools.add_child(key_button)
	key_button.pressed.connect(func(): capturing=true;key_button.text="按字母或 F1～F12（Esc 取消）")
	var muted := CheckButton.new();muted.text="屏蔽对方表情";muted.button_pressed=service.mute_opponent;left.add_child(muted);muted.toggled.connect(service.set_muted)
	var right := VBoxContainer.new();right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(right)
	var heading:=Label.new();heading.text="我的表情库";heading.add_theme_font_size_override("font_size",20);right.add_child(heading)
	var scroll := ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;right.add_child(scroll)
	grid=GridContainer.new();grid.columns=3;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(grid)
	var pages := HBoxContainer.new();right.add_child(pages)
	previous=Button.new();previous.text="‹";pages.add_child(previous);previous.pressed.connect(func(): page=maxi(0,page-1);_library())
	page_label=Label.new();page_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;page_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;pages.add_child(page_label)
	next=Button.new();next.text="›";pages.add_child(next);next.pressed.connect(func(): page+=1;_library())
	note=Label.new();note.text="先选择轮盘位置，再选择表情";note.add_theme_font_size_override("font_size",13);note.add_theme_color_override("font_color",ChaoUI.MUTED);add_child(note)
	var actions := HBoxContainer.new();add_child(actions)
	var refresh := Button.new();refresh.text="刷新";actions.add_child(refresh)
	refresh.pressed.connect(func():
		refresh.disabled=true
		await service.refresh()
		if not is_inside_tree(): return
		refresh.disabled=false;_library();note.text=service.last_error if not service.last_error.is_empty() else "表情库已更新")
	var save := Button.new();save.text="保存轮盘";save.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(save)
	for button in [clear,key_button,previous,next,refresh]:ChaoUI.skin_button(button)
	ChaoUI.skin_button(save,true,"check")
	ChaoUI.skin_button(refresh,false,"refresh-cw")
	save.pressed.connect(func():
		if saving: return
		saving=true;save.disabled=true
		var text: String=await service.save_slots(draft)
		if not is_inside_tree(): return
		saving=false;save.disabled=false;note.text=text;message.emit(text))
	_library()

func _library() -> void:
	for child in grid.get_children(): grid.remove_child(child);child.queue_free()
	if service.catalog.is_empty():
		var empty := Label.new();empty.text="暂无表情\n可在工坊上传";empty.add_theme_font_size_override("font_size",18);grid.add_child(empty)
	var count: int=maxi(1,ceili(service.catalog.size()/12.0))
	page=clampi(page,0,count-1);page_label.text="%d / %d"%[page+1,count];previous.disabled=page==0;next.disabled=page>=count-1
	for e in service.catalog.slice(page*12,(page+1)*12):
		var button := Button.new();button.custom_minimum_size=Vector2(116,130);button.tooltip_text=e.name+" · "+str(e.get("author","作者"));ChaoUI.skin_button(button);grid.add_child(button)
		var sprite := Sprite.new();sprite.entry=e;sprite.origin=service.origin;sprite.position=Vector2(18,8);sprite.size=Vector2(80,80);button.add_child(sprite)
		var label := Label.new();label.text=e.name;label.position=Vector2(6,94);label.size=Vector2(104,26);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;label.mouse_filter=Control.MOUSE_FILTER_IGNORE;label.add_theme_font_size_override("font_size",16);button.add_child(label)
		button.pressed.connect(func(): draft[wheel.selected]=e.emote_id;wheel.slots=draft;wheel.rebuild())

func _input(event: InputEvent) -> void:
	if not capturing or not event is InputEventKey or not event.pressed or event.echo: return
	var key: int=event.physical_keycode if event.physical_keycode else event.keycode
	if key==KEY_ESCAPE:
		capturing=false
	elif key in range(KEY_A,KEY_Z+1) or key in range(KEY_F1,KEY_F12+1):
		service.set_shortcut(key);capturing=false
	if not capturing: key_button.text="快捷键："+OS.get_keycode_string(service.shortcut)
	get_viewport().set_input_as_handled()
