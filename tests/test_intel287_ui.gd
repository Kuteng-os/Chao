extends SceneTree
var checks:=0
var failures:=0
var picked: Array=[]
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var overlay:=preload("res://scripts/ui/battle_choice.gd").new()
	root.add_child(overlay);overlay.size=Vector2(960,640)
	overlay.card_chosen.connect(func(index):picked.append(index))
	var choice={"kind":"intel","choice_id":"peek-1","options":[{"hidden":true,"hand_position":0},{"hidden":true,"hand_position":2}]}
	overlay.configure("选择一张敌方手牌查看",[],false);overlay.show_cards(choice,"wrath")
	await process_frame
	check(overlay.card_scroll.visible,"intel choice visible")
	check(overlay.card_row.get_child_count()==2,"only eligible slots rendered")
	for column in overlay.card_row.get_children():
		var back: Button=column.get_child(0)
		check(back.get_script()==preload("res://scripts/ui/battle_props.gd"),"unrevealed candidate uses card back, never a face")
		check(back.sin_id=="wrath","hidden back uses opponent deck sin")
		check(back.size.y>=354,"card backs have usable touch hit area")
	var column: Node=overlay.card_row.get_child(1)
	check(column.get_child(1).text=="查看第 3 张手牌","public numbering keeps gaps from already revealed cards")
	column.get_child(0).pressed.emit()
	check(picked==[1],"clicking card back sends option index")
	overlay.read_only=true;overlay.show_cards(choice,"wrath")
	check(overlay.card_row.get_child(0).get_child(0).disabled,"spectator cannot click backs")
	check(not overlay.card_row.get_child(0).get_child(1).visible,"spectator has no select button")
	overlay._select("peek-1",0);check(picked==[1],"spectator cannot send choice")
	overlay.read_only=false;overlay.show_cards({})
	overlay._select("peek-1",0);check(picked==[1],"closed old choice cannot send")
	check(not overlay.card_scroll.visible,"selection controls close after resolution")
	var fixtures: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/intel287.json"))
	var card:=CardRuntime.compile_card(fixtures.fixtures.chosen,[])
	for kind in ["discard","research","develop"]:
		overlay.show_cards({"kind":kind,"choice_id":kind,"options":[card]})
		var face: Button=overlay.card_row.get_child(0).get_child(0)
		check(face.get_script()==preload("res://scripts/ui/card_face.gd"),"existing "+kind+" renders a visible card face")
		check(face.spec.name=="窥探" and not face.disabled,"existing choice preserves name and input")
		face.pressed.emit();check(picked.back()==0,"existing choice still selects")
	overlay.show_cards({"kind":"effect","choice_id":"effect","options":[{"label":"抽牌","rules_text":"抽1张牌"}],"source_sin":"gloom"})
	var effect_face: Button=overlay.card_row.get_child(0).get_child(0)
	check(effect_face.choice_mode and effect_face.spec.name=="抽牌","effect choice keeps its source-faction card presentation")
	overlay.queue_free();await process_frame
	print("INTEL 287 UI: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
