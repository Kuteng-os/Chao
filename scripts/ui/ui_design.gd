class_name ChaoUI
extends RefCounted

const TEXT=Color("f1f1f1")
const MUTED=Color("a0a0a0")
const ACCENT=Color("cbcbcb")
const SURFACE=Color("161616eb")
const BORDER=Color("84848433")
static func icon(name:String)->Texture2D:
	var path:="res://assets/vendor/lucide/"+name+".svg"
	return load(path) if ResourceLoader.exists(path) else null
static func style(fill:Color=Color("232323cc"),border:Color=BORDER,radius:=8,padding:=10)->StyleBoxFlat:
	var s:=StyleBoxFlat.new();s.bg_color=fill;s.border_color=border;s.set_border_width_all(0);s.set_corner_radius_all(radius);s.set_content_margin_all(padding)
	return s
static func skin_button(b:Button,primary:=false,icon_name:="")->void:
	var fill:=ACCENT if primary else Color("32323280")
	b.add_theme_stylebox_override("normal",style(fill,Color.TRANSPARENT))
	b.add_theme_stylebox_override("hover",style(fill.lightened(0.12),Color("cecece66")))
	b.add_theme_stylebox_override("pressed",style(fill.darkened(0.15),ACCENT))
	b.add_theme_stylebox_override("focus",style(Color(ACCENT,0.12),Color.TRANSPARENT))
	b.add_theme_stylebox_override("disabled",style(Color("28282855"),Color.TRANSPARENT))
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:b.add_theme_color_override(state,Color("1f1f1f") if primary else TEXT)
	b.add_theme_color_override("font_disabled_color",Color("6e6e6e"))
	b.custom_minimum_size.y=maxf(b.custom_minimum_size.y,44)
	b.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	if not icon_name.is_empty():
		b.icon=icon(icon_name);b.expand_icon=true;b.add_theme_constant_override("icon_max_width",18);b.add_theme_constant_override("h_separation",9)
		if b.text.is_empty():b.custom_minimum_size.x=maxf(b.custom_minimum_size.x,44)
static func nav_button(b:Button,active:bool,compact:bool)->void:
	var box:=style(Color("bebebe14") if active else Color.TRANSPARENT,Color.TRANSPARENT,7,12)
	box.set_border_width_all(0)
	box.border_width_left=2 if active else 0;box.border_color=ACCENT
	b.add_theme_stylebox_override("normal",box)
	b.add_theme_stylebox_override("hover",style(Color("c9c9c910"),Color.TRANSPARENT,7,12))
	b.add_theme_stylebox_override("pressed",style(Color("c9c9c920"),Color.TRANSPARENT,7,12))
	b.add_theme_color_override("font_color",TEXT if active else MUTED)
	b.add_theme_color_override("icon_normal_color",ACCENT if active else MUTED)
	b.text="" if compact else str(b.get_meta("caption",""))
	b.alignment=HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT
	b.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size=Vector2(52 if compact else 156,48)
static func make_theme(mobile:bool)->Theme:
	var t:=Theme.new();var font:=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei UI","Noto Sans CJK SC","sans-serif"])
	# Cards are freely scaled and rotated; distance fields keep CJK glyphs crisp.
	font.multichannel_signed_distance_field=true; font.msdf_size=96
	t.default_font=font;t.default_font_size=18 if mobile else 15
	for cls in ["Label","Button","OptionButton","CheckButton","CheckBox","LineEdit","TextEdit"]:t.set_color("font_color",cls,TEXT)
	for cls in ["Button","OptionButton"]:
		t.set_constant("icon_max_width",cls,22)
		t.set_stylebox("normal",cls,style(Color("30303080"),Color.TRANSPARENT))
		t.set_stylebox("hover",cls,style(Color("3c3c3cdd"),Color("a3a3a34d")))
		t.set_stylebox("pressed",cls,style(Color("484848e0"),Color("b5b5b566")))
		t.set_stylebox("disabled",cls,style(Color("24242455"),Color.TRANSPARENT))
		t.set_stylebox("focus",cls,style(Color(ACCENT,0.12),Color.TRANSPARENT))
		t.set_color("font_hover_color",cls,TEXT);t.set_color("font_pressed_color",cls,TEXT);t.set_color("font_disabled_color",cls,Color("727272"))
	for cls in ["LineEdit","TextEdit"]:
		t.set_stylebox("normal",cls,style(Color("111111a6"),BORDER))
		t.set_stylebox("focus",cls,style(Color("1d1d1dd9"),Color(ACCENT,0.65)))
		t.set_color("font_placeholder_color",cls,Color("808080"));t.set_color("caret_color",cls,ACCENT);t.set_color("selection_color",cls,Color("6363635c"))
	t.set_stylebox("panel","PopupMenu",style(Color("202020fb"),Color("82828266"),9,10))
	t.set_stylebox("hover","PopupMenu",style(Color("6b6b6b66"),Color.TRANSPARENT,4,8))
	t.set_color("font_color","PopupMenu",TEXT);t.set_color("font_hover_color","PopupMenu",TEXT)
	t.set_icon("arrow","OptionButton",icon("chevron-down"));t.set_constant("arrow_margin","OptionButton",10)
	var transparent:=Image.create(1,1,false,Image.FORMAT_RGBA8);transparent.fill(Color.TRANSPARENT)
	var blank:=ImageTexture.create_from_image(transparent)
	for cls in ["VScrollBar","HScrollBar"]:
		var track:=style(Color("00000000"),Color.TRANSPARENT,3,2)
		var grab:=style(Color("91919166"),Color.TRANSPARENT,3,3)
		t.set_stylebox("scroll",cls,track)
		for state in ["grabber","grabber_highlight","grabber_pressed"]:t.set_stylebox(state,cls,grab)
		for state in ["increment","increment_highlight","increment_pressed","decrement","decrement_highlight","decrement_pressed"]:t.set_icon(state,cls,blank)
	t.set_stylebox("separator","HSeparator",style(Color("c4c4c422"),Color.TRANSPARENT,0,0))
	t.set_stylebox("background","ProgressBar",style(Color("8484841f"),Color.TRANSPARENT,2,0))
	t.set_stylebox("fill","ProgressBar",style(ACCENT,Color.TRANSPARENT,2,0))
	var track:=style(Color("353535"),Color.TRANSPARENT,3,3)
	t.set_stylebox("slider","HSlider",track)
	t.set_stylebox("grabber_area","HSlider",style(ACCENT,Color.TRANSPARENT,3,3));t.set_stylebox("grabber_area_highlight","HSlider",style(ACCENT.lightened(0.1),Color.TRANSPARENT,3,3))
	t.set_icon("grabber","HSlider",preload("res://assets/slider_knob.svg"));t.set_icon("grabber_highlight","HSlider",preload("res://assets/slider_knob.svg"))
	for key in ["VBoxContainer","HBoxContainer"]:t.set_constant("separation",key,12)
	t.set_constant("h_separation","GridContainer",18);t.set_constant("v_separation","GridContainer",20)
	return t
