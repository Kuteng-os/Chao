class_name BattleTable
extends "res://scripts/ui/battle_stage_3d.gd"

class Lines extends Control:
	var table: Control
	func _draw() -> void:
		var rect: Rect2=table.field_rect
		var ink:=Color(0.8,0.8,0.8,0.22)
		for y in [rect.position.y,rect.end.y]:
			draw_line(Vector2(rect.position.x,y),Vector2(rect.end.x,y),ink,1,true)
			for x in range(int(rect.position.x),int(rect.end.x),80):draw_line(Vector2(x,y-2),Vector2(x,y+2),Color(ink,0.3),1)
		var font:=get_theme_default_font()
		draw_string(font,Vector2(rect.position.x-56,rect.get_center().y+5),"前线",HORIZONTAL_ALIGNMENT_LEFT,44,12,Color(0.8,0.8,0.8,0.5))
		if table.front_owner>=0:
			var hue:=Color("d2d2d2") if table.front_owner==0 else Color("dda5a0")
			draw_line(Vector2(rect.position.x,rect.get_center().y-10),Vector2(rect.position.x,rect.get_center().y+10),Color(hue,0.65),2,true)

func _ready() -> void:
	super._ready()
	markers=Lines.new();markers.table=self;markers.mouse_filter=Control.MOUSE_FILTER_IGNORE
	markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(markers)

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(markers):markers.queue_redraw()
