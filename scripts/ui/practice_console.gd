extends CanvasLayer
signal dismissed
var controller: Node
var catalog: Array = []
var output: TextEdit
var entry: LineEdit
var history: Array = []
var cursor := 0

func _ready() -> void:
	layer=90
	controller.debug_console_open=true
	var shade:=ColorRect.new();shade.color=Color(0,0,0,0.48);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
	if get_parent() is Control: shade.theme=get_parent().theme
	var panel:=PanelContainer.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.offset_left=24;panel.offset_right=-24;panel.offset_top=24;panel.offset_bottom=-24;shade.add_child(panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color("14231e");style.border_color=Color("c5a36b");style.set_border_width_all(0);style.set_content_margin_all(18);panel.add_theme_stylebox_override("panel",style)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",10);panel.add_child(box)
	var header:=HBoxContainer.new();box.add_child(header)
	var title:=Label.new();title.text="练习控制台 · F8";title.add_theme_font_size_override("font_size",23);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	var close:=Button.new();close.text="返回战场";close.pressed.connect(dismiss);header.add_child(close)
	output=TextEdit.new();output.editable=false;output.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;output.size_flags_vertical=Control.SIZE_EXPAND_FILL;output.add_theme_font_size_override("font_size",18);box.add_child(output)
	output.text=controller.debug_session.HELP+"\n"
	output.add_theme_color_override("font_readonly_color",Color("e5dfcc"))
	close.custom_minimum_size.y=44
	var quick:=HBoxContainer.new();box.add_child(quick)
	for text in ["费用 12","抽牌 1","状态","AI 暂停","AI 步进","撤销"]:
		var button:=Button.new();button.text=text;button.custom_minimum_size.y=44;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.pressed.connect(func():run(text));quick.add_child(button)
	var selection:=HBoxContainer.new();box.add_child(selection)
	var search:=LineEdit.new();search.placeholder_text="筛选卡牌";search.custom_minimum_size.x=140;selection.add_child(search)
	var cards:=OptionButton.new();cards.size_flags_horizontal=Control.SIZE_EXPAND_FILL;cards.clip_text=true;selection.add_child(cards)
	var populate:=func(query: String):
		cards.clear()
		for i in catalog.size():
			if query.is_empty() or query.to_lower() in str(catalog[i].definition.name).to_lower(): cards.add_item("%d · %s"%[i+1,catalog[i].definition.name],i+1)
	search.text_changed.connect(populate);populate.call("")
	var owner:=OptionButton.new();owner.add_item("己方");owner.add_item("敌方");selection.add_child(owner)
	for command in ["手牌","召唤"]:
		var button:=Button.new();button.text=command;button.pressed.connect(func():
			if cards.selected>=0:run("%s %d %s"%[command,cards.get_selected_id(),"己方" if owner.selected==0 else "敌方"]))
		selection.add_child(button)
	var row:=HBoxContainer.new();box.add_child(row)
	entry=LineEdit.new();entry.placeholder_text="输入命令 · ↑↓ 查看历史";entry.size_flags_horizontal=Control.SIZE_EXPAND_FILL;entry.text_submitted.connect(run);entry.gui_input.connect(_entry_input);row.add_child(entry)
	entry.custom_minimum_size.y=44
	var submit:=Button.new();submit.text="执行";submit.pressed.connect(func():run(entry.text));row.add_child(submit)
	entry.grab_focus()

func run(line: String) -> void:
	if line.strip_edges().is_empty(): return
	if history.is_empty() or history.back()!=line:history.append(line)
	if history.size()>100:history.pop_front()
	cursor=history.size()
	var answer: String=controller.debug_session.execute(controller,line,catalog)
	output.text=(output.text+"\n> "+line+"\n"+answer+"\n").right(40000)
	output.set_caret_line(output.get_line_count()-1);entry.clear()

func _entry_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_UP,KEY_DOWN]:
		cursor=clampi(cursor+(-1 if event.keycode==KEY_UP else 1),0,history.size())
		entry.text=str(history[cursor]) if cursor<history.size() else "";entry.caret_column=entry.text.length();entry.accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F8,KEY_ESCAPE]:
		get_viewport().set_input_as_handled();dismiss()

func dismiss() -> void:
	controller.debug_console_open=false
	dismissed.emit();queue_free()

func _exit_tree() -> void:
	if is_instance_valid(controller): controller.debug_console_open=false
