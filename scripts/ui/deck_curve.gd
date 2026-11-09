extends Control
var counts:Array=[]
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;custom_minimum_size.y=56;resized.connect(queue_redraw)
func _draw()->void:
	var font:=get_theme_default_font();var cap:=1
	for count in counts:cap=maxi(cap,int(count))
	var slot:=size.x/8.0
	for i in 8:
		var count:int=int(counts[i]) if i<counts.size() else 0
		var height:=maxf(2,32.0*count/cap)
		draw_style_box(ChaoUI.style(Color("bcbcbc3b") if count==0 else Color("d2d2d2aa"),Color.TRANSPARENT,2,0),Rect2(i*slot+5,34-height,slot-10,height))
		draw_string(font,Vector2(i*slot,52),str(i) if i<7 else "7+",HORIZONTAL_ALIGNMENT_CENTER,slot,11,ChaoUI.MUTED)
