extends SceneTree
const HUD = preload("res://scripts/ui/battle_emotes.gd")
const Service = preload("res://scripts/emote_service.gd")
var failures := 0
var checks := 0
var sent: Array=[]
func check(ok: bool, text: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(text)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var service := Service.new();root.add_child(service);service.shortcut=KEY_T
	service.slots=Array();for i in 8: service.slots.append("11111111-1111-4111-8111-%012d"%i)
	for id in service.slots: service.catalog.append({"emote_id":id,"asset_id":"a".repeat(64),"name":"测试","frame_width":16,"frame_height":16,"columns":1,"durations":[100]})
	preload("res://scripts/ui/emote_cache.gd").textures["a".repeat(64)]=ImageTexture.create_from_image(Image.create(16,16,false,Image.FORMAT_RGBA8))
	var hud := HUD.new();hud.service=service;hud.size=Vector2(1440,900);root.add_child(hud)
	hud.send_requested.connect(func(id,point): sent.append({"id":id,"point":point}))
	var key := InputEventKey.new();key.physical_keycode=KEY_T;key.pressed=true;hud._input(key)
	check(hud._mode=="key","holding T opens wheel")
	key.pressed=false;hud._input(key);check(sent.is_empty(),"first empty release sends nothing")
	key.pressed=true;hud._input(key)
	hud._anchor=Vector2(720,450);hud._update_direction(Vector2(825,345))
	check(hud._selected==1,"northeast flick selects slot 2")
	key.pressed=false;hud._input(key)
	check(sent.size()==1 and sent[0].id==service.slots[1],"releasing shortcut sends selected emote")
	check(sent[0].point.is_equal_approx(Vector2(.5,.5)),"message carries summon point rather than selected wedge")
	hud._due=0;hud._open_at(Vector2(720,450),"key");hud._update_direction(Vector2(730,450));hud._finish()
	check(sent.size()==2 and sent[1].id==sent[0].id,"empty keyboard release repeats last emote")
	hud.me=1;hud._open_at(Vector2(720,675),"key");hud._update_direction(Vector2(720,560));hud._finish()
	check(sent[2].point.is_equal_approx(Vector2(.5,.25)),"opposite seat uses shared coordinate system")
	check(hud._bubble_at(0,Vector2(.5,.25)).is_equal_approx(Vector2(684,639)),"receiver reflects to local orientation")
	hud._due=0;hud.input_blocked=true;key.pressed=true;hud._input(key)
	check(hud._mode.is_empty(),"shortcut blocked while modal is open")
	hud.input_blocked=false
	var touch := InputEventScreenTouch.new();touch.index=0;touch.pressed=true;touch.position=hud.get_global_transform_with_canvas()*hud._button.get_rect().get_center();hud._input(touch)
	check(hud._mode=="placing","mobile begins by holding emote button")
	var drag := InputEventScreenDrag.new();drag.index=0;drag.position=Vector2(900,400);hud._input(drag)
	hud._stable_at-=300;hud._process(0)
	check(hud._mode=="touch" and hud._anchor==Vector2(900,400),"pause at intended location opens wheel")
	drag.position=Vector2(900,500);hud._input(drag)
	touch.pressed=false;touch.position=drag.position;hud._input(touch)
	check(sent.size()==4 and sent[3].id==service.slots[4],"mobile flick and release sends without extra tap")
	check(hud._mode.is_empty() and hud._touch_index==-1,"touch gesture fully releases capture")
	# The last selection belongs to the session, so ordinary battle view rebuilds retain it.
	hud.queue_free();await process_frame
	hud=HUD.new();hud.service=service;hud.size=Vector2(1440,900);root.add_child(hud)
	hud.send_requested.connect(func(id,point): sent.append({"id":id,"point":point}))
	key.pressed=true;hud._input(key);hud._anchor=Vector2(360,225)
	check(hud._wheel.center_text=="重发上次","keyboard center indicates repeat")
	key.pressed=false;hud._input(key)
	check(sent.size()==5 and sent[-1].id==service.slots[4] and sent[-1].point==Vector2(.25,.25),"tap after view rebuild repeats at new anchor")
	key.pressed=true;hud._input(key);check(hud._mode.is_empty(),"rapid repeats retain existing debounce")
	hud._due=0;hud._open_at(Vector2(400,300),"key");hud._update_direction(Vector2(400,190));key.pressed=false;hud._input(key)
	check(sent.size()==6 and sent[-1].id==service.slots[0],"new selection replaces remembered emote")
	for i in 3:
		hud._due=0;key.pressed=true;hud._input(key);key.pressed=false;hud._input(key)
	check(sent.size()==9 and sent[-1].id==service.slots[0],"successive taps repeat without reselection")
	var before:=sent.size()
	hud._open_at(Vector2(400,300),"touch");hud._finish();check(sent.size()==before,"touch center still cancels")
	hud._open_at(Vector2(400,300),"key")
	var escape:=InputEventKey.new();escape.physical_keycode=KEY_ESCAPE;escape.pressed=true;hud._input(escape);hud._input(key)
	check(sent.size()==before and hud._mode.is_empty(),"Escape cancels without repeating on key-up")
	hud._open_at(Vector2(400,300),"key");hud._cancel_gesture();hud._input(key)
	check(sent.size()==before,"window focus loss cancels repeat")
	var previous:String=service.last_sent_id
	service.slots[1]="";hud._open_at(Vector2(400,300),"key");hud._selected=1;hud._finish()
	check(sent.size()==before and service.last_sent_id==previous,"empty slot neither sends nor overwrites history")
	service.slots[0]="";hud._open_at(Vector2(400,300),"key");hud._finish()
	check(sent.size()==before,"removed wheel entry cannot repeat")
	service.slots[0]=previous;service.catalog=[];hud._open_at(Vector2(400,300),"key");hud._finish()
	check(sent.size()==before,"deleted catalog emote cannot repeat")
	hud.queue_free();service.queue_free();await process_frame
	print("EMOTE_GESTURES: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
