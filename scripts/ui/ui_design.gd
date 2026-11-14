class_name ChaoUI
extends RefCounted
## Visual language (0.11): an operations-terminal look. Square corners, thin rules, dark slabs on a pale terminal
## board, condensed Latin display type over CJK captions, and colour used sparingly — cyan for the main action,
## orange/yellow/red for small markers.

const TEXT=Color("f1f1f1")
const MUTED=Color("a0a4aa")
const ACCENT=Color("16a4e6")
const SURFACE=Color("16181ce8")
const BORDER=Color("ffffff22")
## Dark ink for text set directly on the pale board of secondary pages.
const INK=Color("16171a")
const INK_MUTED=Color("55585e")
const SLAB=Color("1d1f23f0")
const SLAB_LIGHT=Color("e9e9e7")
const CYAN=Color("16a4e6")
const CYAN_DARK=Color("0b7fb8")
const ORANGE=Color("ff7a1a")
const YELLOW=Color("ffd21f")
const RED=Color("c8202f")

static var _display: Font
static var _display_light: Font

static func icon(name:String)->Texture2D:
	var path:="res://assets/vendor/lucide/"+name+".svg"
	return load(path) if ResourceLoader.exists(path) else null

## Square slabs everywhere; radius stays as a parameter so older callers keep working, but corners are drawn sharp.
static func style(fill:Color=Color("26292ecc"),border:Color=BORDER,radius:=0,padding:=10)->StyleBoxFlat:
	var s:=StyleBoxFlat.new();s.bg_color=fill;s.border_color=border;s.set_border_width_all(0);s.set_corner_radius_all(0);s.set_content_margin_all(padding)
	s.anti_aliasing=false
	return s

## A slab with a thin rule along one edge, the panel shape used across the terminal UI.
static func slab(fill:Color=SLAB,rule:Color=Color("ffffff40"),padding:=18,rule_side:="top")->StyleBoxFlat:
	var s:=style(fill,rule,0,padding)
	match rule_side:
		"top": s.border_width_top=2
		"left": s.border_width_left=3
		"bottom": s.border_width_bottom=3
	return s

## Condensed display face for Latin titles and big numbers; CJK falls back to the default UI font.
static func display_font(bold:=true)->Font:
	if bold and _display!=null: return _display
	if not bold and _display_light!=null: return _display_light
	var font:=SystemFont.new()
	font.font_names=PackedStringArray(["Bahnschrift","DIN Condensed","Roboto Condensed","sans-serif-condensed","Arial Narrow"])
	font.font_stretch=75
	font.font_weight=700 if bold else 500
	# No distance fields here: Bahnschrift's variable outlines overlap and MSDF leaves specks inside letters.
	font.oversampling=2.0
	var cjk:=SystemFont.new();cjk.font_names=PackedStringArray(["Microsoft YaHei UI","Noto Sans CJK SC","sans-serif"]);cjk.font_weight=700 if bold else 400
	font.fallbacks=[cjk]
	if bold: _display=font
	else: _display_light=font
	return font

static var _display_italic: Font
## The display face leaned forward (the face has no italic of its own).
static func display_italic()->Font:
	if _display_italic!=null: return _display_italic
	var lean:=FontVariation.new();lean.base_font=display_font()
	lean.variation_transform=Transform2D(Vector2(1,0.2),Vector2(0,1),Vector2.ZERO)
	_display_italic=lean
	return lean

## A label in the display face, e.g. an English page title or a large count.
static func display(label:Label,size:int,colour:Color=TEXT,bold:=true)->Label:
	label.add_theme_font_override("font",display_font(bold))
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",colour)
	return label

## Small solid tag such as NOTICE / FILTER / CURRENT DECK.
static func tag(text:String,fill:Color=RED,ink:Color=TEXT)->Label:
	var label:=Label.new();label.text=text
	display(label,12,ink)
	var box:=style(fill,Color.TRANSPARENT,0,0);box.content_margin_left=7;box.content_margin_right=7;box.content_margin_top=1;box.content_margin_bottom=1
	label.add_theme_stylebox_override("normal",box)
	label.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	return label

static func skin_button(b:Button,primary:=false,icon_name:="")->void:
	var fill:=CYAN if primary else Color("26292ee6")
	var normal:=style(fill,Color.TRANSPARENT,0,12)
	if not primary: normal.border_width_left=0
	b.add_theme_stylebox_override("normal",normal)
	var hover:=style(fill.lightened(0.10),Color("ffffff55"),0,12);hover.border_width_bottom=2
	b.add_theme_stylebox_override("hover",hover)
	b.add_theme_stylebox_override("pressed",style(fill.darkened(0.18),CYAN,0,12))
	b.add_theme_stylebox_override("focus",style(Color.TRANSPARENT,Color(CYAN,0.7),0,12))
	b.get_theme_stylebox("focus").set("border_width_bottom",2)
	b.add_theme_stylebox_override("disabled",style(Color("2a2c3066"),Color.TRANSPARENT,0,12))
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:b.add_theme_color_override(state,TEXT)
	for state in ["icon_normal_color","icon_hover_color","icon_pressed_color","icon_focus_color"]:b.add_theme_color_override(state,TEXT)
	b.add_theme_color_override("font_disabled_color",Color("7a7d82"))
	b.custom_minimum_size.y=maxf(b.custom_minimum_size.y,44)
	b.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	if primary: b.add_theme_font_override("font",display_font());b.add_theme_font_size_override("font_size",18)
	if not icon_name.is_empty():
		b.icon=icon(icon_name);b.expand_icon=true;b.add_theme_constant_override("icon_max_width",18);b.add_theme_constant_override("h_separation",9)
		if b.text.is_empty():b.custom_minimum_size.x=maxf(b.custom_minimum_size.x,44)

## A light button (white slab, dark ink) for secondary choices on dark backgrounds.
static func skin_light_button(b:Button)->void:
	skin_button(b,false)
	b.add_theme_stylebox_override("normal",style(SLAB_LIGHT,Color.TRANSPARENT,0,12))
	var hover:=style(Color.WHITE,CYAN,0,12);hover.border_width_bottom=2
	b.add_theme_stylebox_override("hover",hover)
	b.add_theme_stylebox_override("pressed",style(Color("cfcfcc"),CYAN,0,12))
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color","icon_normal_color","icon_hover_color","icon_pressed_color","icon_focus_color"]:b.add_theme_color_override(state,INK)

## Bottom tab of secondary pages: icon over caption; the active one gets a marker triangle (drawn by main).
static func nav_button(b:Button,active:bool,compact:bool)->void:
	var empty:=StyleBoxEmpty.new();empty.content_margin_top=16;empty.content_margin_bottom=4
	for state in ["normal","hover","pressed","focus"]:b.add_theme_stylebox_override(state,empty)
	b.add_theme_color_override("font_color",INK if active else INK_MUTED)
	b.add_theme_color_override("font_hover_color",INK)
	b.add_theme_color_override("font_pressed_color",INK)
	b.add_theme_color_override("icon_normal_color",INK if active else INK_MUTED)
	b.add_theme_color_override("icon_hover_color",INK)
	b.add_theme_color_override("icon_pressed_color",INK)
	b.add_theme_font_size_override("font_size",13)
	b.text="" if compact else str(b.get_meta("caption",""))
	b.alignment=HORIZONTAL_ALIGNMENT_CENTER
	b.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP
	b.custom_minimum_size=Vector2(72 if compact else 116,70)
	b.set_meta("active",active)

static func make_theme(mobile:bool)->Theme:
	var t:=Theme.new();var font:=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei UI","Noto Sans CJK SC","sans-serif"])
	# Cards are freely scaled and rotated; distance fields keep CJK glyphs crisp.
	font.multichannel_signed_distance_field=true; font.msdf_size=96
	t.default_font=font;t.default_font_size=18 if mobile else 15
	for cls in ["Label","Button","OptionButton","CheckButton","CheckBox","LineEdit","TextEdit"]:t.set_color("font_color",cls,TEXT)
	for cls in ["Button","OptionButton"]:
		t.set_constant("icon_max_width",cls,22)
		t.set_stylebox("normal",cls,style(Color("26292ee6"),Color.TRANSPARENT,0,12))
		var hover:=style(Color("33373deb"),Color("ffffff55"),0,12);hover.border_width_bottom=2
		t.set_stylebox("hover",cls,hover)
		t.set_stylebox("pressed",cls,style(Color("1a1c20f0"),CYAN,0,12))
		t.set_stylebox("disabled",cls,style(Color("2a2c3066"),Color.TRANSPARENT,0,12))
		t.set_stylebox("focus",cls,style(Color.TRANSPARENT,Color(CYAN,0.6),0,12))
		t.set_color("font_hover_color",cls,TEXT);t.set_color("font_pressed_color",cls,TEXT);t.set_color("font_disabled_color",cls,Color("7a7d82"))
	for cls in ["LineEdit","TextEdit"]:
		var normal:=style(Color("1b1d21eb"),Color("ffffff2a"),0,10);normal.border_width_bottom=1
		t.set_stylebox("normal",cls,normal)
		var focus:=style(Color("202328f2"),CYAN,0,10);focus.border_width_bottom=2
		t.set_stylebox("focus",cls,focus)
		t.set_color("font_placeholder_color",cls,Color("80848a"));t.set_color("caret_color",cls,CYAN);t.set_color("selection_color",cls,Color(CYAN,0.35))
	t.set_stylebox("panel","PopupMenu",slab(Color("1d1f23fb"),CYAN,6))
	t.set_stylebox("hover","PopupMenu",style(Color(CYAN,0.85),Color.TRANSPARENT,0,8))
	t.set_color("font_color","PopupMenu",TEXT);t.set_color("font_hover_color","PopupMenu",TEXT)
	t.set_icon("arrow","OptionButton",icon("chevron-down"));t.set_constant("arrow_margin","OptionButton",10)
	t.set_color("font_color","TooltipLabel",TEXT)
	t.set_stylebox("panel","TooltipPanel",slab(Color("1d1f23f5"),CYAN,10,"left"))
	var transparent:=Image.create(1,1,false,Image.FORMAT_RGBA8);transparent.fill(Color.TRANSPARENT)
	var blank:=ImageTexture.create_from_image(transparent)
	for cls in ["VScrollBar","HScrollBar"]:
		var track:=style(Color("00000000"),Color.TRANSPARENT,0,2)
		var grab:=style(Color("8a8e9488"),Color.TRANSPARENT,0,2)
		t.set_stylebox("scroll",cls,track)
		for state in ["grabber","grabber_highlight","grabber_pressed"]:t.set_stylebox(state,cls,grab)
		for state in ["increment","increment_highlight","increment_pressed","decrement","decrement_highlight","decrement_pressed"]:t.set_icon(state,cls,blank)
	t.set_stylebox("separator","HSeparator",style(Color("ffffff22"),Color.TRANSPARENT,0,0))
	t.set_stylebox("background","ProgressBar",style(Color("3b3e44"),Color.TRANSPARENT,0,0))
	t.set_stylebox("fill","ProgressBar",style(YELLOW,Color.TRANSPARENT,0,0))
	var track:=style(Color("3b3e44"),Color.TRANSPARENT,0,2)
	t.set_stylebox("slider","HSlider",track)
	t.set_stylebox("grabber_area","HSlider",style(CYAN,Color.TRANSPARENT,0,2));t.set_stylebox("grabber_area_highlight","HSlider",style(CYAN.lightened(0.1),Color.TRANSPARENT,0,2))
	t.set_icon("grabber","HSlider",preload("res://assets/slider_knob.svg"));t.set_icon("grabber_highlight","HSlider",preload("res://assets/slider_knob.svg"))
	for key in ["VBoxContainer","HBoxContainer"]:t.set_constant("separation",key,12)
	t.set_constant("h_separation","GridContainer",18);t.set_constant("v_separation","GridContainer",20)
	return t
