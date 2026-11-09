extends VBoxContainer
const AVATARS := ["commander", "armor", "wings", "artillery", "navy", "recon"]
const AVATAR_NAMES := ["指挥官", "装甲", "航空", "炮兵", "海军", "侦察"]
const AVATAR_MARKS := ["★", "▰", "✦", "✚", "⚓", "◆"]
var ui: Control
var store: AppStore
var public_stats := false
var days := 30
var minimum_games := 1
var cursor := "0"
var body: VBoxContainer
var alive := true

func setup(shell: Control, app_store: AppStore, public: bool) -> void:
	ui = shell
	store = app_store
	public_stats = public
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_render()

func _exit_tree() -> void:
	alive = false

func _render() -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	var top: HBoxContainer = ui._hbox(self)
	ui._label(top, "战局分析" if public_stats else "个人档案", 32)
	ui._spacer(top)
	ui._button(top, "个人档案" if public_stats else "全服统计", func(): ui._navigate("profile" if public_stats else "statistics"))
	if not public_stats and not store.authenticated:
		var guest:VBoxContainer=ui._panel(self)
		guest.size_flags_vertical=Control.SIZE_EXPAND_FILL
		ui._spacer(guest,true)
		var mark:=TextureRect.new();mark.texture=ChaoUI.icon("user-round");mark.custom_minimum_size=Vector2(64,64);mark.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;mark.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;mark.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;guest.add_child(mark)
		var title:Label=ui._label(guest,"你的战斗档案",30);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var note:Label=ui._label(guest,"登录后查看个人战绩与对局记录",16,ChaoUI.MUTED);note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var actions:HBoxContainer=ui._hbox(guest);actions.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		ui._button(actions, "登录账号", func(): ui._account_dialog("login"), true)
		ui._button(actions, "注册账号", func(): ui._account_dialog("register"))
		ui._spacer(guest,true)
		return
	if not public_stats: _profile_header()
	var filters: HBoxContainer = ui._hbox(self)
	var period: OptionButton = ui._option(filters, ["近 7 天", "近 30 天", "近 90 天", "全部"], [7,30,90,0].find(days))
	period.item_selected.connect(func(index): days = [7,30,90,0][index]; _render())
	if public_stats:
		var samples: OptionButton = ui._option(filters, ["全部样本", "至少 10 局", "至少 30 局", "至少 100 局"], [1,10,30,100].find(minimum_games))
		samples.item_selected.connect(func(index): minimum_games = [1,10,30,100][index]; _render())
	ui._button(filters, "刷新", _render)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	body = ui._vbox(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui._label(body, "正在读取", 16, ui.MUTED)
	_load(body)

func _profile_header() -> void:
	var plate:VBoxContainer=ui._panel(self)
	var row: HBoxContainer = ui._hbox(plate, 20)
	var identity: Dictionary = store.account_identity
	var index := maxi(0, AVATARS.find(str(identity.get("avatar", "commander"))))
	var avatar:=PanelContainer.new();avatar.custom_minimum_size=Vector2(82,82);avatar.add_theme_stylebox_override("panel",ChaoUI.style(Color("3b3b3b"),Color.TRANSPARENT,22,12));row.add_child(avatar)
	var mark:Label=ui._label(avatar, AVATAR_MARKS[index], 40, Color(str(identity.get("avatar_color", "#c5a36b"))));mark.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;mark.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var description: VBoxContainer = ui._vbox(row, 3)
	ui._label(description, str(identity.get("display_name", store.settings.player_name)), 24)
	ui._label(description, "@" + str(identity.get("username", "")), 14, ui.MUTED)
	if not str(identity.get("bio", "")).is_empty(): ui._text(description, identity.bio, 14)
	ui._spacer(row)
	ui._button(row, "编辑资料", _edit_profile)
	ui._button(row, "修改密码", ui._password_dialog)

func _edit_profile() -> void:
	var panel: VBoxContainer = ui._modal("编辑资料")
	var identity: Dictionary = store.account_identity
	var nickname: LineEdit = ui._line(panel, str(identity.get("display_name", "")), "昵称")
	nickname.max_length = 32
	var avatar: OptionButton = ui._option(panel, AVATAR_NAMES, maxi(0, AVATARS.find(str(identity.get("avatar", "commander")))))
	var color := ColorPickerButton.new()
	color.color = Color(str(identity.get("avatar_color", "#c5a36b")))
	color.edit_alpha = false
	color.custom_minimum_size.y = 46
	panel.add_child(color)
	var bio: LineEdit = ui._line(panel, str(identity.get("bio", "")), "个人签名")
	bio.max_length = 160
	ui._button(panel, "保存", func():
		var result: Dictionary = await store.request("/v1/profile", HTTPClient.METHOD_PATCH, {"display_name":nickname.text,"avatar":AVATARS[avatar.selected],"avatar_color":"#" + color.color.to_html(false),"bio":bio.text})
		if not alive: return
		if not result.ok: ui._notify(result.error); return
		store.account_identity = result.data
		store.settings.player_name = result.data.display_name
		store.save_profile()
		ui._close_modal()
		_render()
	, true)

func _load(target: VBoxContainer) -> void:
	var endpoint := "/v1/public/statistics" if public_stats else "/v1/me/statistics"
	var result := await store.request(endpoint + "?days=%d&min_games=%d" % [days,minimum_games])
	if not alive or not is_instance_valid(target) or target != body: return
	for child in target.get_children(): target.remove_child(child); child.queue_free()
	if not result.ok: ui._text(target, result.error, 16, ui.GOLD); return
	var stats: Dictionary = result.data
	var counters:=GridContainer.new();counters.columns=4 if public_stats else 3;target.add_child(counters)
	_metric(counters, str(int(stats.matches)), "已结束对局")
	if not public_stats:
		_metric(counters, "%d / %d / %d" % [stats.wins,stats.losses,stats.draws], "胜 / 负 / 平")
		_metric(counters, _percent(stats.win_rate), "胜率")
	_metric(counters, _percent(stats.first_player_win_rate), "先手胜率")
	_metric(counters, str(stats.average_turns), "平均回合")
	_metric(counters, "%d:%02d" % [int(stats.average_duration_seconds) / 60, int(stats.average_duration_seconds) % 60], "平均时长")
	if not public_stats:
		ui._label(target, "对局历史", 22)
		await _history(target)
		if not alive or not is_instance_valid(target) or target != body: return
	ui._label(target, "卡牌表现", 22)
	var table_scroll:=ScrollContainer.new();table_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;target.add_child(table_scroll)
	var table:VBoxContainer=ui._vbox(table_scroll,4);table.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var headings: HBoxContainer = ui._hbox(table)
	var title: Label = ui._label(headings, "卡牌 / 版本", 14, ui.MUTED)
	title.custom_minimum_size.x = 270
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for name in ["样本", "携带胜率", "打出后胜率", "打出数", "伤害 / 次"]:
		var heading: Label = ui._label(headings, name, 14, ui.MUTED)
		heading.custom_minimum_size.x = 95
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if stats.cards.is_empty(): ui._label(target, "暂无符合条件的对局", 16, ui.MUTED)
	for card in stats.cards:
		var row: HBoxContainer = ui._hbox(table)
		var button: Button = ui._button(row, "%s · v%d" % [card.name,card.revision], func(): _card_stats(card))
		button.custom_minimum_size.x = 270
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for value in [str(int(card.games)), _percent(card.win_rate), _percent(card.played_win_rate), str(int(card.play)), "—" if card.damage_per_play == null else str(card.damage_per_play)]:
			var label: Label = ui._label(row, value, 16)
			label.custom_minimum_size.x = 95
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui._text(target, "仅统计服务器对战。打出后胜率受牌组、费用及对局时长影响。", 13, ui.MUTED)

func _metric(parent:Control,value:String,caption:String)->void:
	var tile:VBoxContainer=ui._panel(parent)
	tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	ui._label(tile,caption,13,ChaoUI.MUTED)
	ui._label(tile,value,30,ChaoUI.TEXT)

func _percent(value: Variant) -> String:
	return "—" if value == null else "%.1f%%" % float(value)

func _card_stats(card: Dictionary) -> void:
	var panel: VBoxContainer = ui._modal("%s · v%d" % [card.name,card.revision])
	ui._text(panel, "携带 %d 局 · 胜率 %s\n抽到后 %s（%d 局） · 打出后 %s（%d 局）\n起手 %s（%d 局）" % [card.games,_percent(card.win_rate),_percent(card.drawn_win_rate),card.drawn_games,_percent(card.played_win_rate),card.played_games,_percent(card.opening_win_rate),card.opening_games], 17)
	if card.win_rate_ci95 != null: ui._text(panel, "胜率 95%% 区间：%.1f%%～%.1f%%" % [card.win_rate_ci95[0],card.win_rate_ci95[1]], 14, ui.MUTED)
	ui._text(panel, "抽取 %d · 起手 %d · 打出 %d · 烧毁 %d\n总部伤害 %d · 单位伤害 %d · 过量伤害 %d\n击杀 %d · 阵亡 %d · 治疗 %d\n攻击 %d · 推进 %d · 衍生单位 %d\n部署消耗 %d · 行动消耗 %d · 恢复资源 %d\n触发 %d · 反制揭示 %d" % [card.draw,card.opening_draw,card.play,card.burn,card.hq_damage,card.unit_damage,card.overkill,card.kill,card.death,card.heal,card.attack,card.move,card.summon,card.deployment_spent,card.operation_spent,card.kredits_gained,card.trigger,card.counter_reveal], 17)

func _history(target: VBoxContainer) -> void:
	var result := await store.request("/v1/me/matches?cursor=" + cursor)
	if not alive or not is_instance_valid(target) or target != body: return
	if not result.ok: ui._text(target, result.error); return
	for item in result.data.matches:
		var row:HBoxContainer=ui._hbox(target)
		var outcome:Label=ui._label(row,str(item.result),16,ChaoUI.ACCENT);outcome.custom_minimum_size.x=62
		var name:Button=ui._button(row,str(item.opponent),func():_match_detail(item.match_id));name.size_flags_horizontal=Control.SIZE_EXPAND_FILL;name.alignment=HORIZONTAL_ALIGNMENT_LEFT
		ui._label(row,"%d 回合"%item.turns,14,ChaoUI.MUTED)
		ui._label(row,str(item.started_at).replace("T"," ").left(16),13,ChaoUI.MUTED)
	if result.data.matches.is_empty(): ui._label(target, "暂无对局记录", 16, ui.MUTED)
	var buttons: HBoxContainer = ui._hbox(target)
	if cursor != "0": ui._button(buttons, "上一页", func(): cursor = str(maxi(0,int(cursor)-20)); _render())
	if result.data.next_cursor != null: ui._button(buttons, "下一页", func(): cursor = result.data.next_cursor; _render())

func _match_detail(id: String) -> void:
	var result := await store.request("/v1/me/matches/" + id)
	if not alive: return
	if not result.ok: ui._notify(result.error); return
	var record: Dictionary = result.data
	var panel: VBoxContainer = ui._modal("对局详情")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(650,450)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var list: VBoxContainer = ui._vbox(scroll)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var reasons := {"HQ_DESTROYED":"总部被摧毁", "CONCEDE":"投降", "PLAYER_LEFT":"退出对局", "DISCONNECT_TIMEOUT":"掉线超时", "BOTH_OFFLINE":"双方离线", "IDLE_TIMEOUT":"长时间未操作", "SERVER_ERROR":"服务中断", "SERVER_RESTART":"服务重启"}
	ui._text(list, "%s  vs  %s\n%d 回合 · %d 秒 · %s" % [record.players[0].display_name,record.players[1].display_name,record.turns,record.get("duration_seconds",0),reasons.get(record.reason,"对局结束")], 18)
	for player in record.players:
		ui._label(list, player.display_name, 20, ui.GOLD)
		for card in player.cards:
			ui._text(list, "%d× %s v%d   抽到 %d / 打出 %d / 伤害 %d / 触发 %d" % [card.copies,card.name,card.revision,card.draw+card.opening_draw,card.play,card.hq_damage+card.unit_damage,card.trigger], 14)
	ui._label(list, "逐回合记录", 20, ui.GOLD)
	var names := {"opening_draw":"起手","draw":"抽牌","burn":"烧牌","play":"打出","deploy":"部署","summon":"召唤","attack":"攻击","move":"推进","damage":"伤害","heal":"治疗","death":"阵亡","kill":"击杀","destroy":"消灭","trigger":"触发","effect":"效果","counter_reveal":"揭示反制","turn_start":"回合开始","concede":"投降","fatigue":"疲劳"}
	for event in record.events:
		if not names.has(event.kind): continue
		var extra := ""
		if event.has("target_owner"):
			extra = " → " + str(record.players[int(event.target_owner)].display_name) + (" 总部" if event.get("hq",false) else " 单位")
		if event.kind == "damage" and int(event.get("attempted",0)) > int(event.amount): extra += "（过量 %d）" % (int(event.attempted) - int(event.amount))
		if event.kind == "effect":
			var operations := {"damage":"伤害", "heal":"治疗", "draw":"抽牌", "gain_kredits":"恢复资源", "summon":"召唤", "modify_stats":"调整属性", "grant_keyword":"赋予词条", "set_attack_limit":"调整攻击次数", "modify_operation_cost":"调整行动费", "set_combat_damage_multiplier":"战斗伤害倍率", "destroy":"消灭", "cancel_action":"取消行动"}
			extra = " · " + str(operations.get(event.get("op",""), ""))
		ui._text(list, "%d · %s · %s %s  %d%s" % [event.turn,record.players[int(event.owner)].display_name,str(event.get("name","")),names[event.kind],event.amount,extra], 13, ui.MUTED)
