extends Control
const Audio = preload("res://scripts/ui/frontline_audio.gd")
## Presentation only. Legality is read from the same deterministic engine used by the host.
const Face = preload("res://scripts/ui/card_face.gd")
const Prop = preload("res://scripts/ui/battle_props.gd")
const Table = preload("res://scripts/ui/battle_table.gd")
const ScreenLayout = preload("res://scripts/ui/screen_layout.gd")
const ChoiceOverlay = preload("res://scripts/ui/battle_choice.gd")
const Aim = preload("res://scripts/ui/battle_aim.gd")
const Presentation = preload("res://scripts/ui/battle_presentation.gd")
const HandLayout = preload("res://scripts/ui/battle_hand_layout.gd")
const FRONT := Rect2(210, 312, 1020, 238)
const SUPPORT := Rect2(210, 550, 1020, 230)
const FIELD_SCALE := 1.12
const ENEMY_SUPPORT_Y := 94.0
const FRONT_Y := 332.0
const OWN_SUPPORT_Y := 570.0
const HAND_PLAY_PULL := 100.0
const PAPER := Color("e2ebef")
const GOLD := Color("d2d2d2")
signal emote_requested(id: String, point: Vector2)
var emote_service: Node
var emote_hud: Control
signal hand_clicked(card: Dictionary)
signal action_requested(action: Dictionary)
signal cancel_requested
signal menu_requested
signal help_requested
signal history_requested
signal finish_requested
var state: Dictionary = {}
var me := 0
var selected_hand := ""
var selected_unit := -1
var connected := false
var solo := false
var spectating := false
var opening_overlay: Control
var commander := "指挥官"
var board: Control
var backdrop: Control
var layout_size := Vector2(1440, 900)
var last_safe := Rect2()
var inspector: Control
var inspector_panel: Control
var choice_overlay: Control
var aim: Control
var presentation: Control
var visual_faces: Dictionary = {}
var visual_props: Dictionary = {}
var used_props: Dictionary = {}
var drag_data: Dictionary = {}
var queued_snapshot: Dictionary = {}
var last_event_id := -1
var input_locked := false
var toast_label: Label
var rules: BattleEngine
var my_turn := false
var choosing := false
var targets: Array = []
var hover_token := 0
var inspector_source := 0
var inspector_pinned := false
var related_panel: Control
var target_rects: Dictionary = {}
var touch_mode := OS.has_feature("mobile") or OS.get_environment("FRONTLINE_MOBILE_TEST") == "1"
var result_sounded := false
var result_panel: PanelContainer
var reuse_faces: Dictionary = {}
var spare_hand_faces: Array = []
const HAND_FACE_POOL_LIMIT := 8
var legal_cache: Dictionary = {}
var move_cache: Dictionary = {}
var pending_deployment: Dictionary = {}
var hand_drag_face: CardFace
var hand_drag_source: CardFace
var hand_drag_offset := Vector2.ZERO
var hand_drag_start := Vector2.ZERO
var hand_drag_lift := 0.0
var hand_drag_tween: Tween
var hand_drag_accepted := false
var returning_hand_faces: Dictionary = {}
var submitted_drag: Dictionary = {}
var _overlay_signature: Array = []

func _ready() -> void:
	# Counters and effect prompts change with the hand too. Use the same
	# high-resolution glyph atlas throughout the battle, including the HUD.
	var battle_theme: Theme = theme.duplicate() if theme != null else Theme.new()
	battle_theme.default_font = preload("res://scripts/ui/card_typography.gd").card_font(get_theme_default_font())
	battle_theme.default_font_size = get_theme_default_font_size()
	theme = battle_theme
	clip_contents = true
	board = Control.new()
	board.size = Vector2(1440, 900)
	board.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(board)
	_forward_drop(board)
	resized.connect(_fit)
	_fit()
	rules = BattleEngine.new()
	_refresh_rules()
	_build()
	aim = Aim.new()
	board.add_child(aim)
	presentation = Presentation.new()
	board.add_child(presentation)
	presentation.size = layout_size
	presentation.finished.connect(_playback_finished)
	choice_overlay=ChoiceOverlay.new()
	board.add_child(choice_overlay)
	choice_overlay.canceled.connect(_cancel_effect_selection)
	choice_overlay.finished.connect(func():
		if choosing and state.has("pending_choice") and -1000 in targets: _emit_action({"type":"choose_target","choice_id":state.pending_choice.choice_id,"target_uid":-1000})
	)
	choice_overlay.card_chosen.connect(func(index):
		if choosing: _emit_action({"type":"choose_card","choice_id":state.pending_choice.choice_id,"option_index":index}))
	opening_overlay=preload("res://scripts/ui/opening_hand.gd").new();board.add_child(opening_overlay)
	opening_overlay.confirmed.connect(func(ids):_emit_action({"type":"mulligan","hand_ids":ids}))
	opening_overlay.menu_requested.connect(func():menu_requested.emit())
	if is_instance_valid(emote_service):
		emote_hud=preload("res://scripts/ui/battle_emotes.gd").new();emote_hud.service=emote_service;emote_hud.me=me;emote_hud.size=layout_size
		board.add_child(emote_hud)
		emote_hud.send_requested.connect(func(id,point): emote_requested.emit(id,point))
		emote_hud.opened.connect(_hide_inspector)
	_refresh_selection_overlay()
	for event in state.get("presentation_events",[]): last_event_id = maxi(last_event_id,int(event.id))

func _refresh_rules() -> void:
	_overlay_signature.clear()
	legal_cache.clear()
	move_cache.clear()
	rules.state = state
	targets = []
	my_turn = not spectating and not state.has("mulligan") and state.active_player == me and state.winner == -1 and connected and not state.get("suspended", false) and not state.has("pending_choice")
	choosing = not spectating and state.has("pending_choice") and state.pending_choice.owner == me and state.winner == -1 and connected and not state.get("suspended", false)
	if choosing: targets = state.pending_choice.targets.duplicate()
	if my_turn:
		if selected_unit >= 0: targets = rules.legal_targets(me, {"type":"attack", "uid":selected_unit})
		elif not selected_hand.is_empty(): targets = rules.legal_targets(me, {"type":"play", "hand_id":selected_hand})

func present_snapshot(next: Dictionary, online: bool, hand: String, unit: int) -> void:
	# A delayed network response must not rewind the board or replay old events.
	var newest := int(queued_snapshot.get("state",state).get("state_seq",0))
	if int(next.get("state_seq",0)) < newest: return
	if presentation.running:
		queued_snapshot = {"state":next.duplicate(true),"online":online,"hand":hand,"unit":unit}
		return
	var changed := int(next.get("state_seq",0)) != int(state.get("state_seq",0)) or next != state or connected != online
	connected = online
	selected_hand = hand
	selected_unit = unit
	if not pending_deployment.is_empty() and pending_deployment.hand_id != hand:
		pending_deployment.clear()
		if is_instance_valid(toast_label): toast_label.text = ""
	if not changed:
		_refresh_rules()
		for key in visual_faces:
			var face: Control = visual_faces[key]
			if face is CardFace:
				face.highlighted = key == "u:%d" % unit or key == "h:"+hand
				face.is_target = face.get_meta("target_uid",-999) in targets
				face.queue_redraw()
			elif face.kind=="hq":
				var owner:=int(str(key).trim_prefix("hq:"))
				face.set_meta("target_uid",-101-owner if -101-owner in targets else (-1 if owner!=me else -999))
				face.active = face.get_meta("target_uid",-999) in targets
				face.queue_redraw()
		_refresh_selection_overlay()
		return
	_hide_inspector()
	for face in visual_faces.values():
		if face is CardFace and face.touch_gate.touching: face.touch_gate.cancel(true)
	_cancel_drag()
	_clear_hand_drag()
	drag_data.clear()
	var old: Dictionary = {}
	var old_backs: Dictionary = {}
	var opening: bool = state.has("mulligan") or next.has("mulligan")
	for prop in visual_props.values():
		if prop.kind == "back": old_backs[prop.get_instance_id()] = {"position":prop.position,"rotation":prop.rotation}
	reuse_faces = visual_faces.duplicate()
	for key in visual_faces:
		var face: Control = visual_faces[key]
		_stop_hover(face)
		old[key] = {"position":face.position,"hp":face.current_health if face is CardFace else face.value,"name":str(face.spec.get("name","")) if face is CardFace else ""}
		old[key]["rotation"]=face.rotation
		old[key]["scale"]=face.scale
		if key=="h:"+str(submitted_drag.get("hand_id","")) and Time.get_ticks_msec()-int(submitted_drag.get("time",0))<4000:
			old[key]["position"]=submitted_drag.position
			old[key]["released"]=true
	submitted_drag.clear()
	for node in board.get_children():
		if node != aim and node != presentation and node != choice_overlay and node != opening_overlay and node != emote_hud and not node in reuse_faces.values() and not node in visual_props.values() and not node in spare_hand_faces:
			board.remove_child(node)
			node.queue_free()
	visual_faces.clear()
	target_rects.clear()
	var events: Array = []
	if int(next.get("state_seq",0)) < int(state.get("state_seq",0)): last_event_id = -1
	for event in next.get("presentation_events",[]):
		if int(event.id)>last_event_id: events.append(event)
		last_event_id = maxi(last_event_id,int(event.id))
	state = next.duplicate(true)
	_refresh_rules()
	input_locked = true
	_build()
	var removed: Array = []
	for key in reuse_faces:
		var face: Control = reuse_faces[key]
		if key.begins_with("u:"):
			face.mouse_filter = Control.MOUSE_FILTER_IGNORE
			face.set_meta("visual_key",key)
			removed.append(face)
		elif key.begins_with("h:") and spare_hand_faces.size() < HAND_FACE_POOL_LIMIT:
			_stop_hover(face)
			face.extended_hover = false
			face.hide()
			face.set_meta("screen_space",true)
			face.mouse_filter = Control.MOUSE_FILTER_IGNORE
			face.release_focus()
			spare_hand_faces.append(face)
		else:
			board.remove_child(face)
			face.queue_free()
	reuse_faces.clear()
	input_locked = true
	presentation.size = layout_size
	var pile: Control = visual_props["deck"]
	var draw_context := {"enabled":not opening,"sin":str(state.players[me].get("main_sin","")),"deck":Rect2(pile.position+Vector2(8,2),pile.size-Vector2(10,18)),"hidden":[]}
	var audio := Audio.service(self)
	if not opening and (audio == null or audio.preferences.animations):
		for prop in visual_props.values():
			if prop.kind != "back": continue
			var prior: Dictionary = old_backs.get(prop.get_instance_id(),{})
			draw_context.hidden.append({"node":prop,"fresh":prior.is_empty(),"start":prior.get("position",layout_size-draw_context.deck.get_center()-prop.size*0.5),"rotation":prior.get("rotation",0.22)})
	presentation.play(events,visual_faces,old,removed,me,draw_context)

func _playback_finished() -> void:
	input_locked = false
	if not queued_snapshot.is_empty():
		var next := queued_snapshot
		queued_snapshot = {}
		present_snapshot(next.state,next.online,next.hand,next.unit)
	# A queued duplicate may be a no-op render. Still finish the match after
	# draining it; only a newly started animation should postpone the result.
	if not presentation.running and state.winner != -1: _result()
	_refresh_selection_overlay()

func _emit_action(action: Dictionary) -> void:
	if spectating: return
	if state.has("mulligan") and action.type!="mulligan":return
	if input_locked: return
	if state.has("pending_choice") and action.type not in ["choose_target","choose_card"]: return
	if is_instance_valid(choice_overlay) and choice_overlay.visible and action.type not in ["play","choose_target","choose_card","prepare_play"]: return
	_hide_inspector()
	drag_data.clear()
	if action.type == "prepare_play":
		pending_deployment = action.duplicate()
		for entry in state.players[me].hand:
			if entry.instance_id == action.hand_id:
				hand_clicked.emit(entry)
				show_notice("选择高亮目标")
				return
		return
	if action.type == "play" and not pending_deployment.is_empty() and pending_deployment.hand_id == action.hand_id:
		action = action.duplicate()
		action["position"] = pending_deployment.position
	pending_deployment.clear()
	action_requested.emit(action)

func _process(_delta: float) -> void:
	if is_instance_valid(emote_hud):
		emote_hud.size=layout_size;emote_hud.enabled=not spectating and not state.has("mulligan") and connected and state.get("winner",-1)==-1 and not choosing and not input_locked
		var hq: Control=visual_faces.get("hq:%d"%me)
		if is_instance_valid(hq): emote_hud.hq_width=hq.size.x
	if is_instance_valid(hand_drag_face):
		hand_drag_face.position = board.get_local_mouse_position() - hand_drag_offset - Vector2(0,hand_drag_lift)
	_refresh_selection_overlay()
	if not is_instance_valid(aim): return
	aim.size=layout_size
	aim.active = false
	aim.legal_rects = []
	aim.region = Rect2()
	aim.insertion = Rect2()
	aim.hint = ""
	aim.queue_redraw()
	if input_locked: return
	# An arrow belongs to the held gesture, never a remembered click selection.
	var data:Dictionary = drag_data.duplicate() if get_viewport().gui_is_dragging() else {}
	var legal := targets
	if not data.is_empty():
		legal = _legal_for(data)
	for uid in legal:
		if uid == -1 and data.get("type")=="play": continue
		if target_rects.has(uid): aim.legal_rects.append(target_rects[uid])
	if data.is_empty(): aim.queue_redraw(); return
	var key := "u:%d" % int(data.uid) if data.type=="unit" else "h:"+str(data.hand_id)
	if not visual_faces.has(key): return
	var face: Control = visual_faces[key]
	aim.origin = face.card_top_in_parent() if face is CardFace else face.get_rect().get_center()
	if is_instance_valid(hand_drag_face) and data.type=="play": aim.origin = hand_drag_face.card_top_in_parent()
	aim.pointer = board.get_local_mouse_position()
	var action := _drop_action(get_local_mouse_position(),data)
	aim.active = data.type=="unit" or (data.type=="play" and not -1 in legal and (face.spec.kind!="unit" or action.has("target_uid")))
	aim.valid = not action.is_empty()
	aim.attack = data.type=="unit" and action.get("type", "attack")!="move"
	aim.destination = Rect2()
	if action.has("target_uid") and target_rects.has(action.target_uid): aim.destination = target_rects[action.target_uid]
	if action.has("position"):
		aim.insertion = _placement_marker("front" if action.type == "move" else "support",int(action.position))
	if not pending_deployment.is_empty():
		aim.insertion = _placement_marker("support",int(pending_deployment.position))
		aim.origin = Vector2(aim.insertion.get_center().x, aim.insertion.position.y)
	if data.type=="unit" and _can_move(int(data.uid)): aim.region = _combat_rect(FRONT)
	elif data.type=="play" and -1 in legal: aim.region = _combat_rect(SUPPORT if face.spec.kind=="unit" else Rect2(210,110,1020,649))
	if not drag_data.is_empty() and data.type=="play" and is_instance_valid(hand_drag_face):
		aim.hint="松开部署" if aim.valid and face.spec.kind=="unit" else "松开施放" if aim.valid else "继续向上拖动" if face.spec.kind!="unit" and hand_drag_start.y-aim.pointer.y<HAND_PLAY_PULL else "移至有效位置"
	aim.queue_redraw()

func _refresh_selection_overlay() -> void:
	if not is_instance_valid(choice_overlay):return
	var held_hand:String=str(drag_data.get("hand_id","")) if get_viewport().gui_is_dragging() else ""
	var signature: Array=[input_locked,connected,layout_size,selected_hand,held_hand,choosing,spectating]
	if signature==_overlay_signature:return
	_overlay_signature=signature
	if is_instance_valid(opening_overlay):
		opening_overlay.size=layout_size
		opening_overlay.show_hand(state,me,spectating,connected)
	if not is_instance_valid(choice_overlay): return
	for face in visual_faces.values():
		if face.has_meta("choice_z"):
			face.z_index=int(face.get_meta("choice_z"))
			face.remove_meta("choice_z")
	var text := ""
	var holes: Array = []
	var cancelable := false
	var effect_selection := false
	var choice_targets:Array=targets
	var source_uid := -1
	if not input_locked and connected and state.winner==-1 and not state.get("suspended",false):
		if state.has("pending_choice"):
			var choice: Dictionary=state.pending_choice
			source_uid=int(choice.source_uid)
			if spectating:
				text="%s 正在选择" % str(state.players[int(choice.owner)].get("commander_name","指挥官"))
			elif not choosing:
				text="等待对方选择效果目标"
			elif choice.get("kind","unit") != "unit":
				text = "「%s」：%s" % [choice.source_name,{"intel":"选择一张敌方卡背查看（按敌方手牌从左到右编号）","hand_cost":"选择一张手牌调整费用","search":"选择一张符合条件的卡牌","effect":"选择一项效果","discard":"选择一张手牌弃置","research":"选择研发成果或下一阶段","develop":"选择一张卡牌加入手牌"}.get(choice.kind,"选择一张卡牌")]
			else:
				var side: String="任意一方" if choice.get("side")=="any" else "友方" if choice.get("side")=="ally" else "敌方"
				var timing: String={"on_activate":"主动发动","on_play":"生效","on_summon":"被召唤","on_death":"阵亡","own_turn_start":"回合开始","own_turn_end":"回合结束"}.get(str(choice.trigger),"触发")
				var unit_type := CardRuntime.unit_class_text(choice.get("unit_classes",[]))
				text="部署「%s」：为%s效果选定一个%s%s"%[choice.source_name,timing,side,unit_type] if choice.get("selection_timing")=="deploy" else "「%s」%s：选择一个%s%s"%[choice.source_name,timing,side,unit_type]
			if choosing and choice.get("multi",false): text="「%s」：已选择 %d / %d 个单位，选择下一个或完成" % [choice.source_name,choice.selected_units.size(),choice.max]
		elif not held_hand.is_empty() or not pending_deployment.is_empty():
			var hand_id:String=held_hand if not held_hand.is_empty() else str(pending_deployment.hand_id)
			var entry: Dictionary=rules._hand(me,hand_id)
			choice_targets=_legal_for({"type":"play","hand_id":hand_id})
			if not entry.is_empty() and entry.card.definition.play_target!=null and not -1 in choice_targets and (entry.card.definition.kind!="unit" or not pending_deployment.is_empty()):
				text="「%s」：拖向%s，松手施放"%[entry.card.definition.name,CardRuntime._selector_text(entry.card.definition.play_target)] if not held_hand.is_empty() else "「%s」：选择一个%s"%[entry.card.definition.name,CardRuntime._selector_text(entry.card.definition.play_target)]
				effect_selection=true
				cancelable=held_hand.is_empty()
	if not text.is_empty():
		for face in visual_faces.values():
			var uid:=int(face.get_meta("effect_target_uid",face.get_meta("target_uid",-999)))
			if uid!=-999: target_rects[uid]=face.get_transform()*face.card_body_rect() if face is CardFace else face.get_rect()
			var legal: bool=uid in choice_targets and (choosing or effect_selection)
			if legal or (source_uid>0 and uid==source_uid):
				face.set_meta("choice_z",face.z_index)
				face.z_index=62
			if legal:
				var rect: Rect2=face.get_transform()*face.card_body_rect() if face is CardFace else face.get_rect()
				holes.append(rect)
	choice_overlay.size=layout_size
	choice_overlay.read_only=spectating
	choice_overlay.configure(text,holes,cancelable)
	choice_overlay.finish_button.visible=choosing and not input_locked and -1000 in targets
	var show_choice: bool=choosing or spectating and state.has("pending_choice") and int(state.pending_choice.owner)==me
	choice_overlay.show_cards(state.pending_choice if show_choice and not input_locked else {}, str(state.players[1-me].get("main_sin","")))
	if not text.is_empty() and choice_overlay.get_index()!=board.get_child_count()-1: board.move_child(choice_overlay,-1)
	if is_instance_valid(toast_label): toast_label.visible=text.is_empty()

func _cancel_effect_selection() -> void:
	if state.has("pending_choice"): return
	pending_deployment.clear()
	_hide_inspector()
	cancel_requested.emit()

func _fit() -> void:
	if not is_instance_valid(board) or size.x <= 0 or size.y <= 0: return
	var safe := ScreenLayout.safe_rect(self)
	var factor := minf(safe.size.x / 1440.0, safe.size.y / 900.0)
	var next_size := safe.size / maxf(factor, 0.001)
	var changed := not next_size.is_equal_approx(layout_size) or safe != last_safe
	layout_size = next_size
	last_safe = safe
	board.size = layout_size
	board.scale = Vector2.ONE * factor
	board.position = safe.position
	if changed:
		_hide_inspector()
		if is_instance_valid(presentation): presentation.finish()
		for node in board.get_children():
			if node is Control and node.has_meta("layout_rect"): _layout_node(node)
	if is_instance_valid(backdrop):
		backdrop.size = size
		var front := _combat_rect(FRONT)
		backdrop.field_rect = Rect2(board.position + front.position * factor, front.size * factor)
		backdrop.queue_redraw()

func _layout_rect(rect: Rect2, anchor: String) -> Rect2:
	var extra := layout_size - Vector2(1440,900)
	var offset := extra / 2.0
	match anchor:
		"top_left": offset = Vector2.ZERO
		"top_right": offset = Vector2(extra.x,0)
		"top": offset = Vector2(extra.x/2.0,0)
		"bottom_left": offset = Vector2(0,extra.y)
		"bottom_right": offset = extra
		"bottom": offset = Vector2(extra.x/2.0,extra.y)
		"left": offset.x = 0
		"right": offset.x = extra.x
	return Rect2(rect.position+offset,rect.size)

func _layout_node(node: Control) -> void:
	var rect := _layout_rect(node.get_meta("layout_rect"),node.get_meta("layout_anchor","center"))
	node.position = rect.position
	node.size = rect.size
	if node.has_meta("target_uid"): target_rects[node.get_meta("target_uid")] = node.get_transform()*node.card_body_rect() if node is CardFace else rect
	if node is CardFace and node.hand_mode:
		node.set_meta("rest_position",rect.position)
		node.extended_hover = false
		node.scale = Vector2.ONE
		if node.has_meta("rest_rotation"): node.rotation = node.get_meta("rest_rotation")
		if node.has_meta("rest_z"): node.z_index = node.get_meta("rest_z")

func _combat_rect(rect: Rect2) -> Rect2:
	var extra := layout_size - Vector2(1440,900)
	return Rect2(rect.position+Vector2(0,extra.y/2.0),rect.size+Vector2(extra.x,0))

func _build() -> void:
	_overlay_signature.clear()
	used_props.clear()
	if not is_instance_valid(backdrop):
		backdrop = Table.new()
		add_child(backdrop)
		move_child(backdrop,0)
	backdrop.size = size
	backdrop.bind_board(board)
	var active_field: Dictionary = state.get("field",{})
	var field_media: Dictionary = active_field.get("card",{}).get("definition",{}).get("media",{})
	backdrop.set_background(str(field_media.get("background","")))
	var audio:=Audio.service(self)
	if audio!=null: audio.set_field_music(str(field_media.get("music","")))
	if not active_field.is_empty():
		_small_button("△ " + str(active_field.card.definition.name),Rect2(45,350,180,55),func(): _inspect_field(active_field.card),"left")
	backdrop.front_owner = -1
	for unit in state.units:
		if unit.row == "front": backdrop.front_owner = 0 if unit.owner == me else 1; break
	_small_button("⚙", Rect2(1340, 29, 51, 43), func(): menu_requested.emit(),"top_right")
	_small_button("☰", Rect2(49, 152, 43, 37), func(): history_requested.emit(),"top_left")
	_credits(1 - me, Rect2(46, 36, 215, 108), str(state.players[1-me].get("commander_name","训练 AI" if solo else "对方指挥官")))
	_enemy_hand()
	_hq(1 - me, false)
	_hq(me, true)
	_counters(me, true)
	_counters(1 - me, false)
	_units("support", 1 - me, ENEMY_SUPPORT_Y)
	_units("front", -1, FRONT_Y)
	_units("support", me, OWN_SUPPORT_Y)
	var end := Prop.new()
	end.kind = "end"
	end.active = my_turn
	end.title = "结束回合" if my_turn else "对手回合"
	if spectating: end.title = "跟随方回合" if state.active_player==me else "对方回合"
	if state.has("pending_choice"): end.title = "选择目标" if choosing else "等待选择"
	if not connected or state.get("suspended", false): end.title = "连接暂停"
	if state.winner != -1: end.title = "战局结束"
	end.disabled = not my_turn
	end.pressed.connect(func(): _emit_action({"type":"end_turn"}))
	_place(end, Rect2(1215, 566, 180, 61),"right")
	var own: Dictionary = state.players[me]
	_credits(me, Rect2(46, 780, 215, 108), str(state.players[me].get("commander_name",commander)))
	var pile:Control = _take_prop("deck")
	pile.kind = "deck"
	pile.name = "DeckCounter"
	pile.sin_id = str(own.get("main_sin",""))
	pile.faction_id = str(own.get("main_faction_id",""))
	pile.value = int(own.get("deck_count", 0))
	pile.tooltip_text = "剩余 %d 张；牌库耗尽后，抽牌会使总部受到递增的疲劳伤害。" % pile.value
	_place(pile, Rect2(1232, 721, 95, 137),"bottom_right")
	pile.refresh_back()
	_hand()
	toast_label = _label("", Rect2(326, 80, 798, 28), 15, Color("e5d5a8"), HORIZONTAL_ALIGNMENT_CENTER,"top")
	toast_label.z_index = 20
	if spectating:
		toast_label.text = "观战 · " + str(state.players[me].get("commander_name","指挥官"))
		_small_button("退出观战",Rect2(1215,638,180,46),func(): finish_requested.emit(),"right")
	if state.has("pending_choice"):
		var timing: String = {"on_activate":"主动发动","on_play":"生效时","on_summon":"被召唤时","on_death":"阵亡","own_turn_start":"回合开始","own_turn_end":"回合结束"}.get(state.pending_choice.get("trigger"),"效果触发")
		toast_label.text = "%s · %s" % [state.pending_choice.source_name, timing + "：点击高亮单位选择目标" if choosing else "等待对方选择效果目标"]
	if not connected or state.get("suspended", false): toast_label.text = "连接中断，正在尝试恢复；战局已暂停。"
	if state.winner != -1 and not input_locked: _result()
	for key in visual_props.keys():
		if used_props.has(key):continue
		var stale:Control=visual_props[key]
		board.remove_child(stale);stale.queue_free();visual_props.erase(key)
	_fit()

func _take_prop(key:String)->Control:
	used_props[key]=true
	if not visual_props.has(key):visual_props[key]=Prop.new()
	return visual_props[key]

func _counters(owner: int, friendly: bool) -> void:
	if not friendly: return
	var player: Dictionary = state.players[owner]
	var counters: Array = player.get("counters", [])
	var count := counters.size() if friendly else int(player.get("counter_count", 0))
	for i in count:
		var chip := Button.new()
		chip.text = "反制 %d" % (i + 1)
		chip.add_theme_font_size_override("font_size", 13)
		if friendly:
			var definition: Dictionary = counters[i].card.definition
			chip.text = str(definition.name)
			chip.tooltip_text = CardRuntime.rules_text(definition)
		else:
			chip.tooltip_text = "对方已伏置反制"
		_place(chip, Rect2(46, (600 if friendly else 224) + i * 35, 140, 29),"left")

func _enemy_hand() -> void:
	var other: Dictionary = state.players[1 - me]
	var count := int(other.get("hand_count", 0))
	for i in count:
		var revealed: Array = other.get("revealed_hand",[]).filter(func(entry: Dictionary) -> bool: return int(entry.position)==i)
		if not revealed.is_empty():
			var known: Dictionary = revealed[0].card
			var face := _take_face("intel:%d:%s"%[i,known.definition_hash])
			face.set_meta("intel",true)
			face.set_meta("related_card",known)
			face.spec = CardRuntime.display_definition(known)
			face.art_id = str(known.get("art_id",""))
			face.use_tooltip = false
			face.custom_minimum_size = Vector2(108,156)
			face.drag_payload.clear()
			face.can_act = false
			var shift := i-(count-1)/2.0
			_place(face,Rect2(660+shift*54,-76+absf(shift)*4,108,156),"top")
			face.pivot_offset = Vector2(54,78)
			face.rotation = deg_to_rad(shift*-3.0)
			face.refresh_art()
			visual_faces["intel:%d:%s"%[i,known.definition_hash]] = face
			continue
		var back:Control = _take_prop("back:%d:%d"%[1-me,i])
		back.kind = "back"
		back.sin_id = str(other.get("main_sin",""))
		back.faction_id = str(other.get("main_faction_id",""))
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var offset := i - (count - 1) / 2.0
		_place(back, Rect2(660 + offset * 54, -83 + absf(offset) * 4, 108, 156),"top")
		back.pivot_offset = Vector2(54, 78)
		back.rotation = deg_to_rad(offset * -3.0)
		back.refresh_back()

func _credits(owner: int, rect: Rect2, player_name: String) -> void:
	var credits := Prop.new()
	credits.kind = "credits"
	credits.friendly = owner == me
	credits.value = int(state.players[owner].credits)
	credits.maximum = int(state.players[owner].max_credits)
	credits.title = player_name
	credits.tooltip_text = player_name
	credits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(credits, rect,"bottom_left" if owner==me else "top_left")

func _hq(owner: int, friendly: bool) -> void:
	var y := OWN_SUPPORT_Y if friendly else ENEMY_SUPPORT_Y
	var player: Dictionary = state.players[owner]
	var hq: Button = reuse_faces.get("hq:%d" % owner, null)
	var fresh := hq == null
	if fresh: hq = Prop.new()
	reuse_faces.erase("hq:%d" % owner)
	hq.kind = "hq"
	hq.friendly = friendly
	var compiled: Dictionary=player.get("headquarters",{})
	var spec: Dictionary=compiled.get("definition",{})
	hq.title = str(spec.get("name","总部"))
	hq.maximum=int(player.max_hp)
	hq.sin_id=SinCatalog.id_of(spec) if not spec.is_empty() else str(player.get("main_sin",""))
	hq.hq_art_id=str(compiled.get("art_id",""))
	if hq.hq_art_id.is_empty(): hq.hq_art_id=str(FactionCatalog.info(spec).get("background_id",""))
	hq.value = int(player.hp)
	var effect_target := -101-owner
	hq.active = effect_target in targets or (not friendly and -1 in targets and selected_unit >= 0)
	hq.tooltip_text = "%s  %d / %d\n%s" % [hq.title,int(player.hp),int(player.max_hp),"每回合抽1张牌" if spec.is_empty() else CardRuntime.rules_text(spec)]
	if fresh:
		hq.pressed.connect(func():
			if not hq.active:
				var card:Dictionary=state.players[owner].get("headquarters",{})
				if not card.is_empty(): _inspect_field(card)
				return
			if choosing: _emit_action({"type":"choose_target","choice_id":state.pending_choice.choice_id,"target_uid":-101-owner})
			elif not pending_deployment.is_empty(): _emit_action({"type":"play","hand_id":pending_deployment.hand_id,"target_uid":-101-owner})
		)
	hq.queue_redraw()
	hq.set_meta("target_uid",effect_target if effect_target in targets else (-1 if not friendly else -999))
	hq.set_meta("effect_target_uid",effect_target)
	var line := rules.line_order(owner,"support")
	var dimensions := Face.FIELD_BODY * FIELD_SCALE
	_place(hq, Rect2(Vector2(_formation_x(line.find(-1),line.size(),dimensions.x),y),dimensions))
	target_rects[effect_target]=hq.get_rect()
	visual_faces["hq:%d" % owner] = hq
	hq.update_headquarters_art()

func _units(row: String, owner: int, y: float) -> void:
	var units := rules.line_units(owner,row)
	var line := rules.line_order(owner,row)
	for i in units.size():
		var unit: Dictionary = units[i]
		var spec: Dictionary = CardRuntime.display_definition(unit.card)
		if not str(unit.get("token_id", "")).is_empty() and not unit.card.has("generated_origin"):
			for token in spec.get("tokens", []):
				if token.token_id == unit.token_id: spec = token.duplicate(true); spec["operation_cost"] = token.get("operation_cost", 1); break
		var key := "u:%d" % int(unit.uid)
		var face := _take_face(key)
		face.set_meta("unit",unit)
		face.set_meta("related_card",unit.card)
		spec.abilities = ([] if unit.get("suppressed",false) else unit.card.definition.get("abilities",[])) + unit.get("ability_layers",[]).duplicate(true)
		if spec.has("_printed"):
			spec._printed.abilities = ([] if unit.get("suppressed",false) else unit.card.get("source",unit.card.definition).get("abilities",[])) + unit.get("ability_layers",[]).duplicate(true)
			if unit.get("suppressed",false): spec._printed.keywords=[]
		face.spec = spec
		face.field_effects.clear()
		if spec.abilities.any(func(a):return a.trigger=="on_activate"):
			face.field_effects.append({"id":"active","mark":"主","label":"主动能力（长按或右键查看并发动）"})
		if unit.get("liberated",false): face.field_effects.append({"id":"liberated","mark":"解","label":"解放"})
		if unit.get("is_veteran",false): face.field_effects.append({"id":"veteran","mark":"★","label":"老兵"})
		face.drag_payload.clear()
		face.art_id = str(unit.card.get("art_id", "")) if str(unit.get("token_id", "")).is_empty() or unit.card.has("generated_origin") else str(unit.card.get("token_art_ids", {}).get(unit.token_id, ""))
		face.use_tooltip = false
		face.compact = true
		face.battle_drag = true
		face.enemy = int(unit.owner) != me
		face.current_attack = int(unit.attack)
		face.current_health = int(unit.hp)
		face.current_operation_cost = rules._operation_cost(unit)
		face.current_armor = rules.stack_count(unit, "heavy_armor")
		face.current_custom_stacks = unit.get("stacks",{}).duplicate(true)
		face.current_custom_stacks.erase("heavy_armor")
		if rules._has_keyword(unit,"core.guard"): face.field_effects.append({"id":"guard","mark":"◇","label":"守护" if rules.guard_active(unit) else "守护（烟幕期间失效）"})
		if rules._has_keyword(unit,"core.blitz"): face.field_effects.append({"id":"blitz","mark":"ϟ","label":"闪击"})
		for flag in [["ambush","伏", "伏击"],["fury","Ⅱ","奋战"],["smokescreen","烟","烟幕"],["shock","冲","冲击"],["mobilize","↑","动员"],["alpine","山","山地"],["salvage","缴","缴获"],["immune","免","免疫"]]:
			if rules._has_keyword(unit,"core."+flag[0]):
				var label: String = flag[2]
				if flag[0]=="smokescreen" and not rules.smokescreen_active(unit): label += "（前线不生效）"
				if flag[0]=="ambush" and int(unit.get("ambush_used_turn",-1))==int(state.turn): label += "（本回合已使用）"
				face.field_effects.append({"id":flag[0],"mark":flag[1],"label":label})
		if rules.revive_value(unit) > 0: face.field_effects.append({"id":"revive","mark":"生","label":"复生 %d" % rules.revive_value(unit)})
		if rules._pinned(unit): face.field_effects.append({"id":"pin","mark":"压","label":"已压制，不能主动攻击或移动，仍可反击"})
		if unit.get("suppressed",false): face.field_effects.append({"id":"suppress","mark":"抑","label":"已抑制，原生词条和能力失效"})
		if not unit.get("attack_limits",[]).is_empty(): face.field_effects.append({"id":"attacks","mark":str(rules.attack_limit(unit)),"label":"每回合攻击 %d 次" % rules.attack_limit(unit)})
		if not unit.get("combat_damage_rules",[]).is_empty(): face.field_effects.append({"id":"damage","mark":"×","label":"战斗伤害修正"})
		if not unit.get("modifiers",[]).is_empty(): face.field_effects.append({"id":"stats","mark":"+","label":"属性修正"})
		face.max_health = int(unit.max_hp)
		face.highlighted = int(unit.uid) == selected_unit
		face.can_act = my_turn and int(unit.owner) == me and (rules.can_move(int(unit.uid)) or not rules.legal_targets(me, {"type":"attack", "uid":int(unit.uid)}).is_empty())
		if face.can_act: face.drag_payload = {"type":"unit", "uid":int(unit.uid)}
		face.is_target = int(unit.uid) in targets
		var x := _formation_x(line.find(int(unit.uid)),line.size(),Face.FIELD_BODY.x*FIELD_SCALE)
		face.set_meta("target_uid",int(unit.uid))
		_place(face, Rect2(Vector2(x,y),Face.FIELD_SIZE*FIELD_SCALE))
		visual_faces["u:%d" % int(unit.uid)] = face
		face.refresh_art()
		face.queue_redraw()

func _hand() -> void:
	var hand: Array = state.players[me].hand
	for i in hand.size():
		var card: Dictionary = hand[i]
		var pose := HandLayout.pose(i,hand.size())
		var face := _take_face("h:"+str(card.instance_id))
		face.set_meta("card",card)
		face.drag_payload.clear()
		# Snapshots replace their dictionaries. Reuse unchanged printed content;
		# costs/playability still follow the current rules on every update.
		if face.spec.is_empty() or face.get_meta("printed_card",{}) != card.card:
			face.spec = CardRuntime.display_definition(card.card)
			face.set_meta("printed_card",card.card)
		face.spec["cost"] = rules.play_cost(me,card.card)
		face.set_meta("related_card",card.card)
		face.art_id = str(card.card.get("art_id", ""))
		face.use_tooltip = false
		face.hand_mode = true
		face.hand_hit_owner = _hand_hit_owner
		face.battle_drag = true
		face.highlighted = selected_hand == str(card.instance_id)
		face.can_act = my_turn and not _legal_for({"type":"play", "hand_id":str(card.instance_id)}).is_empty()
		if face.can_act: face.drag_payload = {"type":"play", "hand_id":str(card.instance_id)}
		_place(face, Rect2(pose.position, Face.full_size(220)),"bottom")
		visual_faces["h:"+str(card.instance_id)] = face
		face.pivot_offset = Vector2(110, Face.full_size(220).y)
		var tilt: float = pose.rotation
		face.rotation = tilt
		face.z_index = i + 1
		face.set_meta("rest_position", face.position)
		face.set_meta("rest_rotation", tilt)
		face.set_meta("rest_z", i + 1)
		face.refresh_art()
		face.queue_redraw()

func _hand_hit_owner(canvas_point: Vector2) -> Control:
	var faces: Array=[]
	for key in visual_faces:
		if str(key).begins_with("h:") and not visual_faces[key].get_meta("draw_hidden",false): faces.append(visual_faces[key])
	return preload("res://scripts/ui/hand_hit_test.gd").pick(faces,canvas_point)

func _take_face(key: String) -> CardFace:
	if reuse_faces.has(key):
		var face: CardFace = reuse_faces[key]
		reuse_faces.erase(key)
		return face
	if key.begins_with("h:") and not spare_hand_faces.is_empty():
		var face: CardFace = spare_hand_faces.pop_back()
		_stop_hover(face)
		face.remove_meta("screen_space")
		face.remove_meta("draw_hidden")
		face.remove_meta("drag_hidden")
		face.modulate = Color.WHITE
		face.mouse_filter = Control.MOUSE_FILTER_STOP
		face.show()
		return face
	var face := Face.new()
	face.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and drag_data.is_empty():
			if event.pressed: _inspect(face,true)
			face.accept_event()
	)
	face.pressed.connect(func():
		if is_instance_valid(face) and face.is_inside_tree(): _face_pressed(face)
	,CONNECT_DEFERRED)
	face.mouse_entered.connect(func():
		if touch_mode or input_locked or not drag_data.is_empty(): return
		if face.hand_mode: _hover_hand(face,true)
		_inspect(face)
	)
	face.mouse_exited.connect(func():
		if touch_mode: return
		if face.hand_mode:
			_hover_hand(face,false)
			if inspector_source==face.get_instance_id() and not inspector_pinned: _hide_inspector()
		else: _leave_inspector()
	)
	return face

func _face_pressed(face: CardFace) -> void:
	if input_locked or face.ignore_touch_click(): return
	if spectating:
		_inspect(face,true)
		return
	if is_instance_valid(choice_overlay) and choice_overlay.visible and not int(face.get_meta("target_uid",-999)) in targets: return
	if face.get_meta("intel",false):
		_inspect(face,true)
		return
	if face.hand_mode:
		_inspect(face,true)
		return
	var unit: Dictionary = face.get_meta("unit")
	if choosing and int(unit.uid) in targets:
		_emit_action({"type":"choose_target", "choice_id":state.pending_choice.choice_id, "target_uid":int(unit.uid)})
		return
	if not pending_deployment.is_empty() and int(unit.uid) in targets:
		_emit_action({"type":"play","hand_id":pending_deployment.hand_id,"target_uid":int(unit.uid)})
		return
	_inspect(face)

func _stop_hover(face: Control) -> void:
	if not face.has_meta("hover_tween"): return
	var tween: Tween = face.get_meta("hover_tween")
	if tween != null and tween.is_valid(): tween.kill()

func _hover_hand(face: CardFace, raised: bool) -> void:
	if face.extended_hover==raised:return
	_stop_hover(face)
	face.extended_hover = raised
	face.z_index = 40 if raised else int(face.get_meta("rest_z",1))
	var tween := face.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	face.set_meta("hover_tween",tween)
	var seconds := 0.12
	var audio := Audio.service(self)
	if audio != null and not audio.preferences.animations: seconds = 0.0
	tween.tween_property(face,"position",face.get_meta("rest_position")-Vector2(0,24 if raised else 0),seconds)
	tween.tween_property(face,"rotation",0.0 if raised else float(face.get_meta("rest_rotation")),seconds)
	tween.tween_property(face,"scale",Vector2.ONE*(1.04 if raised else 1.0),seconds)

func _legal_for(data: Dictionary) -> Array:
	var key := "u:%d" % int(data.get("uid",-1)) if data.get("type")=="unit" else "h:"+str(data.get("hand_id",""))
	if not legal_cache.has(key):
		legal_cache[key] = rules.legal_targets(me,{"type":"attack","uid":data.uid} if data.get("type")=="unit" else data)
	return legal_cache[key]

func _can_move(uid: int) -> bool:
	if not move_cache.has(uid): move_cache[uid] = rules.can_move(uid)
	return move_cache[uid]

func _input(event: InputEvent) -> void:
	if not drag_data.is_empty():
		var cancel_mouse:bool=event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT
		var cancel_key:bool=event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE
		var cancel_touch:bool=event is InputEventScreenTouch and event.canceled
		if cancel_mouse or cancel_key or cancel_touch:
			_cancel_drag()
			get_viewport().set_input_as_handled()
			return
	# Touch-generated mouse hover must not move the control beneath the finger.
	if not touch_mode and (event is InputEventScreenTouch or (event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION)):
		touch_mode = true
		_hide_inspector()
		for face in board.get_children():
			if face is CardFace and face.hand_mode:
				_stop_hover(face)
				face.position = face.get_meta("rest_position")
				face.rotation = face.get_meta("rest_rotation")
				face.z_index = face.get_meta("rest_z")
				face.scale = Vector2.ONE
				face.extended_hover = false

func _inspect(face: Button, pinned: bool = false) -> void:
	if is_instance_valid(related_panel) or inspector_pinned and not pinned: return
	if is_instance_valid(emote_hud) and is_instance_valid(emote_hud._wheel_overlay): return
	if is_instance_valid(choice_overlay) and choice_overlay.visible and not pinned: return
	if input_locked or not drag_data.is_empty(): return
	_hide_inspector()
	inspector_pinned = pinned or touch_mode
	inspector_source=face.get_instance_id()
	var ticket := hover_token
	await get_tree().create_timer(0.03 if touch_mode else 0.08).timeout
	if not is_inside_tree() or ticket != hover_token or not is_instance_valid(face) or input_locked or not drag_data.is_empty(): return
	inspector = Face.new()
	inspector.spec = face.spec
	inspector.art_id = face.art_id
	inspector.artwork = face.artwork
	inspector.current_attack = face.current_attack
	inspector.current_health = face.current_health
	inspector.current_operation_cost = face.current_operation_cost
	inspector.current_armor = face.current_armor
	inspector.max_health = face.max_health
	inspector.use_tooltip = false
	inspector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspector.z_index = 80
	inspector.set_meta("screen_space",true)
	var width := 380.0 if touch_mode else 344.0
	var height := Face.full_size(width).y
	var panel_width := 272.0
	var point: Vector2 = face.position+Vector2(face.size.x+20,0)
	if face.hand_mode: point = Vector2(clampf(face.position.x-70,20,layout_size.x-width-panel_width-44),layout_size.y-height-145)
	elif point.x+width+panel_width+24 > layout_size.x: point.x = face.position.x-width-panel_width-36
	point.x = clampf(point.x,20,layout_size.x-width-panel_width-44)
	point.y = clampf(point.y,88,layout_size.y-height-24)
	board.add_child(inspector)
	inspector.position = point
	inspector.size = Vector2(width,height)
	inspector_panel = PanelContainer.new()
	inspector_panel.z_index = 81
	var style := StyleBoxFlat.new()
	style.bg_color=Color("171717f5")
	style.set_corner_radius_all(12)
	style.border_color = Color("848484")
	style.set_border_width_all(0)
	style.set_content_margin_all(18)
	style.shadow_color = Color(0,0,0,0.5)
	style.shadow_size = 12
	inspector_panel.add_theme_stylebox_override("panel",style)
	board.add_child(inspector_panel)
	inspector_panel.position = point+Vector2(width+12,0)
	inspector_panel.size = Vector2(panel_width,height)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",16)
	inspector_panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "卡牌效果"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size",21)
	title.add_theme_color_override("font_color",GOLD)
	header.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(42,38)
	close.pressed.connect(_hide_inspector)
	header.add_child(close)
	var details := RichTextLabel.new()
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_theme_font_size_override("normal_font_size",21 if touch_mode else 19)
	details.add_theme_color_override("default_color",PAPER)
	details.bbcode_enabled = true
	var status: PackedStringArray = []
	for badge in face.effect_badges(): status.append(str(badge.label))
	var granted := _granted_keywords(face)
	var sections: Array = [{"title":"当前状态","body":"\n".join(status) if face.compact else ""}]
	var breakdown := _breakdown_text(face)
	# A quick look shows the card; resting on it (or pinning it) also explains every number that changed.
	details.text = CardRuntime.inspector_text(face.spec,granted,sections+([{"title":"数值变化","body":breakdown}] if inspector_pinned else []))
	box.add_child(details)
	if not inspector_pinned and not breakdown.is_empty():
		var hint := Label.new()
		hint.text = "停留片刻查看数值变化"
		hint.add_theme_font_size_override("font_size",14)
		hint.add_theme_color_override("font_color",Color("8d8d8d"))
		box.add_child(hint)
		_expand_inspector(ticket,details,hint,face.spec,granted,sections,breakdown)
	var unit: Dictionary=face.get_meta("unit",{})
	if not spectating and not unit.is_empty() and int(unit.owner)==me:
		for entry in state.get("unit_activations",{}).get(str(unit.uid),[]):
			var activate:=Button.new()
			activate.custom_minimum_size.y=46
			activate.text="发动能力 · 每回合一次" if str(entry.error).is_empty() else str(entry.error)
			activate.disabled=not str(entry.error).is_empty() or not inspector_pinned or input_locked or not my_turn
			if not inspector_pinned: activate.text="右键查看并发动能力"
			activate.pressed.connect(func():
				_hide_inspector()
				_emit_action({"type":"activate","uid":int(unit.uid),"ability_index":int(entry.ability_index)})
			)
			box.add_child(activate)
	var parent:Dictionary=face.get_meta("related_card",{})
	var related := preload("res://scripts/ui/related_cards.gd")
	if not related.entries(parent).is_empty():
		var button:=Button.new();button.text="查看衍生卡" if inspector_pinned else "右键查看衍生卡";button.custom_minimum_size.y=44;box.add_child(button)
		button.pressed.connect(func():_show_related_cards(parent))
	if face.hand_mode and not touch_mode and not inspector_pinned:
		close.visible=false
		_ignore_preview_mouse(inspector_panel)
	for node in [inspector,inspector_panel]:
		Audio.reveal(self,node)

const INSPECTOR_EXPAND_SECONDS := 0.6

func _expand_inspector(ticket: int, details: RichTextLabel, hint: Label, spec: Dictionary, granted: Array, sections: Array, breakdown: String) -> void:
	await get_tree().create_timer(INSPECTOR_EXPAND_SECONDS).timeout
	if ticket != hover_token or not is_instance_valid(details): return
	details.text = CardRuntime.inspector_text(spec,granted,sections+[{"title":"数值变化","body":breakdown}])
	if is_instance_valid(hint): hint.queue_free()

## Keywords a unit gained in battle, from grants and from auras, so the glossary explains them too.
func _granted_keywords(face: Button) -> Array:
	var unit: Dictionary = face.get_meta("unit",{})
	if unit.is_empty(): return []
	var ids: Array = []
	for layer in unit.get("grants",[]):
		if not str(layer.get("keyword_id","")) in ids: ids.append(str(layer.keyword_id))
	for effect in rules._field_effects(unit,true):
		if effect.op=="grant_keyword" and not str(effect.keyword_id) in ids: ids.append(str(effect.keyword_id))
	return ids.filter(func(id): return rules._has_keyword(unit,id))

func _breakdown_part(part: Dictionary) -> String:
	var value: String = ("设为 %d" % int(part.set)) if part.has("set") else ("%+d" % int(part.amount))
	return "%s %s%s" % [value,str(part.source).replace("[","[lb]"),("（%s）" % part.note) if not str(part.note).is_empty() else ""]

func _breakdown_line(label: String, data: Dictionary) -> String:
	if data.parts.is_empty(): return ""
	var pieces := PackedStringArray(["卡面 %d" % int(data.base)])
	for part in data.parts: pieces.append(_breakdown_part(part))
	return "[b]%s %d[/b]：%s" % [label,int(data.total),"，".join(pieces)]

## Plain-language reasons for every number on a board unit or a hand card that differs from what is printed.
func _breakdown_text(face: Button) -> String:
	var lines := PackedStringArray()
	var unit: Dictionary = face.get_meta("unit",{})
	var hand: Dictionary = face.get_meta("card",{})
	if not unit.is_empty() and not rules.state.is_empty():
		var data: Dictionary = rules.stat_breakdown(unit)
		for entry in [["攻击",data.attack],["防御上限",data.health],["行动费",data.operation_cost]]:
			var line := _breakdown_line(entry[0],entry[1])
			if not line.is_empty(): lines.append(line)
		if int(data.health.damage) > 0: lines.append("[b]当前防御 %d[/b]：受到 %d 点伤害" % [int(data.health.current),int(data.health.damage)])
	elif not hand.is_empty() and hand.get("card") is Dictionary and not rules.state.is_empty():
		var line := _breakdown_line("费用",rules.cost_breakdown(me,hand.card))
		if not line.is_empty(): lines.append(line)
	return "\n".join(lines)

func _ignore_preview_mouse(node: Node) -> void:
	if node is Control: node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_preview_mouse(child)

func _leave_inspector() -> void:
	if inspector_pinned: return
	var ticket := hover_token
	await get_tree().create_timer(0.18).timeout
	if not is_inside_tree() or ticket != hover_token: return
	if is_instance_valid(inspector_panel) and inspector_panel.get_global_rect().has_point(get_global_mouse_position()): return
	_hide_inspector()

func _hide_inspector() -> void:
	hover_token += 1
	inspector_pinned=false
	if is_instance_valid(related_panel):related_panel.queue_free()
	related_panel=null
	inspector_source=0
	if is_instance_valid(inspector):
		inspector.hide()
		inspector.queue_free()
	if is_instance_valid(inspector_panel):
		inspector_panel.hide()
		inspector_panel.queue_free()
	inspector = null
	inspector_panel = null

func _show_related_cards(parent: Dictionary) -> void:
	_hide_inspector()
	related_panel=preload("res://scripts/ui/related_cards.gd").new()
	related_panel.parent_card=parent
	related_panel.position=Vector2(50,80)
	related_panel.size=layout_size-Vector2(100,150)
	related_panel.z_index=110
	board.add_child(related_panel)

func _drop_action(at_position: Vector2, data: Variant) -> Dictionary:
	if input_locked or not my_turn or not data is Dictionary: return {}
	var point := (at_position - board.position) / board.scale
	var target := -999
	for seat in [0,1]:
		var hq: Control=visual_faces.get("hq:%d" % seat)
		var hq_target: int=-101-seat if data.get("type")=="play" else -1
		if is_instance_valid(hq) and hq.get_rect().has_point(point) and hq_target in _legal_for(data) and (data.get("type")=="play" or seat!=me): target=hq_target
	for uid in target_rects:
		if target == -999 and target_rects[uid].has_point(point): target = int(uid); break
	if data.get("type") == "unit":
		var uid := int(data.get("uid", -1))
		if target in _legal_for(data):
			return {"type":"attack", "uid":uid, "target_uid":target}
		if _combat_rect(FRONT).has_point(point) and _can_move(uid):
			return {"type":"move", "uid":uid, "position":_insertion_position("front",point.x)}
	elif data.get("type") == "play":
		var hand_id := str(data.get("hand_id", ""))
		var legal := _legal_for(data)
		for entry in state.players[me].hand:
			if str(entry.instance_id) != hand_id: continue
			if entry.card.definition.kind != "unit" and is_instance_valid(hand_drag_face) and hand_drag_start.y - point.y < HAND_PLAY_PULL:
				return {}
			if entry.card.definition.kind=="unit" and entry.card.definition.get("play_target") != null and pending_deployment.is_empty() and not -1 in legal and not legal.is_empty() and _combat_rect(SUPPORT).has_point(point):
				return {"type":"prepare_play","hand_id":hand_id,"position":_insertion_position("support",point.x)}
			if entry.card.definition.get("play_target") != null and target!=-1 and target in legal:
				var action := {"type":"play", "hand_id":hand_id, "target_uid":target}
				if entry.card.definition.kind=="unit": action["position"] = int(pending_deployment.position) if pending_deployment.get("hand_id")==hand_id else _insertion_position("support",point.x)
				return action
			if -1 in legal:
				var area := SUPPORT if entry.card.definition.kind == "unit" else Rect2(210, 110, 1020, 649)
				if _combat_rect(area).has_point(point):
					var action := {"type":"play", "hand_id":hand_id}
					if entry.card.definition.kind=="unit": action["position"] = _insertion_position("support",point.x)
					return action
	return {}

func _formation_x(index: int, count: int, width: float) -> float:
	return 706.0+(float(index)-(count-1)/2.0)*192.0-width/2.0

func _insertion_position(row: String, x: float) -> int:
	var line := rules.line_order(me,row)
	var offset := (layout_size.x-1440.0)/2.0
	for index in line.size():
		if x < _formation_x(index,line.size(),0)+offset: return index
	return line.size()

func _placement_marker(row: String, index: int) -> Rect2:
	var count := rules.line_order(me,row).size()
	var x := 706.0 if count==0 else _formation_x(index,count,0)-96.0
	return _layout_rect(Rect2(x-2,(OWN_SUPPORT_Y if row=="support" else FRONT_Y)+6,4,Face.FIELD_BODY.y*FIELD_SCALE-12),"center")

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return not _drop_action(at_position, data).is_empty()

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var action := _drop_action(at_position, data)
	if not action.is_empty():
		hand_drag_accepted = true
		if action.type=="play" and is_instance_valid(hand_drag_face):
			submitted_drag={"hand_id":action.hand_id,"position":hand_drag_face.position,"time":Time.get_ticks_msec()}
		var valid:Callable=data.get("_touch_valid",Callable())
		if valid.is_valid(): _finish_touch_drop.call_deferred(action,valid,int(state.get("state_seq",0)))
		else: _emit_action(action)

func _finish_touch_drop(action: Dictionary, valid: Callable, sequence: int) -> void:
	# Process the raw touch cancellation before committing its synthesized
	# mouse release. Only the plain resolved action reaches the authority.
	if not valid.call() or sequence!=int(state.get("state_seq",0)) or not connected or not my_turn:
		submitted_drag.clear()
		_clear_hand_drag()
		return
	_emit_action(action)

func show_notice(message: String) -> void:
	if toast_label != null:
		toast_label.text = message
		toast_label.add_theme_color_override("font_color", GOLD)
		await get_tree().create_timer(3.0).timeout
		if is_instance_valid(toast_label) and toast_label.text == message: toast_label.text = ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_hide_inspector()
			cancel_requested.emit()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_hide_inspector()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if state.has("pending_choice"): return
		if is_instance_valid(choice_overlay) and choice_overlay.visible: _cancel_effect_selection(); return
		if selected_unit >= 0 or not selected_hand.is_empty(): cancel_requested.emit()
		else: menu_requested.emit()

func _result() -> void:
	if is_instance_valid(result_panel) and result_panel.get_parent()==board: return
	_hide_inspector()
	var winner := int(state.winner)
	if not result_sounded:
		result_sounded = true
		if winner in [0,1] and not spectating: Audio.cue(self,"victory" if winner==me else "defeat")
	var message := "胜利" if winner == me else ("平局" if winner == 2 else ("对局中止" if winner == 3 else "失败"))
	if spectating and winner in [0,1]: message = str(state.players[winner].get("commander_name","指挥官")) + " 获胜"
	var panel := PanelContainer.new()
	result_panel=panel
	panel.z_index = 100
	var style := StyleBoxFlat.new()
	style.bg_color=Color("151515f5")
	style.set_corner_radius_all(18)
	style.set_content_margin_all(32)
	style.border_color = GOLD
	style.set_border_width_all(0)
	panel.add_theme_stylebox_override("panel", style)
	_place(panel,Rect2(440,270,560,340))
	Audio.reveal(self,panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 26)
	panel.add_child(box)
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32 if spectating else 48)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", GOLD)
	box.add_child(label)
	var sub:=Label.new();sub.text="第 %d 回合"%int(state.get("turn",1));sub.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;sub.add_theme_font_size_override("font_size",15);sub.add_theme_color_override("font_color",ChaoUI.MUTED);box.add_child(sub)
	var button := Button.new()
	button.text="退出观战" if spectating else "返回对战大厅"
	ChaoUI.skin_button(button,true)
	button.pressed.connect(func(): finish_requested.emit())
	button.custom_minimum_size.y = 44
	box.add_child(button)

func _place(node: Control, rect: Rect2, anchor := "center") -> void:
	var fresh := node.get_parent() == null
	if fresh: board.add_child(node)
	node.set_meta("layout_rect",rect)
	node.set_meta("layout_anchor",anchor)
	_layout_node(node)
	if fresh: _forward_drop(node)

func _forward_drop(node: Control) -> void:
	if node is CardFace:
		node.touch_gate.hold_required = false
		node.touch_gate.inspect_allowed = func(): return not input_locked and drag_data.is_empty()
		node.touch_gate.inspect_requested = func(): _inspect(node,true)
		node.drag_allowed = func(): return not input_locked and not choosing
		node.drag_started.connect(func(data):
			_stop_hover(node)
			drag_data = data
			_hide_inspector()
			if node.hand_mode: _start_hand_drag(node)
		)

	node.gui_input.connect(_control_input)
	node.set_drag_forwarding(
		func(point: Vector2): return _begin_drag(node,point),
		func(point: Vector2, data: Variant): return _can_drop_data(get_global_transform().affine_inverse() * (node.get_global_transform() * point), data),
		func(point: Vector2, data: Variant): _drop_data(get_global_transform().affine_inverse() * (node.get_global_transform() * point), data)
	)

func _control_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and (selected_unit >= 0 or not selected_hand.is_empty()):
		get_viewport().set_input_as_handled()
		cancel_requested.emit()

func _label(value: String, rect: Rect2, fs: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, anchor := "center") -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", fs)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = alignment
	_place(label, rect,anchor)
	return label

func _small_button(value: String, rect: Rect2, callback: Callable, anchor := "center") -> Button:
	var button := Button.new()
	button.text = value
	ChaoUI.skin_button(button)
	if value in ["⚙","☰"]:
		button.text="";ChaoUI.skin_button(button,false,"settings-2" if value=="⚙" else "book-open");button.tooltip_text="对局设置" if value=="⚙" else "对局记录"
	if value=="☰":button.add_theme_stylebox_override("normal",ChaoUI.style(Color.TRANSPARENT,Color.TRANSPARENT))
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(callback)
	_place(button, rect,anchor)
	return button

func _begin_drag(node: Control, point: Vector2) -> Variant:
	if input_locked or not node is CardFace: return null
	_stop_hover(node)
	var data: Variant = node._get_drag_data(point)
	if data is Dictionary:
		drag_data = data
		_hide_inspector()
	return data

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT and not touch_mode: _hide_inspector()
	if what == NOTIFICATION_DRAG_END:
		_finish_hand_drag()
		drag_data.clear()
		_clear_aim()
		_refresh_selection_overlay()
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:_cancel_drag()
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_EXIT_TREE]: _clear_hand_drag()

func _clear_aim() -> void:
	if not is_instance_valid(aim):return
	aim.active=false;aim.was_active=false;aim.legal_rects=[];aim.region=Rect2();aim.insertion=Rect2();aim.hint=""
	aim.queue_redraw()

func _cancel_drag() -> void:
	if drag_data.is_empty():return
	if get_viewport().gui_is_dragging():get_viewport().gui_cancel_drag()
	_finish_hand_drag()
	drag_data.clear()
	_clear_aim()
	_refresh_selection_overlay()

func _start_hand_drag(source: CardFace) -> void:
	_clear_hand_drag()
	hand_drag_source = source
	hand_drag_accepted = false
	hand_drag_offset = board.get_local_mouse_position() - source.position
	hand_drag_start = board.get_global_transform().affine_inverse() * source.drag_press_global
	hand_drag_lift = 0.0
	var face := Face.new()
	face.spec = source.spec
	face.art_id = source.art_id
	face.artwork = source.artwork
	face.faction_icon = source.faction_icon
	face.use_tooltip = false
	face.highlighted = true
	face.custom_minimum_size = source.size
	face.size = source.size
	face.position = source.position
	face.pivot_offset = source.pivot_offset
	face.rotation = source.rotation
	face.scale = source.scale
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.z_index = 75
	# Keep extraction and return in one canvas layer above the selection shade.
	# A raised 3D quad would still be underneath the entire UI canvas.
	face.set_meta("screen_space",true)
	board.add_child(face)
	face.pivot_offset = source.pivot_offset
	hand_drag_face = face
	source.self_modulate.a = 0.0
	source.set_meta("drag_hidden",true)
	hand_drag_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var audio := Audio.service(self)
	var seconds := 0.14 if audio == null or audio.preferences.animations else 0.0
	hand_drag_tween.tween_property(face,"rotation",0.0,seconds)
	hand_drag_tween.tween_property(face,"scale",Vector2.ONE,seconds)
	hand_drag_tween.tween_property(self,"hand_drag_lift",26.0,seconds)

func _finish_hand_drag() -> void:
	if not is_instance_valid(hand_drag_face): return
	if hand_drag_tween != null and hand_drag_tween.is_valid(): hand_drag_tween.kill()
	var face := hand_drag_face
	var source := hand_drag_source
	var accepted := hand_drag_accepted
	hand_drag_face = null
	hand_drag_source = null
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	returning_hand_faces[face] = {"source":source,"tween":tween}
	var audio := Audio.service(self)
	var seconds := (0.09 if accepted else 0.16) if audio == null or audio.preferences.animations else 0.0
	if accepted:
		tween.tween_property(face,"modulate:a",0.0,seconds)
	elif is_instance_valid(source):
		tween.tween_property(face,"position",source.get_meta("rest_position",source.position),seconds)
		tween.tween_property(face,"rotation",source.get_meta("rest_rotation",source.rotation),seconds)
	tween.chain().tween_callback(func():
		if is_instance_valid(source):
			source.self_modulate.a = 1.0
			source.remove_meta("drag_hidden")
			if source.hand_mode: _hover_hand(source,false)
		returning_hand_faces.erase(face)
		if is_instance_valid(face): face.queue_free()
	)

func _clear_hand_drag() -> void:
	if hand_drag_tween != null and hand_drag_tween.is_valid(): hand_drag_tween.kill()
	if is_instance_valid(hand_drag_source):
		hand_drag_source.self_modulate.a = 1.0
		hand_drag_source.remove_meta("drag_hidden")
	if is_instance_valid(hand_drag_face): hand_drag_face.queue_free()
	hand_drag_source = null
	hand_drag_face = null
	for face in returning_hand_faces:
		var entry: Dictionary = returning_hand_faces[face]
		if entry.tween.is_valid(): entry.tween.kill()
		if is_instance_valid(entry.source):
			entry.source.self_modulate.a = 1.0
			entry.source.remove_meta("drag_hidden")
		if is_instance_valid(face): face.queue_free()
	returning_hand_faces.clear()

func _inspect_field(card: Dictionary) -> void:
	Audio.card_cue(self,"select",card.definition.get("media",{}),"card")
	var face:=Face.new()
	face.spec=CardRuntime.display_definition(card)
	face.art_id=str(card.get("art_id",""))
	face.set_meta("related_card",card)
	board.add_child(face)
	face.visible=false
	face.position=Vector2(180,220)
	await _inspect(face,true)
	if is_instance_valid(face): face.queue_free()
