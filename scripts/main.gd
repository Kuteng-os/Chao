extends Control
const Audio = preload("res://scripts/ui/frontline_audio.gd")

const HubScript = preload("res://scripts/ui/player_hub.gd")
const StoreScript = preload("res://scripts/app_store.gd")
const MatchScript = preload("res://scripts/network/match_controller.gd")
const BackgroundScript = preload("res://scripts/ui/map_background.gd")
const CardScript = preload("res://scripts/ui/card_face.gd")
const DeckDropScript = preload("res://scripts/ui/deck_drop_zone.gd")
const DeckStripScript = preload("res://scripts/ui/deck_strip.gd")
const BattleViewScript = preload("res://scripts/ui/battle_view.gd")
const ScreenLayout = preload("res://scripts/ui/screen_layout.gd")
const CREAM := Color("eeeeee")
const MUTED := Color("a3a3a3")
const GOLD := Color("d2d2d2")
const GREEN := Color("aac4ab")
var emotes: Node
var startup: Control
var _boot_loading := true
var _boot_serial := 0
var _boot_done: Dictionary = {}
var _boot_ok := true
var store: AppStore
var audio_system: Audio
var match_controller: MatchController
var content: VBoxContainer
var footer: Label
var connection_badge: Label
var mobile := OS.has_feature("mobile") or OS.get_environment("FRONTLINE_MOBILE_TEST") == "1"
var page := "home"
var work_mode := 0
var source_text := ""
var json_text := ""
var draft: Dictionary = {}
var generation: Dictionary = {}
var generation_id := ""
var questions: Array = []
var answers: Dictionary = {}
var busy := false
var request_epoch := 0
var editor_revision := 1
var info_text := ""
var card_proposals: Array = []
var keyword_source := ""
var keyword_json := ""
var proposal: Dictionary = {}
var keyword_answers: Dictionary = {}
var keyword_busy := false
var keyword_epoch := 0
var pending_generation_id := ""
var pending_source := ""
var pending_editor_revision := 0
const RARITIES := ["standard","limited","special","elite"]
const GITHUB_URL_LIMIT := 7000
const PACK_FORMAT := "chao-card-pack-v1"
const PACK_MAX_CARDS := 20
const PACK_MAX_PNG := 2097152
const PACK_IMPORT_LIMIT := 1048576
## Local card ids ticked in the workshop for the next pack.
var pack_selection: Dictionary = {}
var last_card_error := ""
var manual := {"name":"","kind":0,"cost":1,"operation_cost":1,"attack":1,"health":1,"blitz":false,"guard":false,"effect":0,"amount":1,"trigger":0,"keyword_refs":"[]"}
var creator_keywords: Dictionary = {}
var creator_effects: Array = []
var cloud_rooms: Array = []
var cloud_room_code := ""
var cloud_loading := false
var selected_hand := ""
var selected_unit := -1
var host_address := "127.0.0.1"
var port_number := 24567
const CardSeries = preload("res://scripts/core/card_series.gd")
var library_series := 0
var library_filter := ""
var library_rarity := ""
var library_sin := ""
var library_faction := ""
var library_kind := ""
var library_sort := 0
var library_cost := -1
var library_versions: Dictionary = {}
var library_grid: GridContainer
var library_scroll: ScrollContainer
var deck_scroll: ScrollContainer
var library_deck_list: VBoxContainer
var library_headquarters: Button
var library_deck_title: Button
var library_deck_count: Label
var library_faction_picker: OptionButton
var library_faction_entries: Array = []
var library_card_nodes: Dictionary = {}
var library_deck_nodes: Dictionary = {}
var library_scroll_positions := Vector2i.ZERO
var library_restoring := false
var library_count: Label
var library_drop: PanelContainer
var deck_drop: PanelContainer
var overlay: Control
var nav_buttons: Dictionary = {}
var shell_margin: MarginContainer
var shell_box: VBoxContainer
var shell_header: HBoxContainer
var shell_line: HSeparator
var shell_bottom: HBoxContainer
var battle_view: Control
var practice_console: CanvasLayer
var update_notified := 0
var modal_margin: MarginContainer
var safe_area_elapsed := 0.0
var menu_backdrop: Control
var sidebar: VBoxContainer
var shell_workspace: HBoxContainer
var page_chrome: HBoxContainer
var page_caption: Label
var account_button: Button
var settings_tab := "display"
var library_curve: Control
var toast: PanelContainer
var _page_anim: Tween
const PAGE_NAMES={"home":"指挥中心","network":"对战","library":"卡库与构筑","workshop":"创作工坊","keywords":"词条图鉴","profile":"个人档案","statistics":"战局分析","settings":"设置"}

func _ready() -> void:
	get_window().title="巢战 · 0.9"
	ScreenLayout.configure(get_window(), mobile)
	if mobile: get_tree().quit_on_go_back = false
	_build_theme()
	audio_system = Audio.new()
	audio_system.name = "Audio"
	add_child(audio_system)
	var backdrop := Control.new()
	menu_backdrop=backdrop
	backdrop.set_script(BackgroundScript)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	store = StoreScript.new()
	store.name = "AppStore"
	add_child(store)
	store.changed.connect(_store_changed)
	store.note_changed.connect(func(): if connection_badge != null: connection_badge.text = store.connection_note)
	store.deck_edited.connect(_update_library_deck)
	store.message.connect(_notify)
	emotes=preload("res://scripts/emote_service.gd").new();add_child(emotes);emotes.bind_store(store)
	emotes.progress.connect(func(text):
		if is_instance_valid(startup): startup.labels.emotes.text=text)
	match_controller = MatchScript.new()
	match_controller.name = "MatchController"
	add_child(match_controller)
	match_controller.emote_service=emotes
	match_controller.emote_received.connect(_receive_emote)
	match_controller.state_changed.connect(_battle_updated)
	match_controller.notice.connect(_notify)
	match_controller.status_changed.connect(_match_status)
	_build_shell()
	resized.connect(_update_screen_margins)
	_render()
	ClientUpdate.changed.connect(_update_notice)
	_startup_begin()

func _process(delta: float) -> void:
	if not mobile: return
	safe_area_elapsed += delta
	if safe_area_elapsed >= 0.5:
		safe_area_elapsed = 0.0
		_update_screen_margins()

func _update_screen_margins() -> void:
	if not is_instance_valid(shell_margin): return
	var safe := ScreenLayout.safe_rect(self)
	var insets := {"left":safe.position.x,"top":safe.position.y,"right":size.x-safe.end.x,"bottom":size.y-safe.end.y}
	for side in insets:
		var padding := (16 if mobile else 36) if side in ["left", "right"] else (12 if mobile else (22 if side == "top" else 16))
		# The battle manages its own safe area so the table can reach every edge.
		shell_margin.add_theme_constant_override("margin_"+side, 0 if page=="battle" else ceili(insets[side])+padding)
		if is_instance_valid(modal_margin): modal_margin.add_theme_constant_override("margin_"+side,ceili(insets[side])+12)
	if is_instance_valid(battle_view): battle_view._fit()
	if is_instance_valid(sidebar):_sync_shell()

## The About page outlives none of its renders, so each render binds its own listener and drops it on exit.
func _update_controls(parent: Control) -> void:
	var line := _text(parent, "", 15, GOLD)
	var action := _button(parent, "", func(): ClientUpdate.act(), true)
	var refresh := func():
		if not is_instance_valid(line): return
		var notes := str(ClientUpdate.available.get("notes", "")).strip_edges() if ClientUpdate.newer() else ""
		line.text = ClientUpdate.status if notes.is_empty() else ClientUpdate.status + "\n" + notes
		action.text = ClientUpdate.action_text()
		action.disabled = ClientUpdate.busy
	ClientUpdate.changed.connect(refresh)
	line.tree_exiting.connect(func(): if ClientUpdate.changed.is_connected(refresh): ClientUpdate.changed.disconnect(refresh))
	refresh.call()

func _update_notice() -> void:
	var build := int(ClientUpdate.available.get("build", 0))
	if build > ClientUpdate.current_build and build > update_notified:
		update_notified = build
		_notify("新版本 " + str(ClientUpdate.available.version) + " 已发布，可在设置 → 关于中更新。")

func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or not mobile: return
	if is_instance_valid(overlay): _close_modal()
	elif page == "battle": _leave_match_dialog()
	elif page != "home": _navigate("home")
	else:
		var panel := _modal("退出游戏")
		_button(panel, "退出", func(): get_tree().quit())

func _build_theme() -> void:
	theme=ChaoUI.make_theme(mobile)

func _build_shell() -> void:
	shell_margin=MarginContainer.new();shell_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shell_margin)
	shell_box=_vbox(shell_margin,0)
	shell_header=_hbox(shell_box,16);shell_header.custom_minimum_size.y=58
	var logo:=_button(shell_header,"巢 战",func():_navigate("home"))
	logo.add_theme_font_size_override("font_size",25);logo.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	_label(shell_header,"0.9",11,MUTED)
	_spacer(shell_header)
	connection_badge=_label(shell_header,"",12,MUTED)
	account_button=_button(shell_header,"登录",func():
		if store.authenticated:_navigate("profile")
		else:_account_dialog("login"))
	ChaoUI.skin_button(account_button,false,"user-round")
	account_button.visible=false
	shell_line=HSeparator.new();shell_box.add_child(shell_line)
	shell_workspace=_hbox(shell_box,28);shell_workspace.size_flags_vertical=Control.SIZE_EXPAND_FILL
	sidebar=_vbox(shell_workspace,8);sidebar.custom_minimum_size.x=168
	var gap:=Control.new();gap.custom_minimum_size.y=20;sidebar.add_child(gap)
	for item in [["home","指挥中心","house"],["network","对战","swords"],["library","卡库与构筑","layers"],["workshop","创作工坊","hammer"],["keywords","词条图鉴","book-open"]]:
		_add_navigation(item)
	_spacer(sidebar,true)
	_add_navigation(["settings","设置","settings-2"])
	var main:=_vbox(shell_workspace,18);main.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	page_chrome=_hbox(main);page_chrome.custom_minimum_size.y=18
	page_caption=_label(page_chrome,"",11,MUTED)
	content=_vbox(main,20);content.size_flags_vertical=Control.SIZE_EXPAND_FILL
	shell_bottom=_hbox(main);shell_bottom.custom_minimum_size.y=18
	footer=_label(shell_bottom,"",11,MUTED);footer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_update_screen_margins()

func _add_navigation(item:Array) -> void:
	var key:String=item[0]
	var button:=_button(sidebar,item[1],func():_navigate(key))
	button.name="Nav_"+key;button.set_meta("caption",item[1]);button.tooltip_text=item[1]
	ChaoUI.skin_button(button,false,item[2]);button.add_theme_constant_override("icon_max_width",20)
	nav_buttons[key]=button

func _sync_shell() -> void:
	var battle:=page=="battle"
	sidebar.visible=not battle;page_chrome.visible=not battle and page!="home"
	shell_workspace.add_theme_constant_override("separation",0 if battle else 24)
	var compact:=size.x<1320
	sidebar.custom_minimum_size.x=60 if compact else 168
	for key in nav_buttons:ChaoUI.nav_button(nav_buttons[key],page==key,compact)
	page_caption.text="巢战  /  "+str(PAGE_NAMES.get(page,""))
	account_button.text=str(store.account_identity.get("display_name","登录"))
	connection_badge.text=store.connection_note

func _navigate(next: String) -> void:
	var changed := page != next
	page = next
	_render()
	if changed and page != "battle": _animate_page()
	if changed and next == "library": store.refresh()
	if next == "network" and store.authenticated and store.central_mode: _refresh_cloud_rooms()

func _render() -> void:
	_sync_shell()
	# Deck changes keep the live controls, layout and scroll offsets intact.
	if page == "library" and is_instance_valid(library_scroll) and library_scroll.is_inside_tree():
		_update_library_factions()
		_update_library_series()
		_populate_library()
		_update_library_deck()
		return
	if not library_restoring and is_instance_valid(library_scroll) and library_scroll.is_inside_tree():
		library_scroll_positions.x = library_scroll.scroll_vertical
		if is_instance_valid(deck_scroll): library_scroll_positions.y = deck_scroll.scroll_vertical
	var in_battle := page == "battle"
	menu_backdrop.set_page(page)
	audio_system.set_scene("battle" if in_battle and not match_controller.state.is_empty() else "menu")
	shell_header.visible = not in_battle
	shell_line.visible = not in_battle
	shell_bottom.visible = not in_battle
	shell_box.add_theme_constant_override("separation",0)
	_update_screen_margins()
	if in_battle and is_instance_valid(battle_view) and not match_controller.state.is_empty():
		battle_view.present_snapshot(match_controller.state,match_controller.connected,selected_hand,selected_unit)
		return
	battle_view = null
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	match page:
		"home": _home()
		"workshop": _workshop()
		"library": _library()
		"keywords": _keywords()
		"network": _network_lobby()
		"battle": _battle()
		"settings": _settings()
		"profile", "statistics":
			var hub := VBoxContainer.new()
			hub.set_script(HubScript)
			content.add_child(hub)
			hub.setup(self, store, page == "statistics")

func _home() -> void:
	var body:=_hbox(content,32);body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var intro:=_vbox(body,16);intro.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_spacer(intro,true)
	_label(intro,"都 市 · 战 术 档 案",12,GOLD)
	_label(intro,"巢战",72 if not mobile else 54)
	var season:=_hbox(intro,9)
	_label(season,"CHAO",12,MUTED);_label(season,"/",12,MUTED);_label(season,"0.9",12,MUTED)
	var air:=Control.new();air.custom_minimum_size.y=16;intro.add_child(air)
	var primary:=_button(intro,"进入对战",func():_navigate("network"),true)
	primary.custom_minimum_size=Vector2(270,58);primary.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	ChaoUI.skin_button(primary,true,"arrow-up-right")
	var tools:=_hbox(intro,8)
	_button(tools,"我的牌组",_saved_decks_dialog)
	_button(tools,"表情轮盘",_emote_dialog)
	_spacer(intro,true)
	var shortcut:=_hbox(intro,12)
	var book:=_vbox(shortcut,7);book.custom_minimum_size.x=270
	_label(book,"当前构筑",11,MUTED)
	_label(book,store.deck_name,22)
	var line:=_hbox(book);_label(line,"%02d / 40"%store.deck_ids.size(),16,GOLD);_spacer(line)
	var edit:=_button(line,"编辑",func():_navigate("library"))
	edit.add_theme_stylebox_override("normal",ChaoUI.style(Color.TRANSPARENT,Color.TRANSPARENT))
	var exhibit:=_vbox(body,10);exhibit.custom_minimum_size.x=310 if size.x>1300 else 250
	exhibit.size_flags_horizontal=Control.SIZE_SHRINK_END
	_spacer(exhibit,true)
	var records:=store.latest_cards().filter(func(c):return c.get("art",{}).has("id"))
	if not records.is_empty():
		var carousel:=preload("res://scripts/ui/home_card_carousel.gd").new()
		carousel.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		carousel.blocked=func():return is_instance_valid(overlay) or _boot_loading
		exhibit.add_child(carousel)
		carousel.configure(records,store.display_definition,270 if size.x>1300 else 220)
		carousel.card_selected.connect(_card_details)
	_spacer(exhibit,true)
	var panorama:=_hbox(exhibit,10)
	var scene_text:=_vbox(panorama,5);scene_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_label(scene_text,str(BattleSceneCatalog.preset().name),17)
	_label(scene_text,str(BattleSceneCatalog.preset().get("subtitle","")),11,MUTED)
	var scene_button:=_button(panorama,"",_scene_dialog);ChaoUI.skin_button(scene_button,false,"sliders-horizontal");scene_button.tooltip_text="切换场景"

func _animate_page() -> void:
	if is_instance_valid(_page_anim):_page_anim.kill()
	if not audio_system.preferences.animations:return
	content.modulate.a=0
	_page_anim=create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_page_anim.tween_property(content,"modulate:a",1.0,0.22)

func _scene_dialog() -> void:
	var panel:=_modal("场景与画质")
	for entry in BattleSceneCatalog.entries():
		var selected:bool=entry.id==BattleSceneCatalog.selected()
		_button(panel,str(entry.name)+( "  ·  使用中" if selected else ""),func():
			BattleSceneCatalog.choose(entry.id)
			menu_backdrop.refresh_scene()
			if is_instance_valid(battle_view):battle_view.backdrop.set_scene(entry.id)
			_close_modal();_render()
		,selected)
	_label(panel,"画质",14,MUTED)
	var qualities:=["low","balanced","high"]
	var quality:=_option(panel,["轻量","均衡","高"],maxi(0,qualities.find(BattleSceneCatalog.quality)))
	quality.item_selected.connect(func(index):
		BattleSceneCatalog.choose(BattleSceneCatalog.selected(),qualities[index])
		menu_backdrop.refresh_scene()
		if is_instance_valid(battle_view):battle_view.backdrop.set_scene(BattleSceneCatalog.selected());battle_view.backdrop._resize()
	)
	_text(panel,"场景仅影响本机画面。",12,MUTED)
	_button(panel,"关闭",_close_modal)

func _workshop() -> void:
	_heading("创作工坊","")
	var row:=_hbox(content,24);row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var editor:=_panel(row);editor.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var modes:=_hbox(editor)
	_button(modes,"表单制作",func():_set_work_mode(0);_render(),work_mode!=1)
	_button(modes,"JSON",func():_set_work_mode(1);_render(),work_mode==1)
	if work_mode==1:_json_workshop(editor)
	else:_text_workshop(editor)
	var side:=_vbox(row,18);side.custom_minimum_size.x=340
	_workshop_result(side)
	_workshop_submissions(side)

func _workshop_result(parent: Control) -> void:
	var panel:=_panel(parent)
	_label(panel,"校验结果",22)
	_text(panel,info_text if not info_text.is_empty() else "填写后点击“校验并预览”。",15,GOLD if not last_card_error.is_empty() else MUTED)
	if not draft.is_empty():
		_text(panel,str(draft.get("rules_text","")),15)
		var confirm:=_button(panel,"保存到本地卡库",_confirm_card,true)
		confirm.set_meta("card_action","confirm");confirm.disabled=busy
	if not last_card_error.is_empty():
		_button(panel,"把报错发到 Issue  ↗",_report_card_error)

func _workshop_submissions(parent: Control) -> void:
	var panel:=_panel(parent);panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_label(panel,"我做的卡",22)
	var author:=_line(panel,str(store.settings.player_name),"提交署名")
	author.max_length=64
	author.text_changed.connect(func(value):store.settings.player_name=value.strip_edges();store.save_profile())
	_text(panel,"勾选卡牌打成卡包提交。提交前请先用这些卡组牌试玩。",13,MUTED)
	var mine:=store.cards.filter(func(record):return bool(record.get("local_only",false)))
	for id in pack_selection.keys():
		if not mine.any(func(record):return str(record.card_id)==str(id)):pack_selection.erase(id)
	var actions:=_hbox(panel,8)
	_button(actions,"导入卡包",_open_pack_import)
	var pack_button:=_button(actions,"打包提交（%d）" % pack_selection.size(),_pack_dialog,true)
	pack_button.disabled=pack_selection.is_empty()
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;panel.add_child(scroll)
	var list:=_vbox(scroll,8);list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if mine.is_empty():_text(list,"保存后的卡牌会出现在这里，可以打包提交到 GitHub。",14,MUTED)
	for record in mine:
		var check:=CheckButton.new()
		check.text=str(record.definition.name)
		check.button_pressed=pack_selection.has(str(record.card_id))
		check.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		check.toggled.connect(func(enabled):
			if enabled and pack_selection.size()>=PACK_MAX_CARDS:
				check.set_pressed_no_signal(false)
				_notify("一个卡包最多 %d 张卡。" % PACK_MAX_CARDS)
				return
			if enabled:pack_selection[str(record.card_id)]=true
			else:pack_selection.erase(str(record.card_id))
			pack_button.text="打包提交（%d）" % pack_selection.size()
			pack_button.disabled=pack_selection.is_empty()
		)
		list.add_child(check)

func _pack_records() -> Array:
	return store.cards.filter(func(record):return bool(record.get("local_only",false)) and pack_selection.has(str(record.card_id)))

## Names, art and a self-declared local test, then the pack is exported for upload.
func _pack_dialog() -> void:
	var records:=_pack_records()
	if records.is_empty():return
	var panel:=_modal("打包提交")
	var name_line:=_line(panel,"","卡包名称（1 至 32 字）")
	name_line.max_length=32
	var description:=_editor(panel,"","卡包简介（可选，最多 300 字）",90)
	var arts:={}
	_label(panel,"卡牌（%d 张）" % records.size(),18)
	for record in records:
		var row:=_hbox(panel,8)
		var title:=_label(row,str(record.definition.name),15);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var art_label:=_label(row,"无卡面",13,MUTED)
		_button(row,"选择 PNG 卡面",func():_pick_pack_art(func(path):
			arts[str(record.card_id)]=path
			art_label.text=path.get_file()
		))
	var tested:=CheckButton.new()
	tested.text="我已经用这些卡组牌试玩过，效果符合预期"
	panel.add_child(tested)
	var submit:=_button(panel,"生成卡包并打开提交页面",func():
		_export_pack(records,name_line.text.strip_edges(),description.text.strip_edges(),arts)
	,true)
	submit.disabled=true
	var refresh:=func():submit.disabled=not tested.button_pressed or name_line.text.strip_edges().is_empty()
	tested.toggled.connect(func(_on):refresh.call())
	name_line.text_changed.connect(func(_text):refresh.call())

func _pick_pack_art(chosen: Callable) -> void:
	var dialog:=FileDialog.new()
	dialog.access=FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters=PackedStringArray(["*.png ; PNG 卡面"])
	add_child(dialog)
	dialog.file_selected.connect(func(path):
		var problem:=_pack_art_problem(path)
		if problem.is_empty():chosen.call(path)
		else:_notify(problem)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(850,600))

## The same limits CI applies, so a pack that leaves the game is not rejected for its art.
func _pack_art_problem(path: String) -> String:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return "无法读取卡面文件。"
	var size:=file.get_length()
	var header:=file.get_buffer(8)
	file.close()
	if size>PACK_MAX_PNG:return "卡面不能超过 2 MiB。"
	if header!=PackedByteArray([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]):return "卡面必须是 PNG。"
	var image:=Image.load_from_file(path)
	if image==null or image.get_width()<1 or image.get_width()>1024 or image.get_height()<1 or image.get_height()>1024:return "卡面边长需在 1 至 1024 像素之间。"
	return ""

## Builds pack-<hash>.pack.json exactly as tools/library/submission.mjs checks it; the hash covers the card hashes in order.
func _build_pack(records: Array, pack_name: String, pack_description: String) -> Dictionary:
	if pack_name.is_empty() or pack_name.length()>32:return {"error":"卡包名称需为 1 至 32 个字符。"}
	if pack_description.length()>300:return {"error":"卡包简介最多 300 个字符。"}
	if records.is_empty() or records.size()>PACK_MAX_CARDS:return {"error":"卡包需要包含 1 至 %d 张卡。" % PACK_MAX_CARDS}
	var entries:=[]
	var names:={}
	for record in records:
		var compiled:=store.compile_record(record)
		if not compiled.get("ok",false):return {"error":"《%s》无法编译：%s" % [record.definition.name,str(compiled.get("error",""))],"definition":record.definition}
		if names.has(str(record.definition.name)):return {"error":"卡包里有两张卡都叫《%s》。" % record.definition.name}
		names[str(record.definition.name)]=true
		entries.append({"definition":record.definition,"definition_hash":str(compiled.definition_hash)})
	var hashes:=entries.map(func(entry):return entry.definition_hash)
	var digest:String=CardRuntime.sha(hashes)
	var author:=str(store.settings.player_name).strip_edges()
	var pack:={"format":PACK_FORMAT,"game_version":ClientUpdate.current_version,"author":author if not author.is_empty() else "指挥官","name":pack_name,"cards":entries}
	if not pack_description.is_empty():pack["description"]=pack_description
	return {"pack":pack,"digest":digest,"file":"pack-%s.pack.json" % digest.left(12),"text":JSON.stringify(pack)}

func _pack_art_file(digest: String, definition_hash: String) -> String:
	return "pack-%s-%s.png" % [digest.left(12),definition_hash.left(12)]

func _export_pack(records: Array, pack_name: String, pack_description: String, arts: Dictionary) -> void:
	var built:=_build_pack(records,pack_name,pack_description)
	if built.has("error"):
		if built.has("definition"):_open_issue("[报错] 卡包无法生成",built.error,JSON.stringify(built.definition))
		else:_notify(built.error)
		return
	if mobile:
		# Phones cannot hand an app-private folder to the browser, so the pack text goes through the clipboard instead.
		var url:String=AppStore.GITHUB_REPO+"/new/main/submissions/inbox?filename="+built.file
		var filled:String=url+"&value="+str(built.text).uri_encode()
		if filled.length()<=GITHUB_URL_LIMIT:url=filled
		else:
			DisplayServer.clipboard_set(built.text)
			_notify("卡包内容已复制，请粘贴到打开的页面。")
		if not arts.is_empty():_notify("手机端暂不支持上传卡面，卡面请在电脑上补充。")
		_close_modal()
		if OS.shell_open(url)!=OK:_notify("无法打开浏览器，请访问 "+AppStore.GITHUB_REPO)
		return
	var folder:=ProjectSettings.globalize_path("user://packs").path_join(built.file.trim_suffix(".pack.json"))
	DirAccess.make_dir_recursive_absolute(folder)
	for old in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(old))
	var out:=FileAccess.open(folder.path_join(built.file),FileAccess.WRITE)
	if out==null:
		_notify("无法写入卡包文件夹。")
		return
	out.store_string(built.text)
	out.close()
	for record in records:
		var source:=str(arts.get(str(record.card_id),""))
		if source.is_empty():continue
		var definition_hash:=str(built.pack.cards[records.find(record)].definition_hash)
		var bytes:=FileAccess.get_file_as_bytes(source)
		var art_out:=FileAccess.open(folder.path_join(_pack_art_file(built.digest,definition_hash)),FileAccess.WRITE)
		if art_out==null or bytes.is_empty():
			_notify("无法复制卡面：%s" % source.get_file())
			return
		art_out.store_buffer(bytes)
		art_out.close()
	_close_modal()
	var done:=_modal("卡包已生成")
	_text(done,"卡包《%s》共 %d 张卡，已保存到：\n%s" % [pack_name,records.size(),folder],15)
	_text(done,"1. 在打开的 GitHub 页面登录，把文件夹里的全部文件拖进网页。\n2. 选择 Propose changes，再点 Create pull request。\n3. 校验结果会出现在 PR 下方，失败时会自动开 Issue 说明原因。",14,MUTED)
	_button(done,"打开卡包文件夹",func():OS.shell_open(folder))
	_button(done,"打开 GitHub 上传页面  ↗",func():OS.shell_open(AppStore.GITHUB_REPO+"/upload/main/submissions/inbox"),true)
	OS.shell_open(folder)
	OS.shell_open(AppStore.GITHUB_REPO+"/upload/main/submissions/inbox")

func _open_pack_import() -> void:
	var dialog:=FileDialog.new()
	dialog.access=FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters=PackedStringArray(["*.pack.json ; 巢战卡包"])
	add_child(dialog)
	dialog.file_selected.connect(func(path):
		dialog.queue_free()
		_import_pack(path)
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(850,600))

## Imports every card of a pack as local cards, so the author (or a tester) can build a deck and play it.
func _import_pack(path: String) -> void:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:
		_notify("无法读取卡包文件。")
		return
	if file.get_length()>PACK_IMPORT_LIMIT:
		_notify("卡包文件不能超过 1 MiB。")
		return
	var parsed:Dictionary=CardRuntime.parse_json(file.get_as_text(),PACK_IMPORT_LIMIT)
	if not parsed.ok or not parsed.value is Dictionary or parsed.value.get("format")!=PACK_FORMAT or not parsed.value.get("cards") is Array:
		_notify("这不是巢战卡包文件。")
		return
	var imported:=0
	var failed:=PackedStringArray()
	for entry in parsed.value.cards:
		if not entry is Dictionary or not entry.get("definition") is Dictionary:continue
		var made:Dictionary=await store.create_draft(entry.definition)
		var saved:Dictionary=await store.confirm_draft(made.draft) if made.get("ok",false) else made
		if saved.get("ok",false):imported+=1
		else:failed.append("%s：%s" % [str(entry.definition.get("name","?")),str(saved.get("error",""))])
	_notify("已导入 %d 张卡到本地卡库%s。" % [imported,"，%d 张失败：%s" % [failed.size(),"；".join(failed)] if not failed.is_empty() else ""])
	_render()

func _report_card_error() -> void:
	_open_issue("[报错] 卡牌校验失败",last_card_error,json_text if work_mode==1 else JSON.stringify(_basic_card_definition()))

func _open_issue(title: String, details: String, card: String) -> void:
	var base:=AppStore.GITHUB_REPO+"/issues/new?template=bug.yml&title="+title.uri_encode()+"&version="+str(ClientUpdate.current_version).uri_encode()+"&details="+details.uri_encode()
	var url:=base+"&card="+card.uri_encode()
	if url.length()>GITHUB_URL_LIMIT:
		url=base
		DisplayServer.clipboard_set(card)
		_notify("卡牌 JSON 较长，已复制。请粘贴到 Issue 的卡牌栏。")
	if OS.shell_open(url)!=OK:_notify("无法打开浏览器，请访问 "+AppStore.GITHUB_REPO)

func _text_workshop(parent: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var form := _vbox(scroll, 10)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_row := _hbox(form)
	var name_field := _line(title_row, str(manual.name), "卡牌名称")
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_field.text_changed.connect(func(value): _edit_manual("name", value))
	var kind_field := _option(title_row, ["步兵", "坦克", "炮兵", "战斗机", "轰炸机", "指令"], int(manual.kind))
	kind_field.item_selected.connect(func(index): _edit_manual("kind", index); _render())
	_creator_identity_row(form)
	var numbers := _hbox(form)
	_number_field(numbers, "部署费", "cost", 1, 12)
	if int(manual.kind) != 5:
		_number_field(numbers, "行动费", "operation_cost", 0, 4)
		_number_field(numbers, "攻击", "attack", 0, 20)
		_number_field(numbers, "防御", "health", 1, 20)
	var keyword_row := _hbox(form)
	_label(keyword_row, "词条", 18, GOLD)
	_spacer(keyword_row)
	_button(keyword_row, "选择已有词条", _choose_card_keywords)
	if store.model_configured: _button(keyword_row, "创建新词条", func(): _navigate("keywords"))
	var names: Array[String] = []
	for ref in creator_keywords.values():
		for definition in store.keyword_definitions:
			if definition.id == ref.id and int(definition.version) == int(ref.version):
				var suffix := ""
				for value in ref.params.values(): suffix += " " + str(value)
				names.append(str(definition.name) + suffix)
	_text(form, " · ".join(names) if not names.is_empty() else "未选择词条", 15, MUTED)
	var effects_header := _hbox(form)
	_label(effects_header, "效果组合", 18, GOLD)
	_spacer(effects_header)
	_button(effects_header, "＋ 添加效果", _add_creator_effect).disabled = creator_effects.size() >= 12
	for index in creator_effects.size(): _creator_effect_row(form, index)
	if store.model_configured:
		_label(form, "其他机制（可选）", 18, GOLD)
		var editor := _editor(form, source_text, "已有词条和效果组合即可完成的卡牌，留空直接预览。\n还有其他机制时，在这里描述，交给 DeepSeek 完善。", 104)
		editor.text_changed.connect(func():
			if source_text != editor.text:
				source_text = editor.text
				_invalidate_card_editor()
		)
		_text(form, "基础数值由你填写；DeepSeek 只理解词条和附加效果，细节不清楚时会继续询问。", 12, MUTED)
	else:
		_text(form, "更复杂的效果可切换到 JSON 编写；需要新机制时发 Issue。", 13, MUTED)
	if not questions.is_empty():
		_label(form, "补充效果细节", 20, GOLD)
		_questions_ui(form, questions, answers)
		var submit := _button(form, "提交回答，继续完善", _answer_card, true)
		submit.set_meta("card_action", "answers")
		submit.disabled = busy
	if not card_proposals.is_empty():
		_label(form, "先登记新词条", 19, GOLD)
		for candidate in card_proposals:
			_text(form, "%s — %s" % [candidate.get("name", "新词条"), candidate.get("requested_behavior", "")], 14)
		_button(form, "转到词条登记", _register_card_keyword)
	var buttons := _hbox(parent)
	var generate := _button(buttons, "正在处理…" if busy else ("校验并预览" if source_text.strip_edges().is_empty() else "完善效果并预览"), _generate_card, true)
	generate.set_meta("card_action", "generate")
	generate.disabled = busy
	if busy: _button(buttons, "取消", _cancel_generation)

func _add_creator_effect() -> void:
	if creator_effects.size() >= 12: return
	creator_effects.append({"trigger":"on_play", "op":"draw", "amount":1})
	_invalidate_card_editor()
	_render()

func _creator_effect_row(parent: Control, index: int) -> void:
	var item: Dictionary = creator_effects[index]
	var row := _hbox(parent, 6)
	var triggers := ["on_play", "own_turn_start", "own_turn_end", "on_death"]
	var trigger := _option(row, ["打出时" if int(manual.kind) == 5 else "部署时", "己方回合开始", "己方回合结束", "被消灭时"], triggers.find(item.trigger))
	trigger.disabled = int(manual.kind) == 5
	trigger.item_selected.connect(func(value): _edit_creator_effect(index, "trigger", triggers[value]))
	var operations := ["draw", "heal", "damage", "gain_kredits"]
	var operation := _option(row, ["抽 X 张牌", "总部回复 X 点", "敌方总部受到 X 点伤害", "获得 X 点指挥点"], operations.find(item.op))
	operation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	operation.item_selected.connect(func(value):
		_edit_creator_effect(index, "op", operations[value])
		_edit_creator_effect(index, "amount", mini(int(item.amount), _effect_maximum(operations[value])))
		_render()
	)
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = _effect_maximum(str(item.op))
	amount.value = int(item.amount)
	amount.custom_minimum_size.x = 78
	amount.value_changed.connect(func(value): _edit_creator_effect(index, "amount", int(value)))
	row.add_child(amount)
	_button(row, "×", func(): creator_effects.remove_at(index); _invalidate_card_editor(); _render())

func _edit_creator_effect(index: int, field: String, value: Variant) -> void:
	if index < 0 or index >= creator_effects.size() or creator_effects[index].get(field) == value: return
	creator_effects[index][field] = value
	_invalidate_card_editor()

func _effect_maximum(operation: String) -> int:
	return 3 if operation in ["draw", "gain_kredits"] else 10

func _creator_abilities() -> Array:
	var grouped: Dictionary = {}
	for item in creator_effects:
		var trigger: String = "on_play" if int(manual.kind) == 5 else str(item.trigger)
		if not grouped.has(trigger): grouped[trigger] = []
		var effect := {"op":str(item.op), "amount":int(item.amount)}
		match str(item.op):
			"draw": effect["player"] = "owner"
			"heal": effect["target"] = "own_hq"
			"damage": effect["target"] = "enemy_hq"
		grouped[trigger].append(effect)
	var result: Array = []
	for trigger in grouped:
		var effects: Array = grouped[trigger]
		for offset in range(0, effects.size(), 4): result.append({"trigger":trigger,"effects":effects.slice(offset, mini(offset + 4, effects.size()))})
	return result

func _choose_card_keywords() -> void:
	var panel := _modal("选择已登记词条")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(650, 380)
	panel.add_child(scroll)
	var list := _vbox(scroll, 12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var latest: Dictionary = {}
	for definition in store.keyword_definitions:
		if not latest.has(definition.id) or int(definition.version) > int(latest[definition.id].version): latest[definition.id] = definition
	var choices: Dictionary = {}
	for definition in store.keyword_definitions:
		var definition_key := "%s@%d" % [definition.id, int(definition.version)]
		if int(definition.version) == int(latest[definition.id].version) or creator_keywords.has(definition_key): choices[definition_key] = definition
	for definition in choices.values():
		var key := "%s@%d" % [definition.id, int(definition.version)]
		var row := _hbox(list)
		var check := CheckButton.new()
		check.text = str(definition.name) + (" · v%d" % int(definition.version) if int(definition.version) != int(latest[definition.id].version) else "")
		check.tooltip_text = str(definition.description)
		check.button_pressed = creator_keywords.has(key)
		check.disabled = not _keyword_fits_card(definition)
		row.add_child(check)
		var parameters: Dictionary = creator_keywords.get(key, {}).get("params", {}).duplicate(true)
		for parameter in definition.parameters:
			var limits: Dictionary = definition.parameters[parameter]
			if not parameters.has(parameter): parameters[parameter] = int(limits.minimum)
			var label := _label(row, parameter, 13, MUTED)
			label.tooltip_text = str(definition.description)
			var spin := SpinBox.new()
			spin.min_value = int(limits.minimum)
			spin.max_value = int(limits.maximum)
			spin.value = int(parameters[parameter])
			spin.value_changed.connect(func(value):
				parameters[parameter] = int(value)
				if creator_keywords.has(key): creator_keywords[key].params = parameters.duplicate(true); _invalidate_card_editor()
			)
			row.add_child(spin)
		check.toggled.connect(func(enabled):
			if enabled:
				for existing in creator_keywords.keys():
					if creator_keywords[existing].id == definition.id: creator_keywords.erase(existing)
				creator_keywords[key] = {"id":definition.id,"version":int(definition.version),"params":parameters.duplicate(true)}
			else: creator_keywords.erase(key)
			_invalidate_card_editor()
			if enabled: call_deferred("_choose_card_keywords")
		)
		_text(list, str(definition.description), 13, MUTED)
	_button(panel, "完成", func(): _close_modal(); _render(), true)

func _keyword_fits_card(definition: Dictionary) -> bool:
	if int(manual.kind) != 5: return true
	var implementation: Dictionary = definition.get("implementation", {})
	if implementation.get("kind", "") == "builtin": return false
	for ability in implementation.get("abilities", []):
		if ability.get("trigger", "") != "on_play": return false
		for effect in ability.get("effects", []):
			if effect.get("target", "") == "self": return false
	return true

func _card_blueprint() -> Dictionary:
	var classes := ["infantry", "tank", "artillery", "fighter", "bomber", "order"]
	var kind: String = classes[int(manual.kind)]
	var blueprint := {"kind":"order" if kind == "order" else "unit", "unit_class":null if kind == "order" else kind, "cost":int(manual.cost), "operation_cost":0 if kind == "order" else int(manual.operation_cost), "attack":0 if kind == "order" else int(manual.attack), "health":0 if kind == "order" else int(manual.health), "keywords":creator_keywords.values().duplicate(true)}
	if not str(manual.name).strip_edges().is_empty(): blueprint["name"] = str(manual.name).strip_edges()
	if not creator_effects.is_empty(): blueprint["abilities"] = _creator_abilities()
	return blueprint

func _basic_card_definition() -> Dictionary:
	var definition := _card_blueprint()
	definition["name"] = str(manual.name).strip_edges()
	definition.merge({"schema_version":"1.0.0", "ruleset_version":"frontline-1", "flavor_text":"", "abilities":_creator_abilities(), "tokens":[], "play_target":null, "appearance":{"emblem":"order" if definition.kind == "order" else definition.unit_class}})
	definition["rarity"] = str(manual.get("rarity", "standard"))
	if not str(manual.get("faction_id", "")).is_empty(): definition["faction_id"] = str(manual.faction_id)
	if not str(manual.get("sin", "")).is_empty(): definition["sin"] = str(manual.sin)
	return definition

func _creator_identity_row(form: Control) -> void:
	var row := _hbox(form)
	var rarity := _option(row, ["普通", "限定", "特殊", "精英"], maxi(0, RARITIES.find(str(manual.get("rarity", "standard")))))
	rarity.item_selected.connect(func(index): _edit_manual("rarity", RARITIES[index]))
	var faction_ids := [""]
	var faction_names := ["无阵营"]
	for id in store.factions:
		if bool(store.factions[id].get("archived", false)): continue
		faction_ids.append(id)
		faction_names.append(str(store.factions[id].name))
	var faction := _option(row, faction_names, maxi(0, faction_ids.find(str(manual.get("faction_id", "")))))
	faction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	faction.item_selected.connect(func(index): _edit_manual("faction_id", faction_ids[index]))
	var sin_ids := [""]
	var sin_names := ["无罪孽"]
	for entry in SinCatalog.ENTRIES:
		sin_ids.append(entry.id)
		sin_names.append(entry.name)
	var sin_choice := _option(row, sin_names, maxi(0, sin_ids.find(str(manual.get("sin", "")))))
	sin_choice.item_selected.connect(func(index): _edit_manual("sin", sin_ids[index]))

func _manual_workshop(parent: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var form := _vbox(scroll, 10)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_field := _line(form, str(manual.name), "卡牌名称（必填）")
	name_field.text_changed.connect(func(value): _edit_manual("name", value))
	var types := _option(form, ["步兵", "坦克", "炮兵", "战斗机", "轰炸机", "指令"], int(manual.kind))
	types.item_selected.connect(func(index): _edit_manual("kind", index))
	var numbers := _hbox(form)
	_number_field(numbers, "部署费用", "cost", 1, 12)
	_number_field(numbers, "行动费用", "operation_cost", 0, 4)
	_number_field(numbers, "攻击", "attack", 0, 20)
	_number_field(numbers, "生命", "health", 1, 20)
	var keywords := _hbox(form)
	for pair in [["blitz","突击"],["guard","守护"]]:
		var key: String = pair[0]
		var check := CheckButton.new()
		check.text = pair[1]
		check.button_pressed = bool(manual[key])
		check.toggled.connect(func(value): _edit_manual(key, value))
		keywords.add_child(check)
	_label(form, "技能", 16, GOLD)
	var effect_row := _hbox(form)
	var trigger := _option(effect_row, ["部署时", "己方回合开始", "己方回合结束", "死亡时"], int(manual.trigger))
	trigger.item_selected.connect(func(index): _edit_manual("trigger", index))
	var effect := _option(effect_row, ["无技能", "对一个敌军单位造成伤害", "对敌方总部造成伤害", "抽牌", "恢复己方总部生命", "获得当前资源", "自身攻击和生命增加"], int(manual.effect))
	effect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect.item_selected.connect(func(index): _edit_manual("effect", index))
	_number_field(form, "技能数值（抽牌 / 资源≤3，属性≤5）", "amount", 1, 10)
	_label(form, "其它已登记词条引用（JSON，可选）", 13, MUTED)
	var refs := _editor(form, str(manual.keyword_refs), "[]", 70)
	refs.text_changed.connect(func(): _edit_manual("keyword_refs", refs.text))
	_text(form, "更复杂的多段技能、召唤和目标规则可通过 JSON 导入制作。所有数值由你确认。", 12, MUTED)
	var btn := _button(parent, "校验并预览", _preview_manual, true)
	btn.set_meta("card_action", "preview")
	btn.disabled = busy

func _json_workshop(parent: Control) -> void:
	_text(parent, "粘贴 CardSpec 或 .card.json 导出包。系统会检查字段、效果、参数与独立词条依赖。", 15, MUTED)
	var editor := _editor(parent, json_text, "在这里粘贴你的卡牌 JSON", 350)
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.text_changed.connect(func(): _edit_json(editor.text))
	var actions := _hbox(parent)
	_button(actions, "从文件读取", _open_import_dialog)
	var btn := _button(actions, "校验并预览", _preview_json, true)
	btn.set_meta("card_action", "preview")
	btn.disabled = busy

func _edit_manual(key: String, value: Variant) -> void:
	if manual.get(key) == value:
		return
	manual[key] = value
	if key == "kind":
		if int(value) == 5:
			for effect in creator_effects: effect.trigger = "on_play"
		for ref_key in creator_keywords.keys():
			for definition in store.keyword_definitions:
				if definition.id == creator_keywords[ref_key].id and int(definition.version) == int(creator_keywords[ref_key].version) and not _keyword_fits_card(definition):
					creator_keywords.erase(ref_key)
					break
	_invalidate_card_editor()

func _edit_json(value: String) -> void:
	if json_text == value:
		return
	json_text = value
	_invalidate_card_editor()

func _set_work_mode(value: int) -> void:
	if work_mode == value:
		return
	work_mode = value
	_invalidate_card_editor()

func _invalidate_card_editor() -> void:
	var stale_job := generation_id
	editor_revision += 1
	request_epoch += 1
	busy = false
	draft = {}
	generation = {}
	generation_id = ""
	questions = []
	answers = {}
	card_proposals = []
	last_card_error = ""
	info_text = "输入已修改，请重新生成或预览。"
	_refresh_card_action_buttons()
	# Keep pending_editor_revision unchanged: edited cards must not resume an old keyword-linked task.
	if not stale_job.is_empty():
		store.request("/v1/card-generations/" + stale_job, HTTPClient.METHOD_DELETE)

func _refresh_card_action_buttons() -> void:
	if not is_instance_valid(content):
		return
	for button in content.find_children("*", "BaseButton", true, false):
		match str(button.get_meta("card_action", "")):
			"preview": button.disabled = busy
			"generate":
				button.disabled = busy
				button.text = "正在处理…" if busy else ("校验并预览" if source_text.strip_edges().is_empty() else "完善效果并预览")
			"confirm": button.disabled = busy or draft.is_empty()
			"answers": button.disabled = busy or questions.is_empty()

func _card_request_is_current(epoch: int, revision: int) -> bool:
	if epoch != request_epoch:
		return false
	if revision != editor_revision:
		# Only this request owns busy. A newer epoch must never be cleared by a late result.
		busy = false
		_refresh_card_action_buttons()
		return false
	return true

func _manual_definition() -> Dictionary:
	var classes := ["infantry","tank","artillery","fighter","bomber","order"]
	var kind: String = classes[int(manual.kind)]
	var refs = JSON.parse_string(str(manual.keyword_refs))
	if not refs is Array:
		return {"_error":"其它词条引用必须是 JSON 数组。"}
	var keyword_refs: Array = refs.duplicate(true)
	if manual.blitz:
		keyword_refs.append({"id":"core.blitz","version":1,"params":{}})
	if manual.guard:
		keyword_refs.append({"id":"core.guard","version":1,"params":{}})
	var effects: Array = []
	var target = null
	var amount := int(manual.amount)
	match int(manual.effect):
		1:
			effects.append({"op":"damage","target":"chosen","amount":amount})
			target = {"side":"enemy","row":"any"}
		2: effects.append({"op":"damage","target":"enemy_hq","amount":amount})
		3: effects.append({"op":"draw","player":"owner","amount":amount})
		4: effects.append({"op":"heal","target":"own_hq","amount":amount})
		5: effects.append({"op":"gain_kredits","amount":amount})
		6: effects.append({"op":"modify_stats","target":"self","attack_delta":amount,"health_delta":amount,"duration":"battle"})
	var abilities: Array = []
	if not effects.is_empty():
		abilities.append({"trigger":["on_play","own_turn_start","own_turn_end","on_death"][int(manual.trigger)],"effects":effects})
	return {"schema_version":"1.0.0","ruleset_version":"frontline-1","name":str(manual.name).strip_edges(),"flavor_text":"","kind":"order" if kind == "order" else "unit","unit_class":null if kind == "order" else kind,"cost":int(manual.cost),"operation_cost":0 if kind == "order" else int(manual.operation_cost),"attack":0 if kind == "order" else int(manual.attack),"health":0 if kind == "order" else int(manual.health),"keywords":keyword_refs,"play_target":target,"abilities":abilities,"tokens":[],"appearance":{"emblem":kind}}

func _preview_manual() -> void:
	var definition := _manual_definition()
	if definition.has("_error"):
		_notify(definition._error)
		return
	await _preview_definition(definition)

func _preview_json() -> void:
	var parsed := CardRuntime.parse_json(json_text)
	if not parsed.ok or not parsed.get("value") is Dictionary:
		_card_error(str(parsed.get("error", "JSON 必须是完整对象。")))
		return
	var data: Dictionary = parsed.value
	if data.has("definition") and not data.definition is Dictionary:
		_card_error("导出包 definition 必须是对象。")
		return
	var definition: Dictionary = data.get("definition", data)
	if data.has("definition"):
		if data.size() != 4 or data.get("package_version") != "1" or not data.get("keyword_bindings") is Array or not data.has("definition_hash"):
			_card_error("导出包必须包含 package_version、definition、definition_hash、keyword_bindings 四个字段。")
			return
		var check := CardRuntime.compile_card(definition, store.keyword_definitions)
		if not check.get("ok", false) or CardRuntime.canonical(data.keyword_bindings) != CardRuntime.canonical(check.get("keyword_bindings", [])):
			_card_error("导出包的词条依赖与当前登记版本不匹配。")
			return
	if data.has("definition_hash") and data.definition_hash != CardRuntime.sha(definition):
		_card_error("导出包的哈希与定义不一致。")
		return
	await _preview_definition(definition)

func _card_error(value: String) -> void:
	draft = {}
	info_text = value
	last_card_error = value
	_render()

func _preview_definition(definition: Dictionary) -> void:
	if busy:
		return
	request_epoch += 1
	var epoch := request_epoch
	var revision := editor_revision
	busy = true
	draft = {}
	last_card_error = ""
	info_text = "正在校验规则…"
	_render()
	var result := await store.create_draft(definition.duplicate(true))
	if not _card_request_is_current(epoch, revision):
		return
	busy = false
	if result.ok:
		draft = result.draft
		info_text = "校验通过。确认这张卡牌后，再导入卡库。"
	else:
		draft = {}
		info_text = str(result.error)
		last_card_error = info_text
	if page == "workshop":
		_render()

func _confirm_card() -> void:
	if draft.is_empty() or busy:
		return
	request_epoch += 1
	var epoch := request_epoch
	var revision := editor_revision
	var confirmed_draft := draft.duplicate(true)
	busy = true
	_refresh_card_action_buttons()
	var result := await store.confirm_draft(confirmed_draft)
	if not _card_request_is_current(epoch, revision):
		return
	busy = false
	if result.ok:
		draft = {}
		info_text = "已保存到本地卡库，可以组牌试玩，也可以在右侧提交到 GitHub。"
		_notify(info_text)
	else:
		info_text = str(result.error)
	_render()

func _generate_card() -> void:
	if source_text.strip_edges().is_empty():
		if str(manual.name).strip_edges().is_empty():
			info_text = "请填写卡牌名称。"
			_render()
			return
		await _preview_definition(_basic_card_definition())
		return
	await _start_generation({"request_id":AppStore.uuid(),"editor_revision":editor_revision,"source_text":source_text,"card_blueprint":_card_blueprint(),"clarification_answers":[],"schema_version":"1.0.0","ruleset_version":"frontline-1"})

func _answer_card() -> void:
	var response_answers: Array = []
	for q in questions:
		var answer := str(answers.get(q.id, "")).strip_edges()
		if answer.is_empty():
			_notify("请回答所有待澄清问题。")
			return
		response_answers.append({"question_id":q.id,"answer":answer})
	await _start_generation({"request_id":AppStore.uuid(),"editor_revision":editor_revision,"source_text":source_text,"clarification_answers":response_answers,"parent_generation_id":generation_id,"schema_version":"1.0.0","ruleset_version":"frontline-1"})

func _start_generation(payload: Dictionary) -> void:
	if busy:
		return
	request_epoch += 1
	var epoch := request_epoch
	var rev := editor_revision
	busy = true
	draft = {}
	info_text = "DeepSeek 正在理解你的描述…"
	card_proposals = []
	questions = []
	answers = {}
	_render()
	var result := await store.request("/v1/card-generations", HTTPClient.METHOD_POST, payload)
	if not _card_request_is_current(epoch, rev):
		if result.ok and not str(result.data.get("generation_id", "")).is_empty():
			store.request("/v1/card-generations/" + str(result.data.generation_id), HTTPClient.METHOD_DELETE)
		return
	if not result.ok:
		busy = false
		info_text = str(result.error)
		_render()
		return
	generation_id = str(result.data.get("generation_id", ""))
	await _poll_card_job(generation_id, epoch, rev)

func _poll_card_job(id: String, epoch: int, rev: int) -> void:
	if not _card_request_is_current(epoch, rev):
		return
	generation_id = id
	for attempt in range(48):
		await get_tree().create_timer(1.0 if attempt == 0 else 2.0).timeout
		if not _card_request_is_current(epoch, rev):
			return
		var result := await store.request("/v1/card-generations/" + id)
		if not _card_request_is_current(epoch, rev):
			return
		if not result.ok:
			busy = false
			info_text = str(result.error)
			if page == "workshop": _render()
			return
		generation = result.data
		var status := str(generation.get("status", ""))
		if status in ["queued", "running"]:
			continue
		busy = false
		questions = []
		answers = {}
		var value: Dictionary = generation.get("result", {})
		match status:
			"ready":
				draft = value
				info_text = "生成完成，请检查规则后确认。"
			"needs_clarification":
				questions = value.get("questions", generation.get("questions", []))
				info_text = "模型还需要一些细节。你的原始描述与前面的回答都会保留。"
			"needs_keyword_registration":
				card_proposals = value.get("proposals", [])
				info_text = "请先登记新词条，再继续生成这张卡牌。"
			"unsupported":
				info_text = "当前规则暂不支持：" + "；".join(value.get("reasons", []))
			_:
				var error = generation.get("error", {})
				info_text = str(error.get("message", "生成未完成，请保留描述后重试。")) if error is Dictionary else str(error)
		if page == "workshop": _render()
		return
	if _card_request_is_current(epoch, rev):
		busy = false
		info_text = "等待生成超时。任务记录仍保留，可取消后重试。"
		if page == "workshop": _render()

func _cancel_generation() -> void:
	request_epoch += 1
	busy = false
	draft = {}
	questions = []
	answers = {}
	card_proposals = []
	if not generation_id.is_empty():
		store.request("/v1/card-generations/" + generation_id, HTTPClient.METHOD_DELETE)
	generation_id = ""
	info_text = "生成已取消，输入内容已保留。"
	_render()

func _register_card_keyword() -> void:
	if card_proposals.is_empty(): return
	var first: Dictionary = {}
	for candidate in card_proposals:
		var registered := false
		for keyword in store.keyword_definitions:
			if keyword.get("name", "") == candidate.get("name", "") or candidate.get("name", "") in keyword.get("aliases", []): registered = true
		if not registered:
			first = candidate
			break
	if first.is_empty():
		await _resume_pending_card()
		return
	keyword_source = str(first.get("name", "")) + "：" + str(first.get("requested_behavior", ""))
	pending_generation_id = generation_id
	pending_source = source_text
	pending_editor_revision = editor_revision
	proposal = {}
	_navigate("keywords")

func _questions_ui(parent: Control, question_list: Array, target: Dictionary) -> void:
	for q in question_list:
		_text(parent, str(q.get("question", "")), 15, CREAM)
		var id: String = q.get("id", "")
		var answer := _line(parent, str(target.get(id, "")), "输入你的回答，也可选择下方选项")
		answer.text_changed.connect(func(value): target[id] = value)
		var choices: Array = q.get("options", [])
		if not choices.is_empty():
			var row := _hbox(parent, 6)
			for option in choices:
				var value := str(option)
				var b := _button(row, value, func(): answer.text = value; target[id] = value)
				b.add_theme_font_size_override("font_size", 12)

func _library() -> void:
	var heading := _hbox(content)
	_label(heading,"卡库与构筑",32)
	library_count = _label(heading, "", 12, MUTED)
	_spacer(heading)
	_button(heading, "我的牌组", _saved_decks_dialog).name = "SavedDecksButton"
	_button(heading, "新建牌组", _new_deck_dialog).name = "NewDeckButton"
	var filters_scroll:=ScrollContainer.new();filters_scroll.name="FilterDock"
	filters_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;filters_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	filters_scroll.custom_minimum_size.y=50;content.add_child(filters_scroll)
	var tools:=_hbox(filters_scroll,6);tools.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tools.name="LibraryFilters"
	var search := _line(tools, library_filter, "搜索")
	search.name = "LibrarySearch"
	search.custom_minimum_size.x = 150
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(value): library_filter=value; _populate_library())
	var kinds := ["", "infantry", "tank", "artillery", "fighter", "bomber", "order", "counter", "field", "hq"]
	var types := _option(tools, ["全部类型", "步兵", "坦克", "炮兵", "战斗机", "轰炸机", "指令", "反制", "场地", "总部"], kinds.find(library_kind))
	types.name = "LibraryTypeFilter"
	types.fit_to_longest_item = false
	types.custom_minimum_size.x = 120
	types.item_selected.connect(func(index): library_kind=kinds[index]; _populate_library())
	var sins: Array = ["", "none"] + SinCatalog.IDS
	var sin_names: Array = ["全部罪孽", "未选择罪孽"] + SinCatalog.ENTRIES.map(func(e): return e.name)
	var sin_picker := _option(tools, sin_names, maxi(0,sins.find(library_sin)))
	sin_picker.name = "LibrarySinFilter"
	sin_picker.fit_to_longest_item = false
	sin_picker.custom_minimum_size.x = 120
	sin_picker.item_selected.connect(func(index): library_sin=sins[index]; _populate_library())
	library_faction_picker = _option(tools, ["全部阵营"], 0)
	library_faction_picker.name = "LibraryFactionFilter"
	library_faction_picker.fit_to_longest_item = false
	library_faction_picker.custom_minimum_size.x = 150
	library_faction_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_faction_picker.size_flags_stretch_ratio = 0.5
	library_faction_picker.clip_text = true
	library_faction_entries = []
	_update_library_factions()
	library_faction_picker.item_selected.connect(func(index): library_faction = str(library_faction_picker.get_item_metadata(index)); _populate_library())
	var rarities := [""]+DeckRules.RARITIES
	var rarity := _option(tools, ["全部稀有度", "普通 · 4", "限定 · 3", "特殊 · 2", "精英 · 1"], rarities.find(library_rarity))
	rarity.name = "LibraryRarityFilter"
	rarity.fit_to_longest_item = false
	rarity.custom_minimum_size.x = 130
	rarity.item_selected.connect(func(index): library_rarity=rarities[index]; _populate_library())
	var series_values: Array = [0]+CardSeries.options(store.latest_cards(),store.series_catalog())
	var series_picker := _option(tools,["全部卡包"]+series_values.slice(1).map(func(n):return CardSeries.label(n,store.series_catalog())),maxi(0,series_values.find(library_series)))
	series_picker.name = "LibrarySeriesFilter"
	series_picker.fit_to_longest_item = false
	series_picker.custom_minimum_size.x = 100
	for index in series_values.size(): series_picker.set_item_metadata(index,series_values[index])
	series_picker.item_selected.connect(func(index): library_series=int(series_picker.get_item_metadata(index)); _populate_library())
	var costs: Array = ["全部费用"]
	for fee in range(1,13): costs.append("%d K" % fee)
	var cost_filter := _option(tools, costs, maxi(0,library_cost))
	cost_filter.name = "LibraryCostFilter"
	cost_filter.fit_to_longest_item = false
	cost_filter.custom_minimum_size.x = 120
	cost_filter.item_selected.connect(func(index): library_cost=index if index>0 else -1; _populate_library())
	var row := _hbox(content,20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library_drop = DeckDropScript.new()
	library_drop.name = "LibraryDrop"
	library_drop.accepted_type = "deck_remove"
	library_drop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_drop.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	library_drop.card_dropped.connect(func(id): store.remove_from_deck(id))
	row.add_child(library_drop)
	var shelf := _vbox(library_drop, 14)
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_scroll = ScrollContainer.new()
	library_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	library_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shelf.add_child(library_scroll)
	library_grid = GridContainer.new()
	library_grid.columns = 4
	library_grid.add_theme_constant_override("h_separation", 20)
	library_grid.add_theme_constant_override("v_separation", 24)
	library_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_scroll.add_child(library_grid)
	library_scroll.resized.connect(func(): if is_instance_valid(library_grid): library_grid.columns=maxi(1,int(library_scroll.size.x/222.0)))
	library_card_nodes.clear()
	_populate_library()
	deck_drop = DeckDropScript.new()
	deck_drop.name = "DeckDrop"
	deck_drop.custom_minimum_size.x=302 if size.x<1320 else 320
	deck_drop.add_theme_stylebox_override("panel", ChaoUI.style(Color("141414ed"),Color("adadad33"),12,16))
	deck_drop.card_dropped.connect(_library_add_card)
	row.add_child(deck_drop)
	var side := _vbox(deck_drop,12)
	_label(side,"当前构筑",10,MUTED)
	var deck_header := _hbox(side)
	var title := _button(deck_header, store.deck_name, _save_deck_dialog)
	library_deck_title = title
	title.flat = true
	title.clip_text = true
	title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 19)
	title.tooltip_text = "命名与保存"
	library_deck_count = _label(deck_header, "%02d / 40" % store.deck_ids.size(), 17, GOLD)
	_button(side, "主、副罪孽", _deck_sins_dialog).name="DeckSinsButton"
	var rules_status := _label(side, "", 12, MUTED)
	rules_status.name="DeckRulesStatus"
	rules_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var progress:=ProgressBar.new();progress.name="DeckProgress";progress.max_value=40;progress.value=store.deck_ids.size();progress.show_percentage=false;progress.custom_minimum_size.y=3;side.add_child(progress)
	library_curve=preload("res://scripts/ui/deck_curve.gd").new();side.add_child(library_curve)
	library_headquarters = _button(side,"总部 · 默认",_headquarters_dialog)
	library_headquarters.alignment=HORIZONTAL_ALIGNMENT_LEFT
	library_headquarters.clip_text=true
	deck_scroll = ScrollContainer.new()
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(deck_scroll)
	library_deck_list = _vbox(deck_scroll, 2)
	library_deck_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_deck_nodes.clear()
	_update_library_deck()
	var actions := _hbox(side, 6)
	_button(actions, "保存", _save_deck_dialog,true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(actions, "导入", func(): _deck_browser(false)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_drop.forward_children()
	library_restoring = true
	_restore_library_scroll(library_scroll, deck_scroll)

func _restore_library_scroll(shelf: ScrollContainer, deck: ScrollContainer) -> void:
	# Two layout passes establish the new scroll ranges after a store refresh.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(shelf) or not shelf.is_inside_tree() or shelf != library_scroll: return
	shelf.scroll_vertical = library_scroll_positions.x
	deck.scroll_vertical = library_scroll_positions.y
	library_restoring = false

func _library_add_card(id: String) -> void:
	var record := store.get_card(id)
	if record.is_empty(): return
	if store.active_deck_id.is_empty() and store.deck_ids.is_empty(): _new_deck_dialog(id); return
	var error: String = store.select_headquarters(id) if record.definition.kind=="hq" else store.add_to_deck(id)
	if not error.is_empty(): _notify(error)
	else: audio_system.sound("deploy")

func _library_card_details_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		_card_details(store.get_card(id))

func _new_deck_dialog(first_card := "") -> void:
	var panel := _modal("新建牌组")
	_label(panel,"01  牌组信息    /    02  选牌构筑",12,MUTED)
	var title := _line(panel, "新牌组", "牌组名称")
	title.name="NewDeckName"
	title.max_length = 40
	var ids: Array = [""] + SinCatalog.IDS
	var names: Array = ["请选择"] + SinCatalog.ENTRIES.map(func(e): return e.name)
	var sins:=_hbox(panel,18)
	var main_column:=_vbox(sins,8);main_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var ally_column:=_vbox(sins,8);ally_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_label(main_column, "主罪孽 · 30 张", 14, MUTED)
	var primary := _option(main_column, names, 0)
	primary.name = "NewDeckMainSin"
	_label(ally_column, "副罪孽 · 10 张", 14, MUTED)
	var secondary := _option(ally_column, names, 0)
	secondary.name = "NewDeckAllySin"
	for i in SinCatalog.IDS.size():
		primary.set_item_icon(i+1,SinCatalog.icon(SinCatalog.IDS[i]))
		secondary.set_item_icon(i+1,SinCatalog.icon(SinCatalog.IDS[i]))
	_label(panel,"大阵营限主罪孽，小阵营限副罪孽；无罪孽牌暂通用，可补足名额。",13,MUTED)
	var create := _button(panel, "开始选牌", func():
		var name := title.text.strip_edges()
		if name.is_empty(): _notify("请输入牌组名称。"); return
		if primary.selected==0 or secondary.selected==0 or primary.selected==secondary.selected: _notify("请选择两种不同的主罪孽与副罪孽。"); return
		var result := store.new_local_deck(name, "", ids[primary.selected], ids[secondary.selected])
		if not result.ok: _notify(result.error); return
		_close_modal()
		_navigate("library")
		if not first_card.is_empty(): _library_add_card(first_card)
	, true)
	create.name="StartDeckBuilding"
	create.disabled=true
	primary.item_selected.connect(func(index):
		for i in secondary.item_count: secondary.set_item_disabled(i,i>0 and i==index)
		if secondary.selected==index: secondary.select(0)
		create.disabled=index==0 or secondary.selected==0
	)
	secondary.item_selected.connect(func(index): create.disabled=index==0 or primary.selected==0 or index==primary.selected)

func _deck_sins_dialog() -> void:
	var panel := _modal("修改牌组罪孽")
	var ids: Array = [""]+SinCatalog.IDS
	var names: Array = ["请选择"]+SinCatalog.ENTRIES.map(func(e): return e.name)
	_label(panel,"主罪孽 · 30 张",14,MUTED)
	var primary := _option(panel,names,maxi(0,ids.find(store.main_sin)))
	_label(panel,"副罪孽 · 10 张",14,MUTED)
	var secondary := _option(panel,names,maxi(0,ids.find(store.ally_sin)))
	_label(panel,"修改后保留现有卡牌，可按提示调整不符合规则的卡。",13,MUTED)
	_button(panel,"确定",func():
		var error: String=store.select_deck_sins(ids[primary.selected],ids[secondary.selected])
		if not error.is_empty(): _notify(error); return
		_close_modal()
	,true)

func _deck_sin_text(primary: String, secondary: String) -> String:
	return SinCatalog.label(primary) + (" · "+SinCatalog.label(secondary) if not secondary.is_empty() else "")

func _saved_decks_dialog() -> void:
	var panel := _modal("我的牌组",Vector2(900,620))
	var actions:=_hbox(panel)
	_button(actions,"新建牌组",_new_deck_dialog,true)
	_button(actions,"导入",func():_deck_browser(false))
	var scroll:=ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var list:=GridContainer.new();list.columns=2;scroll.add_child(list)
	list.name="SavedDeckList"
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if store.local_decks.is_empty(): _label(list,"暂无已保存牌组",16,MUTED)
	for entry in store.local_decks.duplicate(true):
		var box:=PanelContainer.new()
		var sin_color:=SinCatalog.color_for({"sin":entry.get("main_sin","")})
		box.add_theme_stylebox_override("panel",ChaoUI.style(sin_color.lerp(Color("202020ee"),0.68),ChaoUI.BORDER,12,18))
		box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		list.add_child(box)
		var body:=_vbox(box,12)
		var row:=_hbox(body,12)
		var symbol:=TextureRect.new();symbol.texture=SinCatalog.icon(str(entry.get("main_sin","")));symbol.custom_minimum_size=Vector2(46,46);symbol.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;symbol.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;row.add_child(symbol)
		var info:=_vbox(row,5)
		info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var title:=_label(info,str(entry.name),19)
		title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		title.tooltip_text=str(entry.name)
		_label(info,"%d / 40 · %s"%[entry.cards.size(),_deck_sin_text(str(entry.get("main_sin","")),str(entry.get("ally_sin","")))],13,MUTED)
		var controls:=_hbox(body,8)
		var edit:=_button(controls,"编辑牌组",func():
			var result:=store.load_local_deck(entry.id)
			if not result.ok: _notify(result.error); return
			_close_modal()
			_navigate("library")
		)
		edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		edit.name="EditDeck_"+str(entry.id)
		_button(controls,"重命名",func():_rename_deck_dialog(entry))
		_button(controls,"删除",func():_delete_deck_dialog(entry))

func _rename_deck_dialog(entry: Dictionary) -> void:
	var panel:=_modal("重命名牌组")
	var title:=_line(panel,str(entry.name),"牌组名称")
	title.max_length=40
	_button(panel,"保存",func():
		var result:=store.rename_local_deck(str(entry.id),title.text)
		if result.ok: _saved_decks_dialog()
		else: _notify(result.error)
	,true)

func _delete_deck_dialog(entry: Dictionary) -> void:
	var panel:=_modal("删除本地牌组")
	_label(panel,str(entry.name),19)
	_button(panel,"删除",func():
		var result:=store.delete_local_deck(str(entry.id))
		if result.ok: _saved_decks_dialog()
		else: _notify(result.error)
	,true)


func _save_deck_dialog() -> void:
	var panel := _modal("保存牌组")
	var title := _line(panel, store.deck_name, "牌组名称")
	title.name="SaveDeckName"
	title.max_length = 40
	_label(panel,_deck_sin_text(store.main_sin,store.ally_sin),14,MUTED)
	var actions := _hbox(panel)
	var save := func(as_copy: bool):
		var result := store.save_local_deck(title.text, as_copy)
		if not result.ok: _notify(result.error); return
		_close_modal()
		_render()
		_notify("已保存到本地。")
	_button(actions, "保存", func(): save.call(false), true).name="ConfirmDeckSave"
	_button(actions, "另存为新牌组", func(): save.call(true))

func _publish_deck_dialog() -> void:
	var prepared := store.cloud_deck_refs()
	if not prepared.ok: _notify(prepared.error); return
	var panel := _modal("上传共享牌组")
	var title := _line(panel, store.deck_name, "牌组名称")
	title.max_length = 40
	_label(panel, "40 张 · 其他玩家可选用此牌组", 14, MUTED)
	var publish := _button(panel, "上传", func(): pass, true)
	publish.pressed.connect(func():
		var saved := store.save_local_deck(title.text)
		if not saved.ok: _notify(saved.error); return
		publish.disabled = true
		publish.text = "上传中…"
		var result := await store.publish_deck()
		if not is_instance_valid(publish): return
		publish.disabled = false
		publish.text = "上传"
		if not result.ok: _notify(result.error); return
		_close_modal()
		_render()
		_notify("牌组已共享。")
	)

func _deck_browser(shared: bool, mine: bool = false, cursor: String = "0") -> void:
	var panel := _modal("导入牌组")
	var tabs := _hbox(panel)
	_button(tabs, "本地", func(): _deck_browser(false), not shared)
	_button(tabs, "JSON", _import_deck_json_dialog)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 330
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var list := _vbox(scroll, 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var entries: Array = store.local_decks.duplicate(true)
	var next_cursor: Variant = null
	if shared:
		var status := _label(list, "读取中…", 14, MUTED)
		var endpoint := "/v1/decks" if store.authenticated else "/v1/public/decks"
		var result := await store.request(endpoint + "?cursor=" + cursor + ("&mine=1" if mine else ""))
		if not is_instance_valid(list): return
		status.queue_free()
		if not result.ok: _label(list, result.error, 14, GOLD); return
		entries = result.data.get("decks", [])
		next_cursor = result.data.get("next_cursor")
	else:
		entries.reverse()
	if entries.is_empty(): _label(list, "暂无牌组", 14, MUTED)
	for entry in entries:
		var row := _hbox(list, 12)
		var column := _vbox(row, 3)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := _label(column, str(entry.name), 17)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var count: int = int(entry.get("card_count", 0)) if shared else entry.cards.size()
		_label(column, (str(entry.get("author", {}).get("name", "未署名")) + " · " if shared else "") + "%d / 40" % count + (" · 已撤回" if shared and not entry.get("published", true) else ""), 12, MUTED)
		if shared:
			_button(row, "查看", func(): _shared_deck_detail(str(entry.deck_id)))
		else:
			_button(row, "选用", func():
				var result := store.load_local_deck(entry.id)
				if result.ok: _close_modal()
				else: _notify(result.error)
			)
	if next_cursor != null: _button(panel, "下一页", func(): _deck_browser(true, mine, str(next_cursor)))
	elif cursor != "0": _button(panel, "返回首页", func(): _deck_browser(true, mine))

func _import_deck_json_dialog() -> void:
	var panel := _modal("导入牌组")
	var tabs := _hbox(panel)
	_button(tabs, "本地", func(): _deck_browser(false))
	_button(tabs, "JSON", _import_deck_json_dialog, true)
	var editor := _editor(panel, "", "粘贴牌组 JSON", 300)
	editor.name = "DeckImportJSON"
	var actions := _hbox(panel)
	_button(actions, "选择文件", func():
		var picker := FileDialog.new()
		picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		picker.access = FileDialog.ACCESS_FILESYSTEM
		picker.filters = PackedStringArray(["*.json ; JSON"])
		picker.use_native_dialog = mobile
		add_child(picker)
		picker.file_selected.connect(func(path):
			if is_instance_valid(editor):
				var file := FileAccess.open(path,FileAccess.READ)
				if file == null: _notify("无法读取文件。")
				elif file.get_length() > 8388608: _notify("牌组文件不能超过 8 MB。")
				else: editor.text=file.get_as_text()
			picker.queue_free()
		)
		picker.canceled.connect(picker.queue_free)
		picker.popup_centered(Vector2i(800,560))
	)
	_button(actions, "导入", func():
		var result := store.import_deck_json(editor.text)
		if not result.ok: _notify(result.error); return
		_close_modal()
		_render()
		_notify("牌组已导入。")
	, true)

func _shared_deck_detail(id: String) -> void:
	var panel := _modal("共享牌组")
	var status := _label(panel, "读取中…", 14, MUTED)
	var result := await store.request(("/v1/decks/" if store.authenticated else "/v1/public/decks/") + id)
	if not is_instance_valid(panel): return
	if not result.ok: status.text = result.error; return
	var bundle: Dictionary = result.data
	status.text = str(bundle.deck.name) + " · " + str(bundle.deck.author.name)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 340
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var list := _vbox(scroll, 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for record in bundle.cards:
		var strip := DeckStripScript.new()
		strip.record = record
		strip.draggable = false
		strip.copies = bundle.deck.cards.filter(func(ref): return ref.card_id==record.card_id and ref.revision==record.revision).size()
		list.add_child(strip)
	var actions := _hbox(panel)
	_button(actions, "选用并保存到本地", func():
		var accepted := store.accept_shared_deck(bundle)
		if accepted.ok: _close_modal(); _notify("已保存到本地。")
		else: _notify(accepted.error)
	, true)
	if bundle.deck.get("owned_by_me", false) and bundle.deck.get("published", true):
		var withdraw := _button(actions, "撤回共享", func(): pass)
		withdraw.pressed.connect(func():
			withdraw.disabled = true
			var response := await store.request("/v1/decks/"+id, HTTPClient.METHOD_DELETE)
			if not is_instance_valid(withdraw): return
			if not response.ok: withdraw.disabled=false; _notify(response.error); return
			for entry in store.local_decks:
				var published: Dictionary = entry.get("shared", {}).get(store._scope(), {})
				if published.get("deck_id") == id: entry.shared[store._scope()] = response.data
			store.save_profile()
			_deck_browser(true, true)
		)

func _update_library_factions() -> void:
	if not is_instance_valid(library_faction_picker): return
	var entries: Array = store.factions.values().filter(func(f): return not f.get("archived", false))
	entries.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	var options: Array = entries.map(func(f): return [str(f.faction_id), str(f.name)])
	options.push_front(["", "全部阵营"])
	if options == library_faction_entries: return
	library_faction_entries = options
	library_faction_picker.clear()
	var selected := 0
	for item in options:
		var index := library_faction_picker.item_count
		library_faction_picker.add_item(item[1])
		library_faction_picker.set_item_metadata(index, item[0])
		if item[0] == library_faction: selected = index
	library_faction = str(options[selected][0])
	library_faction_picker.select(selected)

func _headquarters_dialog() -> void:
	var box := _modal("选择总部", Vector2(700,540))
	_button(box,"默认总部 · 20 防御 · 每回合抽 1 张",func(): store.select_headquarters(""); _close_modal())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(0,360)
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var list := _vbox(scroll,8)
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for record in store.latest_cards():
		if record.definition.kind!="hq": continue
		var item := _button(list,str(record.definition.name),func():
			var error := store.select_headquarters(record.card_id)
			if not error.is_empty(): _notify(error)
			else: _close_modal()
		)
		item.tooltip_text=CardRuntime.rules_text(store.display_definition(record))

func _update_library_deck() -> void:
	if not is_instance_valid(library_deck_list): return
	var sins_button := deck_drop.find_child("DeckSinsButton",true,false)
	if sins_button!=null: sins_button.text=_deck_sin_text(store.main_sin,store.ally_sin)+" · 修改"
	var rules_status := deck_drop.find_child("DeckRulesStatus",true,false)
	if rules_status!=null:
		var composition: Dictionary=store.deck_composition()
		var primary_count := 0
		var secondary_count := 0
		var neutral_count := 0
		for id in store.deck_ids:
			var definition: Dictionary=store.get_card(id).get("definition",{})
			if definition.get("sin")==null or definition.get("sin")=="": neutral_count+=1
			elif definition.get("sin")==store.main_sin: primary_count+=1
			elif definition.get("sin")==store.ally_sin: secondary_count+=1
		rules_status.text="主罪孽 %d / 30 · 副罪孽 %d / 10" % [primary_count,secondary_count]
		if neutral_count>0: rules_status.text+="\n通用 %d 张 · 自动补足剩余名额" % neutral_count
		if not composition.error.is_empty(): rules_status.text+="\n"+str(composition.error)
	library_deck_title.text = store.deck_name
	if is_instance_valid(library_headquarters):
		var hq: Dictionary=store.get_card(store.headquarters_id)
		library_headquarters.text="总部 · "+str(hq.get("definition",{}).get("name","默认"))
	library_deck_count.text = "%02d / 40" % store.deck_ids.size()
	var progress:=deck_drop.find_child("DeckProgress",true,false)
	if progress!=null:progress.value=store.deck_ids.size()
	if is_instance_valid(library_curve):
		var distribution:Array=[];distribution.resize(8);distribution.fill(0)
		for id in store.deck_ids:
			var card:Dictionary=store.get_card(id)
			if not card.is_empty():distribution[mini(7,int(card.definition.cost))]+=1
		library_curve.counts=distribution;library_curve.queue_redraw()
	var counts := {}
	var entries := {}
	for id in store.deck_ids:
		counts[id] = int(counts.get(id, 0)) + 1
		if not entries.has(id): entries[id] = store.get_card(id)
	var ids: Array = counts.keys().filter(func(id): return not entries[id].is_empty())
	ids.sort_custom(func(a, b):
		var x: Dictionary = entries[a].definition
		var y: Dictionary = entries[b].definition
		return str(x.name).naturalnocasecmp_to(str(y.name)) < 0 if x.cost == y.cost else x.cost < y.cost
	)
	for id in library_deck_nodes.keys():
		if not id in ids:
			var obsolete: Control = library_deck_nodes[id]
			library_deck_list.remove_child(obsolete)
			obsolete.queue_free()
			library_deck_nodes.erase(id)
	var empty := library_deck_list.get_node_or_null("EmptyDeck")
	if ids.is_empty():
		if empty == null: _label(library_deck_list, "点击或拖入卡牌", 14, MUTED).name = "EmptyDeck"
	elif empty != null:
		library_deck_list.remove_child(empty)
		empty.queue_free()
	for index in ids.size():
		var id: String = ids[index]
		var strip: Button = library_deck_nodes.get(id)
		if strip == null:
			strip = DeckStripScript.new()
			strip.record = entries[id]
			strip.pressed.connect(func():
				if is_instance_valid(strip) and strip.is_inside_tree() and not strip.ignore_touch_click(): store.remove_from_deck(id)
			,CONNECT_DEFERRED)
			strip.gui_input.connect(func(event):_library_card_details_input(event,id))
			strip.touch_gate.inspect_requested = func(): _card_details(store.get_card(id))
			strip.drag_started.connect(func(_data): _close_modal(false))
			library_deck_nodes[id] = strip
			library_deck_list.add_child(strip)
		strip.record = entries[id]
		strip.copies = counts[id]
		strip.queue_redraw()
		if strip.get_index() != index: library_deck_list.move_child(strip, index)
	deck_drop.forward_children()

func _update_library_series() -> void:
	var picker: OptionButton = content.find_child("LibrarySeriesFilter",true,false)
	if picker == null: return
	var catalog := store.series_catalog()
	var values: Array = [0]+CardSeries.options(store.latest_cards(),catalog)
	var labels: Array = ["全部卡包"]+values.slice(1).map(func(n):return CardSeries.label(n,catalog))
	var unchanged := picker.item_count == values.size()
	if unchanged:
		for i in values.size():
			if picker.get_item_metadata(i) != values[i] or picker.get_item_text(i) != labels[i]: unchanged=false; break
	if unchanged: return
	picker.clear()
	for i in values.size():
		picker.add_item(labels[i])
		picker.set_item_metadata(i,values[i])
	if not library_series in values: library_series=0
	picker.select(values.find(library_series))

func _populate_library() -> void:
	if not is_instance_valid(library_grid): return
	var visible_cards: Array = []
	for latest in store.latest_cards():
		var entry: Dictionary = store.get_card(str(library_versions.get(store.card_identity(latest), latest.card_id)))
		if entry.is_empty(): entry = latest
		if library_series>0 and CardSeries.number(entry)!=library_series: continue
		var spec: Dictionary = entry.definition
		var kind := str(spec.unit_class) if spec.kind == "unit" else str(spec.kind)
		if not library_kind.is_empty() and kind != library_kind and not library_kind in CardRuntime.definition_classes(store.display_definition(entry)): continue
		if not library_rarity.is_empty() and DeckRules.rarity(spec) != library_rarity: continue
		if not library_sin.is_empty() and (not SinCatalog.id_of(spec).is_empty() if library_sin=="none" else SinCatalog.id_of(spec)!=library_sin): continue
		if not library_faction.is_empty() and spec.get("faction_id", "") != library_faction: continue
		if library_cost >= 0 and int(spec.cost) != library_cost: continue
		if not library_filter.strip_edges().is_empty():
			var text := str(spec.name)+SinCatalog.label(SinCatalog.id_of(spec))+str(FactionCatalog.info(spec).get("name", ""))+store.card_author(entry)+CardRuntime.rules_text(store.display_definition(entry))
			if not library_filter.strip_edges().to_lower() in text.to_lower(): continue
		visible_cards.append(entry)
	visible_cards.sort_custom(func(a:Dictionary,b:Dictionary): return str(a.definition.name).naturalnocasecmp_to(str(b.definition.name)) < 0 if library_sort==1 or a.definition.cost==b.definition.cost else a.definition.cost<b.definition.cost)
	library_count.text = "%d 张卡牌" % visible_cards.size()
	var ids: Array = visible_cards.map(func(entry): return str(entry.card_id))
	for id in library_card_nodes.keys():
		if not id in ids:
			var obsolete: Control = library_card_nodes[id]
			library_grid.remove_child(obsolete)
			obsolete.queue_free()
			library_card_nodes.erase(id)
	var empty := library_grid.get_node_or_null("EmptyLibrary")
	if ids.is_empty():
		if empty == null: _label(library_grid, "暂无匹配卡牌" if not store.cards.is_empty() else "暂无卡牌", 18, MUTED).name = "EmptyLibrary"
	elif empty != null:
		library_grid.remove_child(empty)
		empty.queue_free()
	for index in visible_cards.size():
		var entry: Dictionary = visible_cards[index]
		var id := str(entry.card_id)
		var column: VBoxContainer = library_card_nodes.get(id)
		if column == null:
			column = _vbox(library_grid, 8)
			column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			column.custom_minimum_size.x = 202
			var face := CardScript.new()
			face.spec = store.display_definition(entry)
			face.drag_payload = {"type":"deck_add","card_id":id} if DeckRules.can_include(entry.definition) else {}
			face.art_id = str(entry.get("art", {}).get("id", ""))
			face.pressed.connect(func():
				if is_instance_valid(face) and face.is_inside_tree() and not face.ignore_touch_click(): _library_add_card(id)
			,CONNECT_DEFERRED)
			face.gui_input.connect(func(event):_library_card_details_input(event,id))
			face.touch_gate.inspect_requested = func(): _card_details(store.get_card(id))
			face.drag_started.connect(func(_data): _close_modal(false))
			column.add_child(face)
			face.custom_minimum_size = CardScript.full_size(202)
			if entry.has("derived_from"): _label(column, "衍生 · 可入组" if DeckRules.can_include(entry.definition) else "衍生 · 不可入组", 12, MUTED)
			library_card_nodes[id] = column
		else:
			var face: CardFace = column.get_child(0)
			face.drag_payload = {"type":"deck_add","card_id":id} if DeckRules.can_include(entry.definition) else {}
			face.author_name = store.card_author(entry)
			face.art_id = str(entry.get("art", {}).get("id", ""))
			face.refresh_art()
			face.queue_redraw()
		if column.get_index() != index: library_grid.move_child(column, index)
	if is_instance_valid(library_drop): library_drop.forward_children()

func _card_details(record: Dictionary) -> void:
	var panel := _modal(str(record.definition.name))
	var row := _hbox(panel, 24)
	var face := CardScript.new()
	face.spec = store.compile_record(record).get("definition",record.definition)
	face.author_name = store.card_author(record)
	face.art_id = str(record.get("art", {}).get("id", ""))
	face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(face)
	face.custom_minimum_size = CardScript.full_size(280)
	var info := _vbox(row, 11)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var identity := store.card_identity(record)
	var latest: Dictionary = record
	for candidate in store.latest_cards():
		if store.card_identity(candidate) == identity: latest=candidate
	_label(info, "卡牌资料", 12, MUTED)
	var versions := OptionButton.new()
	for version in latest.get("available_revisions",range(int(latest.get("revision",1)),0,-1)):
		versions.add_item("v%d%s" % [version, " · 最新" if version==int(latest.get("revision",1)) else ""],version)
		if version == int(record.get("revision",1)): versions.select(versions.item_count-1)
	info.add_child(versions)
	versions.item_selected.connect(func(index):
		var result := await store.load_card_version(latest,versions.get_item_id(index))
		if not result.ok: _notify(result.error); return
		library_versions[identity] = result.card.card_id
		_render()
		_card_details(result.card)
	)
	_rules_info(info,face.spec)
	var related := preload("res://scripts/ui/related_cards.gd")
	var compiled := store.compile_record(record)
	if compiled.get("ok",false) and not related.entries(compiled).is_empty():
		_button(info,"查看衍生卡",func():
			var container:=_modal("衍生卡")
			var viewer:=related.new();viewer.parent_card=compiled;viewer.custom_minimum_size=Vector2(850,590);container.add_child(viewer)
			viewer.closed.connect(func():_card_details(record))
		)
	if record.definition.has("veteran"):
		_button(info,"查看老兵形态",func(): _veteran_details(record))
	_label(info, "总部 · 单独选择1张" if record.definition.kind=="hq" else "%s · 最多 %d 张" % [DeckRules.NAMES.get(DeckRules.rarity(record.definition),"普通"), DeckRules.limit(record.definition)], 13, GOLD)
	_label(info, "罪孽 · "+SinCatalog.label(SinCatalog.id_of(record.definition)), 13, MUTED)
	_label(info, "阵营 · "+str(store.factions.get(str(record.definition.get("faction_id", "")), {}).get("name", "未指定")), 13, MUTED)
	_label(info, "作者 · "+store.card_author(record), 13, MUTED)
	if record.has("derived_from"):
		_label(info, "来源 · "+str(record.derived_from.get("name","")), 13, MUTED)
		_label(info, "允许加入牌组" if DeckRules.can_include(record.definition) else "衍生卡 · 不可主动加入牌组", 13, GOLD)
	if record.definition.kind=="hq":
		_button(info,"设为总部",func(): store.select_headquarters(record.card_id); _close_modal(),true)
	_button(info, "在卡库中选用", func(): library_versions[identity]=record.card_id; _close_modal(); _render(), true)

func _keywords() -> void:
	var top:=_hbox(content);_label(top,"词条图鉴",32);_spacer(top)
	var search:=_line(content,"","查找词条名称或描述")
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;content.add_child(scroll)
	var grid:=GridContainer.new();grid.columns=2;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_theme_constant_override("h_separation",18);grid.add_theme_constant_override("v_separation",16);scroll.add_child(grid)
	var latest:Dictionary={}
	for definition in store.keyword_definitions:
		if not latest.has(definition.id) or int(definition.version)>int(latest[definition.id].version):latest[definition.id]=definition
	for keyword in latest.values():
		var state:Dictionary=store.content_status("keywords",str(keyword.id))
		if state.get("archived",false) or state.get("deleted",false):continue
		var panel:=_panel(grid);panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var heading:=_hbox(panel);_label(heading,str(keyword.get("name","")),22);_spacer(heading);_label(heading,"v%s"%keyword.get("version",1),11,MUTED)
		_text(panel,CardRuntime.keyword_description(str(keyword.id),str(keyword.get("description",""))),15,MUTED)
		var tile:Control=panel.get_parent();tile.set_meta("filter",str(keyword.get("name",""))+str(keyword.get("description","")))
	search.text_changed.connect(func(text):
		for tile in grid.get_children():tile.visible=text.strip_edges().to_lower() in str(tile.get_meta("filter","")).to_lower())
	if latest.is_empty():_label(grid,"暂无词条",16,MUTED)

func _use_keyword(keyword: Dictionary) -> void:
	var params := {}
	for key in keyword.get("parameters", {}):
		params[key] = keyword.parameters[key].minimum
	var refs = JSON.parse_string(str(manual.keyword_refs))
	if not refs is Array: refs = []
	if keyword.id in ["core.blitz", "core.guard"]:
		manual["blitz" if keyword.id == "core.blitz" else "guard"] = true
	else:
		refs.append({"id":keyword.id,"version":keyword.version,"params":params})
		manual.keyword_refs = JSON.stringify(refs)
	work_mode = 1
	_invalidate_card_editor()
	_navigate("workshop")

func _generate_keyword() -> void:
	if keyword_source.strip_edges().is_empty() or keyword_busy:
		_notify("请先描述词条的含义。")
		return
	keyword_busy = true
	keyword_epoch += 1
	var epoch := keyword_epoch
	var result := await store.request("/v1/keyword-proposals", HTTPClient.METHOD_POST, {"request_id":AppStore.uuid(),"source_text":keyword_source,"suggested_name":keyword_source.split("：")[0].left(32),"related_generation_id":pending_generation_id if not pending_generation_id.is_empty() else null})
	if not result.ok:
		keyword_busy = false
		_notify(result.error)
		return
	await _poll_keyword(str(result.data.get("proposal_id", "")), epoch)

func _poll_keyword(id: String, epoch: int) -> void:
	for attempt in range(48):
		if epoch != keyword_epoch: return
		var result := await store.request("/v1/keyword-proposals/" + id)
		if not result.ok:
			keyword_busy = false
			_notify(result.error)
			return
		proposal = result.data
		if str(proposal.get("status", "")) != "proposed":
			keyword_busy = false
			keyword_answers = {}
			if page == "keywords": _render()
			return
		if attempt == 0 and page == "keywords": _render()
		await get_tree().create_timer(2.0).timeout
	keyword_busy = false
	_notify("词条生成仍未完成，请稍后重试。")

func _answer_keyword() -> void:
	var reply: Array = []
	for q in proposal.get("questions", []):
		var answer := str(keyword_answers.get(q.id, "")).strip_edges()
		if answer.is_empty(): _notify("请回答词条的所有问题。"); return
		reply.append({"question_id":q.id,"answer":answer})
	keyword_busy = true
	keyword_epoch += 1
	var result := await store.request("/v1/keyword-proposals/" + str(proposal.proposal_id) + "/answers", HTTPClient.METHOD_POST, {"request_id":AppStore.uuid(),"expected_revision":proposal.revision,"answers":reply})
	if result.ok:
		await _poll_keyword(str(proposal.proposal_id), keyword_epoch)
	else:
		keyword_busy = false
		_notify(result.error)

func _confirm_keyword() -> void:
	if keyword_busy: return
	keyword_busy = true
	var result := await store.request("/v1/keyword-proposals/" + str(proposal.proposal_id) + "/confirm", HTTPClient.METHOD_POST, {"request_id":AppStore.uuid(),"expected_revision":proposal.revision,"candidate_hash":proposal.candidate_hash})
	keyword_busy = false
	if result.ok:
		proposal.status = "approved"
		if result.data.has("resumed_generation_id"):
			proposal["resumed_generation_id"] = result.data.resumed_generation_id
		await store.refresh()
		_notify("词条已通过自动校验并登记。")
		_render()
	else:
		_notify(result.error)

func _resume_pending_card() -> void:
	if busy:
		return
	if pending_source.is_empty() or pending_editor_revision != editor_revision:
		_notify("原卡牌内容已变更，请从当前编辑内容继续生成。")
		return
	_navigate("workshop")
	var resume_epoch := request_epoch
	var resume_revision := editor_revision
	var resumed := str(proposal.get("resumed_generation_id", ""))
	if resumed.is_empty() and not pending_generation_id.is_empty():
		var old := await store.request("/v1/card-generations/" + pending_generation_id)
		if not _card_request_is_current(resume_epoch, resume_revision):
			return
		if old.ok: resumed = str(old.data.get("resumed_generation_id", ""))
	if not resumed.is_empty():
		request_epoch += 1
		busy = true
		info_text = "继续先前的生成任务，已保留澄清历史。"
		_render()
		await _poll_card_job(resumed, request_epoch, editor_revision)
		return
	for candidate in card_proposals:
		var registered := false
		for keyword in store.keyword_definitions:
			if keyword.get("name", "") == candidate.get("name", "") or candidate.get("name", "") in keyword.get("aliases", []): registered = true
		if not registered:
			info_text = "还有词条需要登记：" + str(candidate.get("name", ""))
			_render()
			return
	await _start_generation({"request_id":AppStore.uuid(),"editor_revision":editor_revision,"source_text":pending_source,"clarification_answers":[],"parent_generation_id":pending_generation_id,"schema_version":"1.0.0","ruleset_version":"frontline-1"})

func _manual_keyword_dialog() -> void:
	var panel := _modal("导入独立词条定义")
	_text(panel, "粘贴 KeywordDefinition。普通玩家只能登记受约束的 template；校验后仍需在词条页面确认。", 14, MUTED)
	var editor := _editor(panel, keyword_json, "粘贴词条 JSON", 300)
	_button(panel, "校验词条草稿", func():
		keyword_json = editor.text
		var parsed := CardRuntime.parse_json(keyword_json)
		if not parsed.ok or not parsed.get("value") is Dictionary: _notify("词条必须是完整且没有重复键的 JSON 对象。"); return
		var body := {"request_id":AppStore.uuid(),"definition":parsed.value}
		if not pending_generation_id.is_empty(): body["related_generation_id"] = pending_generation_id
		var result := await store.request("/v1/keyword-imports", HTTPClient.METHOD_POST, body)
		if result.ok:
			proposal = result.data.get("proposal", result.data)
			_close_modal()
			_render()
		else: _notify(result.error)
	, true)

func _network_lobby() -> void:
	var heading:=_hbox(content);_label(heading,"选择战场",32);_spacer(heading)
	_button(heading,"切换牌组",_saved_decks_dialog)
	var row:=_hbox(content,20);row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var side:=_vbox(row,18);side.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var practice:=_panel(side);practice.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_label(practice,"练习场",27);_label(practice,"PRACTICE",11,GOLD)
	_text(practice,store.deck_name+"  ·  %d / 40"%store.deck_ids.size(),15,MUTED)
	_text(practice,"使用当前牌组进行镜像练习。",15,MUTED);_spacer(practice,true)
	_button(practice,"开始练习",_start_solo,true)
	_button(practice,"编辑当前牌组",func():_navigate("library"))
	var lan:=_panel(side);_label(lan,"局域网",21);_button(lan,"直连设备",_lan_dialog)
	if match_controller.mode!="menu":
		_button(lan,"返回进行中的对局",func():_navigate("battle"))

func _lan_dialog() -> void:
	var network := _modal("局域网直连")
	var address := _line(network, host_address, "主机 IP，例如 192.168.1.10")
	address.text_changed.connect(func(value): host_address = value)
	var port := SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = port_number
	port.prefix = "UDP 端口  "
	port.value_changed.connect(func(value): port_number = int(value))
	network.add_child(port)
	var my_ips: Array[String] = []
	for address_value in IP.get_local_addresses():
		if address_value.begins_with("192.168.") or address_value.begins_with("10."):
			my_ips.append(address_value)
	_text(network, "本机局域网地址：" + (" / ".join(my_ips) if not my_ips.is_empty() else "请查看系统网络设置"), 13, GOLD)
	_text(network, "双方需要使用相同版本，并位于同一局域网或可互通的网络。", 13, MUTED)
	var actions := _hbox(network)
	_button(actions, "创建房间", func(): _close_modal(); _host_match(), true)
	_button(actions, "加入房间", func(): _close_modal(); _join_match())

func _refresh_cloud_rooms() -> void:
	if cloud_loading: return
	cloud_loading = true
	var result := await store.request("/v1/rooms")
	cloud_loading = false
	if result.ok: cloud_rooms = result.data.get("rooms", [])
	else: _notify(result.error)
	if page == "network": _render()

func _start_cloud(room_id: String) -> void:
	if cloud_loading or not _can_begin_match(): return
	cloud_loading = true
	await store.refresh()
	var prepared := store.cloud_deck_refs()
	if not prepared.ok:
		cloud_loading = false
		_notify(prepared.error)
		return
	var error: int = await match_controller.start_cloud(store, prepared.get("deck", prepared.get("refs", [])), room_id, prepared.get("headquarters"))
	cloud_loading = false
	if error != OK: return
	_navigate("battle")

func _choose_spectator(room_id: String) -> void:
	if cloud_loading: return
	if match_controller.mode!="menu":
		if match_controller.spectating and room_id in [match_controller.cloud_room_id,match_controller.cloud_room_code]: _navigate("battle")
		else: _notify("请先离开当前对局或观战。")
		return
	cloud_loading=true
	var result: Dictionary=await store.request("/v1/rooms")
	cloud_loading=false
	if not result.get("ok",false): _notify(str(result.get("error","无法读取房间")));return
	cloud_rooms=result.data.get("rooms",[])
	for room in cloud_rooms:
		if room_id not in [str(room.room_id),str(room.code)]: continue
		if room.status not in ["active","suspended"]: _notify("对局开始后才能观战。");return
		var panel:=_modal("选择跟随玩家")
		_text(panel,"只显示所选一方的手牌，本局视角固定。",16,MUTED)
		var names: Array=room.get("commanders",["房主","对手"])
		for seat in [0,1]:
			if room.get("followed_player")!=null and int(room.followed_player)!=seat: continue
			_button(panel,str(names[seat]),_start_spectating.bind(str(room.room_id),seat),true)
		return
	_notify("未找到正在进行的房间。")

func _start_spectating(room_id: String, seat: int) -> void:
	if cloud_loading or match_controller.mode!="menu": return
	_close_modal()
	cloud_loading=true
	var error: int=await match_controller.watch_cloud(store,room_id,seat)
	cloud_loading=false
	if error==OK: _navigate("battle")
	elif page=="network": _render()

func _start_solo() -> void:
	if not _can_begin_match(): return
	match_controller.faction_catalog = store.factions.duplicate(true)
	match_controller.main_sin = store.main_sin
	match_controller.ally_sin = store.ally_sin
	match_controller.commander_name = str(store.account_identity.get("display_name",store.settings.get("player_name","指挥官")))
	match_controller.main_faction_id = store.main_faction_id
	var deck := store.compile_deck()
	if not deck.ok: _notify(deck.error); return
	match_controller.headquarters=deck.headquarters
	var err: String = match_controller.start_solo(deck.deck, deck.get("keyword_definitions", store.keyword_definitions))
	if not err.is_empty(): _notify(err); return
	_navigate("battle")

func _host_match() -> void:
	if not _can_begin_match(): return
	match_controller.faction_catalog = store.factions.duplicate(true)
	match_controller.main_sin = store.main_sin
	match_controller.ally_sin = store.ally_sin
	match_controller.commander_name = str(store.account_identity.get("display_name",store.settings.get("player_name","指挥官")))
	match_controller.main_faction_id = store.main_faction_id
	var deck := store.compile_deck()
	if not deck.ok: _notify(deck.error); return
	match_controller.headquarters=deck.headquarters
	var err: int = match_controller.host_game(deck.deck, deck.get("keyword_definitions", store.keyword_definitions), port_number)
	if err != OK: _notify("房间创建失败：" + error_string(err)); return
	_navigate("battle")

func _join_match() -> void:
	if not _can_begin_match(): return
	match_controller.faction_catalog = store.factions.duplicate(true)
	match_controller.main_sin = store.main_sin
	match_controller.ally_sin = store.ally_sin
	match_controller.commander_name = str(store.account_identity.get("display_name",store.settings.get("player_name","指挥官")))
	match_controller.main_faction_id = store.main_faction_id
	var deck := store.compile_deck()
	if not deck.ok: _notify(deck.error); return
	match_controller.headquarters=deck.headquarters
	var err: int = match_controller.join_game(host_address, deck.deck, deck.get("keyword_definitions", store.keyword_definitions), port_number)
	if err != OK: _notify("加入失败：" + error_string(err)); return
	_navigate("battle")

func _can_begin_match() -> bool:
	if match_controller.mode != "menu":
		_notify("已有一场对局或房间，请先返回当前战局并退出。")
		_navigate("battle")
		return false
	return true

func _battle() -> void:
	var state := match_controller.state
	if state.is_empty():
		var waiting := _panel(content)
		waiting.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_label(waiting, "等待对手进入战场", 35, GOLD)
		if match_controller.mode == "cloud":
			_label(waiting, "房间号  " + match_controller.cloud_room_code, 40, CREAM)
		_text(waiting, match_controller.status, 18, MUTED)
		_text(waiting, "对手加入后将自动校验双方卡牌与词条，然后开始对战。", 16, MUTED)
		_button(waiting, "取消并返回", func(): match_controller.leave_game(); _navigate("network"))
		return
	battle_view = BattleViewScript.new()
	battle_view.emote_service=emotes
	battle_view.emote_requested.connect(match_controller.send_emote)
	battle_view.state = state
	battle_view.me = match_controller.local_player
	battle_view.connected = match_controller.connected
	battle_view.solo = match_controller.mode == "solo"
	battle_view.spectating = match_controller.spectating
	battle_view.commander = str(store.account_identity.get("display_name",store.settings.get("player_name", "指挥官")))
	battle_view.selected_hand = selected_hand
	battle_view.selected_unit = selected_unit
	battle_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle_view.hand_clicked.connect(_hand_clicked)
	battle_view.action_requested.connect(_act)
	battle_view.cancel_requested.connect(func(): selected_hand = ""; selected_unit = -1; _render())
	battle_view.menu_requested.connect(_leave_match_dialog)
	battle_view.help_requested.connect(_battle_help)
	battle_view.history_requested.connect(_battle_history)
	battle_view.finish_requested.connect(func(): match_controller.leave_game(); _navigate("network"))
	content.add_child(battle_view)

func _battle_history() -> void:
	var panel := _modal("战场记录")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(650, 360)
	panel.add_child(scroll)
	var entries := _vbox(scroll, 10)
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in match_controller.state.get("log", []):
		_text(entries, str(entry), 15, MUTED)
func _hand_clicked(card: Dictionary) -> void:
	# Only a deployed card awaiting its effect target can latch this state.
	if not is_instance_valid(battle_view) or battle_view.pending_deployment.get("hand_id","")!=str(card.instance_id):return
	selected_unit = -1
	selected_hand = str(card.instance_id)
	_render()

func _selection_hint() -> String:
	if is_instance_valid(battle_view) and not battle_view.pending_deployment.is_empty(): return "选择高亮目标以完成部署效果。"
	return "按住卡牌拖动，松手出牌或行动。拖回原处或松在无效位置取消。"

func _act(action: Dictionary) -> void:
	if match_controller.spectating: return
	match_controller.submit_action(action)
	selected_hand = ""
	selected_unit = -1
	if page == "battle": _render()

func _battle_updated() -> void:
	selected_hand = ""
	selected_unit = -1
	if page in ["battle", "network"] and not match_controller.state.is_empty():
		page = "battle"
		_render()

func _match_status() -> void:
	_notify(match_controller.status)
	if page == "battle": _render()

func _leave_match_dialog() -> void:
	if match_controller.spectating:
		var watching:=_modal("观战菜单")
		_button(watching,"声音与动效",_audio_dialog)
		_button(watching,"退出观战",func(): match_controller.leave_game();_close_modal();_navigate("network"))
		return
	var panel := _modal("对局菜单")
	if match_controller.mode=="solo": _button(panel,"练习控制台 · F8",_open_practice_console)
	_button(panel, "声音与动效", _audio_dialog)
	_button(panel, "游戏规则", _battle_help)
	_text(panel, "退出将关闭当前连接。若要认输，请先发送投降行动。", 16, MUTED)
	_button(panel, "投降", func(): _act({"type":"concede"}); _close_modal())
	_button(panel, "离开并返回", func(): match_controller.leave_game(); _close_modal(); _navigate("network"))
	if match_controller.mode in ["client", "cloud"]:
		_button(panel, "尝试重新连接", func(): match_controller.reconnect_game(); _close_modal())

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F8 and page=="battle" and match_controller.mode=="solo":
		get_viewport().set_input_as_handled()
		_open_practice_console()

func _open_practice_console() -> void:
	if match_controller.mode!="solo" or match_controller.spectating: return
	if is_instance_valid(practice_console): return
	_close_modal()
	selected_hand="";selected_unit=-1
	var catalog: Array=[]
	for record in store.cards:
		var compiled:=store.compile_record(record)
		if compiled.get("ok",false):
			if record.get("art") is Dictionary: compiled["art_id"]=str(record.art.get("id",""))
			catalog.append(compiled)
	practice_console=preload("res://scripts/ui/practice_console.gd").new()
	practice_console.controller=match_controller
	practice_console.catalog=catalog
	if is_instance_valid(battle_view):
		battle_view.emote_hud.input_blocked=true
	practice_console.dismissed.connect(func():
		practice_console=null
		if is_instance_valid(battle_view): battle_view.emote_hud.input_blocked=false
		_render())
	add_child(practice_console)

func _battle_help() -> void:
	var panel := _modal("前线规则")
	_text(panel, "操作：按住卡牌拖动，松手出牌或行动。按住己方单位拖向敌军或总部进行攻击，拖向前线进行移动。拖回原处或松在无效位置取消，也可按右键或 Esc 取消。点击卡牌只查看信息；效果需要另选目标时，按提示完成选择。", 17)
	_text(panel, "双方总部 20 生命。每回合增加一个资源槽并补满资源，抽一张牌。\n\n单位部署在后援线，通常下回合才能行动。步兵和坦克可进入无敌军占据的前线。步兵推进后不能攻击，坦克可以。前线单位能攻击敌方后援与总部。\n\n炮兵与飞机可以远程攻击。炮兵不受反击，轰炸机仅遭飞机反击。守护仅保护同阵线左右紧邻的友方目标（包括总部）；炮兵、轰炸机和技能伤害不受守护限制。\n\n突击允许刚部署的单位行动。单位每回合最多移动一次，默认攻击一次，额外攻击次数以卡牌效果为准。每次移动和攻击分别支付当前行动费用。", 17)

func _settings() -> void:
	_heading("设置","")
	var row:=_hbox(content,24);row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var categories:=_vbox(row,6);categories.custom_minimum_size.x=148
	for entry in [["display","显示与场景","monitor"],["audio","声音与动效","volume-2"],["about","关于","book-open"]]:
		var button:=_button(categories,entry[1],func():settings_tab=entry[0];_render())
		button.set_meta("caption",entry[1]);ChaoUI.skin_button(button,false,entry[2]);ChaoUI.nav_button(button,settings_tab==entry[0],false)
	var scroll:=ScrollContainer.new();scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;row.add_child(scroll)
	var body:=_vbox(scroll,20);body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	match settings_tab:
		"display":
			var panel:=_panel(body);_label(panel,"战场场景",24)
			var options:=_hbox(panel,14)
			for entry in BattleSceneCatalog.entries():
				var tile:=_panel(options);tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
				_label(tile,str(entry.name),22);_label(tile,str(entry.get("subtitle","")),13,MUTED)
				var active:bool=entry.id==BattleSceneCatalog.selected()
				_button(tile,"使用中" if active else "选择场景",func():
					BattleSceneCatalog.choose(entry.id);menu_backdrop.refresh_scene();_render()
				,active)
			var graphics:=_panel(body);_label(graphics,"画质",24)
			var quality:=_option(graphics,["轻量 · 降低阴影和渲染开销","均衡 · 推荐","高 · 更平滑的边缘"],maxi(0,["low","balanced","high"].find(BattleSceneCatalog.quality)))
			quality.item_selected.connect(func(index):BattleSceneCatalog.choose(BattleSceneCatalog.selected(),["low","balanced","high"][index]);menu_backdrop.refresh_scene())
			_text(graphics,"场景和画质仅影响本机画面。",13,MUTED)
		"audio":
			var panel:=_panel(body);_label(panel,"声音与动效",24);_audio_controls(panel)
			var controls:=_panel(body);_label(controls,"表情",24);_button(controls,"配置轮盘",_emote_dialog)
		"about":
			var panel:=_panel(body);_label(panel,"巢战",42);_label(panel,ClientUpdate.current_version,18,GOLD)
			_text(panel,"卡库启动时自动更新，GitHub 连不上时会改用镜像。客户端新版本从 GitHub Releases 下载，安装包经过签名校验。",15,MUTED)
			_update_controls(panel)
			_button(panel,"版本发布页  ↗",func():OS.shell_open(ClientUpdate.RELEASES))
			_button(panel,"反馈问题  ↗",func():_open_issue("[报错] ","",""))
			if not mobile:_button(panel,"打开本地档案目录",func():OS.shell_open(ProjectSettings.globalize_path("user://")))
			_text(panel,"场景模型 · Kenney
材质与环境光 · Poly Haven
界面图标 · Lucide",14,MUTED)
			_button(panel,"资源来源与许可",func():
				var license_panel:=_modal("资源来源与许可")
				var license_text:=_editor(license_panel,FileAccess.get_file_as_string("res://assets/vendor/THIRD_PARTY.txt"),"",420)
				license_text.editable=false
			)

func _audio_dialog() -> void:
	_audio_controls(_modal("声音与动效"))

func _audio_controls(panel:VBoxContainer) -> void:
	for item in [["master","总音量"],["music","音乐"],["effects","音效"]]:
		var key: String = item[0]
		var row := _hbox(panel)
		var caption := _label(row,item[1],18)
		caption.custom_minimum_size.x = 85
		var slider := HSlider.new()
		slider.name = "Audio_"+key
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.value = roundf(float(audio_system.preferences[key])*100)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(280,48 if mobile else 34)
		row.add_child(slider)
		var value := _label(row,"%d%%" % slider.value,18,MUTED)
		value.custom_minimum_size.x = 60
		slider.value_changed.connect(func(amount):
			audio_system.set_preference(key,amount/100.0)
			value.text = "%d%%" % amount
		)
		slider.drag_ended.connect(func(changed):
			if changed and key == "effects": audio_system.sound("deploy")
		)
	for item in [["muted","静音"],["background_mute","切到后台时静音"],["animations","界面动效"]]:
		var key: String = item[0]
		var toggle := CheckButton.new()
		toggle.name = "Audio_"+key
		toggle.text = item[1]
		toggle.button_pressed = audio_system.preferences[key]
		toggle.custom_minimum_size.y = 48 if mobile else 32
		toggle.toggled.connect(func(value): audio_system.set_preference(key,value))
		panel.add_child(toggle)
	var credits := _hbox(panel)
	_spacer(credits)
	_button(credits,"音频来源",func():
		var info := _modal("音频来源")
		_text(info,"音效 · Kenney\n菜单音乐 · Spring Spring — War Theme\n战斗音乐 · Cethiel — Laments of the War\nCC0 1.0",17,MUTED)
	)

func _account_dialog(mode: String) -> void:
	var title := "登录账号" if mode == "login" else ("绑定账号" if mode == "link" else "注册账号")
	var panel := _modal(title)
	_label(panel, "账号", 16, MUTED)
	var username := _line(panel, "", "2～32 个字符")
	username.max_length = 32
	_label(panel, "密码", 16, MUTED)
	var password := _line(panel, "", "10～128 个字符")
	password.secret = true
	password.max_length = 128
	var confirmation: LineEdit
	if mode != "login":
		_label(panel, "确认密码", 16, MUTED)
		confirmation = _line(panel, "", "再次输入密码")
		confirmation.secret = true
		confirmation.max_length = 128
	_button(panel, title, func():
		if mode != "login" and password.text != confirmation.text:
			_notify("两次输入的密码不一致。")
			return
		var result := await store.account_login(username.text.strip_edges(), password.text) if mode == "login" else await store.account_register(username.text.strip_edges(), password.text, mode == "link")
		if not result.ok:
			_notify(result.error)
			return
		_close_modal()
		if store.account_identity.get("must_change_password", false): _password_dialog()
		else: _notify("已登录" if mode == "login" else "账号已绑定" if mode == "link" else "注册成功")
	, true)
	if mode == "login": _button(panel, "注册账号", func(): _account_dialog("register"))
	elif mode == "register": _button(panel, "返回登录", func(): _account_dialog("login"))

func _password_dialog() -> void:
	var panel := _modal("修改初始密码" if store.account_identity.get("must_change_password", false) else "修改密码")
	_label(panel, "当前密码", 16, MUTED)
	var current := _line(panel, "", "当前密码")
	current.secret = true
	current.max_length = 128
	_label(panel, "新密码", 16, MUTED)
	var password := _line(panel, "", "10～128 个字符")
	password.secret = true
	password.max_length = 128
	_label(panel, "确认新密码", 16, MUTED)
	var confirmation := _line(panel, "", "再次输入新密码")
	confirmation.secret = true
	confirmation.max_length = 128
	_button(panel, "保存密码", func():
		if password.text != confirmation.text:
			_notify("两次输入的新密码不一致。")
			return
		var result := await store.change_password(current.text, password.text)
		if result.ok:
			_close_modal()
			_notify("密码已更新")
		else: _notify(result.error)
	, true)

func _store_changed() -> void:
	if is_instance_valid(emotes) and emotes.bind_store(store) and not _boot_loading: emotes.refresh()
	if connection_badge != null:
		connection_badge.text = store.connection_note
	if page in ["home","library","settings","profile"]:
		_render()

func _notify(value: String) -> void:
	if is_instance_valid(battle_view):battle_view.show_notice(value)
	info_text=value
	if is_instance_valid(footer):footer.text=""
	if value.is_empty():return
	if is_instance_valid(toast):remove_child(toast);toast.queue_free()
	toast=PanelContainer.new();toast.mouse_filter=Control.MOUSE_FILTER_IGNORE;toast.z_index=600
	toast.add_theme_stylebox_override("panel",ChaoUI.style(Color("172b35f5"),Color("c6c6c655"),9,16));add_child(toast)
	var text:=_text(toast,value,14);text.custom_minimum_size.x=minf(480,size.x-80)
	var token:=toast
	await get_tree().process_frame
	if not is_instance_valid(token):return
	token.position=Vector2((size.x-token.size.x)/2,size.y-token.size.y-26)
	audio_system.fade_in(token)
	await get_tree().create_timer(4.5).timeout
	if is_instance_valid(token):
		var tween:=token.create_tween();tween.tween_property(token,"modulate:a",0.0,0.2);tween.tween_callback(token.queue_free)

func _open_import_dialog() -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.json ; 卡牌定义 JSON"])
	add_child(dialog)
	dialog.file_selected.connect(func(path):
		var source_file := FileAccess.open(path, FileAccess.READ)
		if source_file == null: _notify("无法读取文件。"); dialog.queue_free(); return
		if source_file.get_length() > 32768: _notify("导入文件不能超过 32 KiB。"); dialog.queue_free(); return
		_edit_json(source_file.get_as_text())
		dialog.queue_free()
		_render()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(850, 600))

func _export_card(record: Dictionary) -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.current_file = "card.card.json"
	dialog.filters = PackedStringArray(["*.json ; 卡牌定义 JSON"])
	add_child(dialog)
	dialog.file_selected.connect(func(path):
		var compiled := store.compile_record(record)
		if not compiled.get("ok", false):
			_notify("导出失败：" + str(compiled.get("error", "缺少词条依赖")))
			dialog.queue_free()
			return
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"package_version":"1","definition":record.definition,"definition_hash":compiled.definition_hash,"keyword_bindings":compiled.get("keyword_bindings",[])}, "\t"))
			_notify("卡牌已导出。")
		else: _notify("导出失败，请检查文件权限。")
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(850, 600))

func _show_json(title: String, value: Dictionary) -> void:
	var panel := _modal(title)
	var editor := _editor(panel, JSON.stringify(value, "\t"), "", 380)
	editor.editable = false
	_button(panel, "复制 JSON", func(): DisplayServer.clipboard_set(editor.text); _notify("已复制。"))

func _modal(title: String, fixed_size: Vector2 = Vector2.ZERO) -> VBoxContainer:
	_close_modal(false)
	overlay = Control.new()
	overlay.z_index=500
	if is_instance_valid(battle_view) and is_instance_valid(battle_view.emote_hud): battle_view.emote_hud.input_blocked=true
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var shade := ColorRect.new()
	shade.color=Color(0.015,0.025,0.04,0.80)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_margin = MarginContainer.new()
	modal_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(modal_margin)
	_update_screen_margins()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if fixed_size == Vector2.ZERO:
		var modal_scroll := ScrollContainer.new()
		modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		modal_margin.add_child(modal_scroll)
		modal_scroll.add_child(center)
	else:
		modal_margin.add_child(center)
	var panel := _panel(center)
	if fixed_size == Vector2.ZERO:
		panel.custom_minimum_size.x=minf(760,ScreenLayout.safe_rect(self).size.x-64)
	else:
		var frame: Control = panel.get_parent()
		var fit := func(): frame.custom_minimum_size = fixed_size.min(ScreenLayout.safe_rect(self).size - Vector2(24, 24))
		overlay.resized.connect(fit)
		center.resized.connect(fit)
		fit.call_deferred()
	var header := _hbox(panel)
	_label(header,title,25,CREAM)
	_spacer(header)
	var close:=_button(header,"",_close_modal);ChaoUI.skin_button(close,false,"x");close.tooltip_text="关闭"
	audio_system.sound("open")
	audio_system.fade_in(overlay)
	return panel

func _close_modal(play_sound: bool = true) -> void:
	if is_instance_valid(battle_view) and is_instance_valid(battle_view.emote_hud): battle_view.emote_hud.input_blocked=false
	if is_instance_valid(overlay):
		if play_sound: audio_system.sound("close")
		remove_child(overlay)
		overlay.queue_free()
	overlay = null
	modal_margin = null

func _heading(title: String, subtitle: String) -> void:
	var row := _hbox(content)
	_label(row,title,32)
	_spacer(row)
	if not subtitle.is_empty(): _label(row, subtitle, 12, GOLD)

func _label(parent: Control, value: String, font_size: int = 16, color: Color = CREAM) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", maxi(17, font_size) if mobile else font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _text(parent: Control, value: String, font_size: int = 16, color: Color = CREAM) -> Label:
	var label := _label(parent, value, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _vbox(parent: Node, separation: int = 12) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box

func _hbox(parent: Node, separation: int = 12) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box

func _button(parent: Control,value:String,callback:Callable,primary:bool=false) -> Button:
	var button:=Button.new();button.text=value
	ChaoUI.skin_button(button,primary)
	button.custom_minimum_size.y=48 if mobile else 42
	button.pressed.connect(callback);parent.add_child(button)
	return button

func _panel(parent: Control) -> VBoxContainer:
	var panel:=PanelContainer.new();panel.add_theme_stylebox_override("panel",ChaoUI.style(Color("111111cc"),Color("adadad26"),10,22));parent.add_child(panel)
	var box:=_vbox(panel,16)
	box.resized.connect(func():
		panel.size_flags_horizontal=box.size_flags_horizontal
		panel.size_flags_vertical=box.size_flags_vertical
		panel.size_flags_stretch_ratio=box.size_flags_stretch_ratio)
	return box

func _box(fill: Color, stroke: Color, radius: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = stroke
	style.set_border_width_all(0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

func _line(parent: Control, value: String, placeholder: String) -> LineEdit:
	var field := LineEdit.new()
	field.text = value
	field.placeholder_text = placeholder
	field.custom_minimum_size.y = 54 if mobile else 42
	parent.add_child(field)
	return field

func _editor(parent: Control, value: String, placeholder: String, height: float) -> TextEdit:
	var field := TextEdit.new()
	field.text = value
	field.placeholder_text = placeholder
	field.custom_minimum_size.y = height
	field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	parent.add_child(field)
	return field

func _option(parent: Control, options: Array, selected: int) -> OptionButton:
	var field := OptionButton.new()
	field.expand_icon=true
	field.custom_minimum_size.y = 52 if mobile else 40
	for option in options: field.add_item(str(option))
	field.select(selected)
	parent.add_child(field)
	return field

func _number_field(parent: Control, title: String, key: String, minimum: int, maximum: int) -> SpinBox:
	var column := _vbox(parent, 4)
	_label(column, title, 12, MUTED)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = int(manual[key])
	spin.custom_minimum_size.x = 104
	spin.value_changed.connect(func(value): _edit_manual(key, int(value)))
	column.add_child(spin)
	return spin

func _stat(parent: Control, number: String, caption: String) -> void:
	var box := _vbox(parent, 3)
	_label(box, number, 33, GOLD)
	_label(box, caption, 12, MUTED)

func _spacer(parent: Control, vertical: bool = false) -> void:
	var spacer := Control.new()
	if vertical: spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else: spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)

func _rules_info(parent: Control, definition: Dictionary) -> void:
	var label:=RichTextLabel.new()
	label.bbcode_enabled=true
	label.fit_content=true
	label.scroll_active=false
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size",15)
	label.add_theme_color_override("default_color",CREAM)
	label.text=CardRuntime.bold_rules_text(CardRuntime.detailed_rules_text(definition),definition)
	parent.add_child(label)


func _emote_dialog() -> void:
	if not match_controller.state.is_empty() and int(match_controller.state.get("winner",-1))==-1 and match_controller.mode!="menu": return
	var panel := _modal("表情轮盘",Vector2(850,620))
	var editor := preload("res://scripts/ui/emote_editor.gd").new()
	editor.service=emotes;panel.add_child(editor)
	editor.message.connect(_notify)

func _receive_emote(player: int, id: String, point: Vector2, display_scale: float) -> void:
	if not is_instance_valid(battle_view) or (player!=match_controller.local_player and emotes.mute_opponent): return
	var current := battle_view
	if emotes.entry(id).is_empty(): await emotes.refresh()
	if not is_instance_valid(current) or current!=battle_view: return
	if is_instance_valid(battle_view.emote_hud): battle_view.emote_hud.show_emote(player,id,point,display_scale)

func _startup_begin() -> void:
	_boot_loading=true;_boot_serial+=1;_boot_done.clear();_boot_ok=true
	if is_instance_valid(startup): remove_child(startup);startup.queue_free()
	startup=preload("res://scripts/ui/startup_loading.gd").new();add_child(startup)
	startup.continue_requested.connect(_startup_enter)
	startup.retry_requested.connect(_startup_begin)
	_startup_catalog(_boot_serial)
	_startup_updates(_boot_serial)

func _startup_catalog(serial: int) -> void:
	await store.refresh()
	if serial!=_boot_serial: return
	_startup_stage("cards",store.connection_note,store.bundled_ready)
	emotes.bind_store(store)
	var ok: bool=await emotes.refresh()
	if ok: ok=await emotes.preload_slots()
	if serial!=_boot_serial: return
	_startup_stage("emotes",("内置表情 · %d 个"%emotes.catalog.size()) if ok else "表情 · 使用本地配置",ok)

func _startup_updates(serial: int) -> void:
	await ClientUpdate.check()
	if serial!=_boot_serial: return
	# Being offline is not a startup failure; only a manifest with a bad signature is.
	var ok := not ClientUpdate.signature_failed
	_startup_stage("update",ClientUpdate.status if not ClientUpdate.status.is_empty() else "更新检查未完成",ok)

func _startup_stage(key: String, text: String, ok: bool) -> void:
	_boot_done[key]=true;_boot_ok=_boot_ok and ok
	if is_instance_valid(startup):
		startup.stage(key,text,ok)
		if _boot_done.size()==3: startup.finish(_boot_ok)

func _startup_enter() -> void:
	_boot_loading=false
	if is_instance_valid(startup): remove_child(startup);startup.queue_free()
	startup=null

func _veteran_details(record: Dictionary) -> void:
	var compiled: Dictionary=store.compile_record(record)
	if not compiled.get("ok",false): return
	var form: Dictionary=BattleEngine.new()._generated_card(compiled,record.definition.veteran.token_id)
	if form.is_empty(): return
	var panel:=_modal(str(form.definition.name)+" · 老兵")
	var row:=_hbox(panel,24)
	var face:=CardScript.new()
	face.spec=CardRuntime.display_definition(form)
	face.art_id=str(form.get("art_id",""))
	face.mouse_filter=Control.MOUSE_FILTER_IGNORE
	face.custom_minimum_size=CardScript.full_size(226)
	face.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	row.add_child(face)
	var info:=_vbox(row,15)
	info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_rules_info(info,face.spec)
	_button(info,"返回原形态",func(): _card_details(record))
