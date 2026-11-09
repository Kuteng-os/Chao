extends Control
const Face = preload("res://scripts/ui/card_face.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# Use the same platform font fallback as the actual game, including Android.
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	theme = Theme.new()
	theme.default_font = font
	var background := ColorRect.new()
	background.color = Color("202d26")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var texts := ["闪击\n阵亡：友方单位重甲+1\n部署：自身重甲+1", "部署：对所选敌方单位造成2点伤害，然后抽1张牌。\n己方回合开始：使所有友方步兵攻击+1、防御+1。\n阵亡：在支援阵线召唤1个步兵。", "己方回合开始：对所有敌方单位造成1点伤害，然后抽1张牌。\n".repeat(10)]
	for index in texts.size():
		var face := Face.new()
		face.spec = {"name":["岩石大师","多效果指令","超长效果反制"][index],"kind":["unit","order","counter"][index],"unit_class":"tank" if index==0 else null,"cost":3,"operation_cost":1,"attack":3,"health":2,"rarity":["limited","special","elite"][index],"keywords":[],"abilities":[]}
		face.subtitle = texts[index]
		face.position = Vector2(34+index*430,65)
		face.size = Face.full_size(380)
		add_child(face)
		var layout: Dictionary = face.rules_layout()
		check(layout.rect.size.y==[101,72,78][index],"Unit and order title areas leave a bounded rules area")
		check(layout.art_bottom<=230 and layout.rect.position.y==[247,276,270][index],"Art, stats and rules keep separate areas")
		check(layout.font_size>=13 and layout.font_size<=18,"Readable font limits respected")
		check(layout.art_bottom>=190 and layout.art_bottom+20<layout.rect.position.y,"Art retains space and stats do not overlap rules")
		check(layout.rect.end.y<=348,"Rules remain within the paper border")
		check(face.rarity_rect().position.y>=Face.FULL_CARD_SIZE.y,"Rarity is below the entire card frame")
		check(face.rarity_rect().end.y<=Face.FULL_CARD_SIZE.y+Face.RARITY_FOOTER_HEIGHT,"Rarity stays inside its reserved footer without clipping")
		check(is_equal_approx(face._print_rect().size.x,380),"Reserving a rarity footer never shrinks the card width")
		for line in layout.lines:check(face.get_theme_default_font().get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,layout.font_size).x<=layout.rect.size.x,"Wrapped line fits card width")
		if index==0:check(not layout.overflow and layout.font_size>=14,"Reported Rock Master sample shows every effect at a legible size")
		if index==0:check(not layout.lines.any(func(line): return line.strip_edges() in ["1","+1","甲+1"]),"Automatic font fitting avoids a trailing stat on its own line")
		if index==2:check(layout.overflow and layout.font_size==13,"Extreme content stops shrinking at the minimum")
		check(not layout.lines.any(func(line): return line in ["。","，","！","？",".",","]),"Closing punctuation does not become an orphaned line")
		print("RULES SAMPLE: %s, font=%d, height=%d, lines=%d, overflow=%s"%[face.spec.kind,layout.font_size,layout.rect.size.y,layout.lines.size(),layout.overflow])
		var first_size: int = layout.font_size
		face.size=Face.full_size(202)
		check(face.rules_layout().font_size==first_size,"Collection and inspector preserve typography")
		face.size=Face.full_size(380)
		face.subtitle="闪击"
		check(face.rules_layout().font_size==(17 if index==1 else 18) and not face.rules_layout().overflow,"Editing text invalidates cached layout")
		face.subtitle=texts[index]
	# All hand and library faces use the same layout; no card name or ID has an exception.
	var generated := Face.new()
	generated.spec={"kind":"order","name":"衍生指令","cost":1,"keywords":[],"abilities":[{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":2}]}]}
	add_child(generated)
	generated.visible=false
	check(not generated.rules_layout().lines.is_empty() and not generated.rules_layout().overflow,"Generated order rules use automatic layout without subtitle overrides")
	generated.spec={"kind":"unit","name":"普通步兵","unit_class":"infantry","cost":1,"operation_cost":1,"attack":1,"health":1,"keywords":[],"abilities":[]}
	check(generated.rules_layout().lines.is_empty(),"A vanilla card does not print placeholder rules")
	generated.subtitle="闪击"
	check(generated.rules_layout().font_size==18 and generated.rules_layout().rect.size.y==101,"Short unit rules keep the largest font below the top title")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://card-rules-layout.png")
	print("CARD RULES LAYOUT: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
