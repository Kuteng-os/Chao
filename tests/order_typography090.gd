extends Control

func _ready() -> void:
	theme=ChaoUI.make_theme(false)
	get_viewport().warp_mouse(Vector2(3,3))
	var background:=ColorRect.new();background.color=Color("101a22");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var heading:=Label.new();heading.text="指令卡 · 排版样例";heading.position=Vector2(45,35);heading.add_theme_font_size_override("font_size",27);add_child(heading)
	var records:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/visual090_assets/records.json"))
	var samples:=[
		{"name":"战术集火","text":"　对所选敌方单位造成2点伤害。\n    抽1张牌。","sin":"wrath"},
		{"name":"最后的孵化","text":"弃置1张【集团军】单位手牌。\n　同名单位永久+2/+2，行动费-1。","sin":"gloom"},
		{"name":"跨越整个都市的紧急支援行动","text":"使一个友方单位获得闪击。\n  抽2张牌。","sin":"pride"},
		{"name":"Emergency Tactical Reinforcements","text":"  Draw 2 cards.\n\tGive a friendly unit +2 attack this turn.","sin":"envy"}
	]
	for i in samples.size():
		var face:=CardFace.new();face.spec={"kind":"order","name":samples[i].name,"cost":2,"sin":samples[i].sin,"rarity":"limited","keywords":[],"abilities":[]};face.subtitle=samples[i].text
		face.artwork=load("res://tests/visual090_assets/"+str(records[i].art.id)+".png");face.use_tooltip=false
		face.position=Vector2(45+i*345,110);face.size=CardFace.full_size(310);add_child(face)
		var title:Dictionary=face._order_title_layout();var rules:Dictionary=face.rules_layout()
		print("ORDER PREVIEW ",samples[i].name," title=",title.font_size," body=",rules.font_size," title_lines=",title.lines.size()," body_lines=",rules.lines)
		var hand:=CardFace.new();hand.spec=face.spec;hand.subtitle=face.subtitle;hand.artwork=face.artwork;hand.use_tooltip=false
		hand.position=Vector2(120+i*345,595);hand.size=CardFace.full_size(150);add_child(hand)
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../../order-typography090.png")
	get_tree().quit()
