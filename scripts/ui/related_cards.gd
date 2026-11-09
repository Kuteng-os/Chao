extends PanelContainer
## Only accepts the frozen, already-visible parent; never queries an opponent deck.
const Face = preload("res://scripts/ui/card_face.gd")
signal closed
var parent_card: Dictionary = {}

static func entries(parent: Dictionary) -> Array:
	var result: Array = []
	if parent.is_empty() or not parent.has("source") or not parent.has("definition"): return result
	var engine := BattleEngine.new()
	for token in parent.definition.get("tokens",[]):
		if token.token_id == parent.get("generated_token_id", ""): continue
		var generated := engine._generated_card(parent,str(token.token_id))
		if generated.is_empty(): continue
		generated["derived_deck_building"] = token.get("deck_building","generated_only")
		generated["display_keywords"] = parent.get("display_keywords",CardRuntime.builtin_keywords()).duplicate(true)
		result.append(generated)
	return result

func _ready() -> void:
	set_meta("screen_space",true)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var style:=StyleBoxFlat.new();style.bg_color=Color("161616fa");style.set_corner_radius_all(12);style.set_content_margin_all(22)
	add_theme_stylebox_override("panel",style)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",14);add_child(box)
	var header:=HBoxContainer.new();box.add_child(header)
	var title:=Label.new();title.text="衍生卡 · "+str(parent_card.definition.get("name",""));title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.add_theme_font_size_override("font_size",23);header.add_child(title)
	var close:=Button.new();close.text="关闭";close.custom_minimum_size=Vector2(80,44);close.pressed.connect(func():closed.emit();queue_free());header.add_child(close)
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(scroll)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",20);scroll.add_child(row)
	for card in entries(parent_card):
		var column:=VBoxContainer.new();column.custom_minimum_size.x=266;row.add_child(column)
		var face:=Face.new();face.spec=CardRuntime.display_definition(card);face.art_id=str(card.get("art_id",""));face.custom_minimum_size=Face.full_size(266);face.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.add_child(face)
		var text:=RichTextLabel.new();text.bbcode_enabled=true;text.fit_content=true;text.scroll_active=false;text.custom_minimum_size.x=266;text.add_theme_font_size_override("normal_font_size",16);text.text=CardRuntime.bold_rules_text(CardRuntime.detailed_rules_text(face.spec),face.spec);column.add_child(text)
		var permit:=Label.new();permit.text="允许加入牌组" if card.get("derived_deck_building","generated_only") == "allowed" else "衍生卡 · 不可主动加入牌组";permit.add_theme_font_size_override("font_size",14);column.add_child(permit)
