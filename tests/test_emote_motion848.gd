extends SceneTree
const HUD=preload("res://scripts/ui/battle_emotes.gd")
const Service=preload("res://scripts/emote_service.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var service:=Service.new();root.add_child(service);service.catalog=[{"emote_id":"11111111-1111-4111-8111-111111111111"}];service.mute_opponent=false
	var hud:=HUD.new();hud.service=service;hud.size=Vector2(1440,900);hud._mobile=false;root.add_child(hud);hud._visual_rng.seed=887
	check(not hud._button.visible and hud.get_children().filter(func(n):return n is Button and n.visible).is_empty(),"desktop has no battle emote buttons")
	check(not hud.has_signal("configure_requested"),"battle HUD has no configuration route")
	for i in 8:hud.show_emote(0,service.catalog[0].emote_id,Vector2(.5,.5))
	var offsets:Dictionary={}
	for sprite in hud._bubbles:
		var offset:Vector2=sprite.get_meta("offset");offsets[str(offset)]=true
		check(absf(offset.x)<=12 and absf(offset.y)<=8 and absf(sprite.rotation)<=.14,"small bounded offset and rotation")
	check(offsets.size()>1,"rapid repeats have distinct offsets")
	var sprite:Control=hud._bubbles[0];var first:Vector2=sprite.position
	sprite.set_meta("born",Time.get_ticks_msec()-1100);hud._animate_bubbles()
	check(sprite.position.y<first.y-10 and sprite.modulate.a>0 and sprite.modulate.a<.8,"emote rises and gradually fades")
	sprite.set_meta("born",Time.get_ticks_msec()-2000);hud._animate_bubbles();check(hud._bubbles.size()==7,"finished sprite removed")
	hud._mobile=true;hud._process(0);check(hud._button.visible,"mobile keeps summon control")
	service.set_muted(true);hud.show_emote(1,service.catalog[0].emote_id);check(hud._bubbles.size()==7,"opponent mute still honored")
	hud.show_emote(0,service.catalog[0].emote_id,Vector2(.5,.5),1.0)
	check(hud._bubbles[-1].size.is_equal_approx(Vector2(156,156)),"1x uses headquarters width")
	hud.show_emote(0,service.catalog[0].emote_id,Vector2(.5,.5),2.0)
	check(hud._bubbles[-1].size.is_equal_approx(Vector2(312,312)),"author 2x is applied to battle sprite")
	hud.hq_width=180;hud._animate_bubbles();check(hud._bubbles[-1].size.is_equal_approx(Vector2(360,360)),"resize keeps headquarters-relative size")
	hud.hq_width=156;hud.show_emote(0,service.catalog[0].emote_id,Vector2(.5,.5),NAN)
	check(hud._bubbles[-1].size.is_equal_approx(Vector2(71.76,71.76)),"invalid scale falls back to legacy size")
	hud.queue_free();service.queue_free();await process_frame
	print("EMOTE_MOTION848: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
