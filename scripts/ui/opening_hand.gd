extends Control
signal confirmed(ids: Array)
signal menu_requested
var selected: Array=[]
var key:=""
var row: HBoxContainer
var title: Label
var note: Label
var confirm: Button
var read_only:=false
var faces: Array=[]

func _ready() -> void:
	z_index=70;mouse_filter=MOUSE_FILTER_STOP
	var shade:=ColorRect.new();shade.color=Color(0.02,0.035,0.05,0.86);shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT);shade.mouse_filter=MOUSE_FILTER_IGNORE;add_child(shade)
	title=Label.new();title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_theme_font_size_override("font_size",34);add_child(title)
	note=Label.new();note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;note.add_theme_font_size_override("font_size",19);add_child(note)
	row=HBoxContainer.new();row.alignment=BoxContainer.ALIGNMENT_CENTER;row.add_theme_constant_override("separation",18);add_child(row)
	confirm=Button.new();confirm.custom_minimum_size=Vector2(300,56);ChaoUI.skin_button(confirm,true,"check");confirm.add_theme_font_size_override("font_size",20);confirm.pressed.connect(func():confirmed.emit(selected.duplicate()));add_child(confirm)
	var menu:=Button.new();menu.text="菜单";ChaoUI.skin_button(menu,false,"settings-2");menu.position=Vector2(24,24);menu.pressed.connect(func():menu_requested.emit());add_child(menu)
	visible=false

func show_hand(state: Dictionary, seat: int, watching: bool, connected: bool) -> void:
	visible=state.has("mulligan") and state.get("winner",-1)==-1
	if not visible:selected.clear();key="";return
	read_only=watching or state.mulligan.confirmed[seat] or not connected or state.get("suspended",false)
	title.text="开局换牌" if not watching else "观战 · 开局换牌"
	note.text="等待对方确认" if state.mulligan.confirmed[seat] else "跟随玩家正在选择手牌" if watching else "点击选择要换掉的牌，每局仅一次；联机超时将保留原手牌。"
	if not connected or state.get("suspended",false): note.text="连接恢复后继续换牌"
	var hand: Array=state.players[seat].hand
	var next_key:=JSON.stringify(hand.map(func(h):return str(h.instance_id)))
	if next_key!=key:
		key=next_key;selected.clear();faces.clear()
		for child in row.get_children():row.remove_child(child);child.queue_free()
		for card in hand:
			var column:=VBoxContainer.new();column.add_theme_constant_override("separation",12);row.add_child(column)
			var face:=preload("res://scripts/ui/card_face.gd").new()
			face.spec=CardRuntime.display_definition(card.card);face.art_id=card.card.get("art_id","");face.use_tooltip=false;face.touch_gate.hold_required=false
			face.custom_minimum_size=face.full_size(218);column.add_child(face);face.refresh_art()
			var tag:=Label.new();tag.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;tag.add_theme_font_size_override("font_size",22);column.add_child(tag)
			faces.append({"face":face,"tag":tag,"id":str(card.instance_id)})
			face.pressed.connect(func():toggle(str(card.instance_id)))
	var width:=minf(218,(size.x-80-18*maxi(0,hand.size()-1))/maxi(1,hand.size()))
	for item in faces:item.face.custom_minimum_size=item.face.full_size(width)
	title.position=Vector2(30,38);title.size=Vector2(size.x-60,50)
	note.position=Vector2(30,96);note.size=Vector2(size.x-60,38)
	row.position=Vector2(30,160);row.size=Vector2(size.x-60,500)
	confirm.position=Vector2((size.x-300)*0.5,size.y-115);confirm.size=Vector2(300,56)
	confirm.visible=not watching;confirm.disabled=read_only
	refresh_selection()

func toggle(id: String) -> void:
	if read_only:return
	if id in selected:selected.erase(id)
	else:selected.append(id)
	refresh_selection()

func refresh_selection() -> void:
	for item in faces:
		item.tag.text="换掉" if item.id in selected else "保留"
		item.tag.add_theme_color_override("font_color",ChaoUI.ACCENT if item.id in selected else ChaoUI.MUTED)
		item.face.modulate=Color(0.7,0.7,0.7) if item.id in selected else Color.WHITE
		item.face.highlighted=item.id in selected;item.face.queue_redraw()
	confirm.text="等待确认" if read_only else "全部保留" if selected.is_empty() else "确认换 %d 张"%selected.size()
