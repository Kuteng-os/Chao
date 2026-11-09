extends Control
var phase:=0.0
func _ready()->void:mouse_filter=Control.MOUSE_FILTER_IGNORE
func _process(delta:float)->void:phase+=delta;queue_redraw()
func _draw()->void:
	var center:=size/2
	for i in 3:
		var radius:=42+i*18
		draw_arc(center,radius,phase*0.18+i,phase*0.18+i+4.7,64,Color(0.5,0.8,0.8,0.35-i*0.08),1.5,true)
	var icon:=ChaoUI.icon("layers")
	if icon!=null:draw_texture_rect(icon,Rect2(center-Vector2(18,18),Vector2(36,36)),false,ChaoUI.ACCENT)
