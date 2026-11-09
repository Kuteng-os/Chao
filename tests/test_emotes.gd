extends SceneTree
const Service = preload("res://scripts/emote_service.gd")
const Cache = preload("res://scripts/ui/emote_cache.gd")
const Wheel = preload("res://scripts/ui/emote_wheel.gd")
const Controller = preload("res://scripts/network/match_controller.gd")
var checks := 0
var failures := 0
var received: Array=[]
class API extends Node:
	var settings := {"backend_url":"https://test.invalid","owner_id":"a"}
	var authenticated := true
	var catalog: Array=[]
	var saved: Array=["","","","","","","",""]
	func request(path: String, method: int=HTTPClient.METHOD_GET, body: Dictionary={}) -> Dictionary:
		await get_tree().process_frame
		if path=="/v1/public/emotes": return {"ok":true,"data":{"emotes":catalog}}
		if method==HTTPClient.METHOD_PUT: saved=body.slots.duplicate()
		return {"ok":true,"data":{"slots":saved.duplicate()}}
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures+=1;push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var e := {"emote_id":"11111111-1111-4111-8111-111111111111","asset_id":"a".repeat(64),"name":"测试","frame_width":16,"frame_height":16,"columns":2,"durations":[100,200]}
	check(Cache.valid(e),"valid animated metadata")
	for key in ["frame_width","columns","durations"]:
		var invalid := e.duplicate(true);invalid[key]=0
		check(not Cache.valid(invalid),"invalid metadata rejected")
	var api := API.new();root.add_child(api);api.catalog=[e]
	var service := Service.new();root.add_child(service);service.bind_store(api)
	check(await service.refresh(),"load catalog and cloud preferences")
	check(service.catalog.size()==1,"catalog installed")
	var selected: Array=[e.emote_id,"","",e.emote_id,"","","",""]
	await service.save_slots(selected)
	check(api.saved==selected and service.slots==selected,"eight-slot local and server save")
	service.last_sent_id=e.emote_id;check(service.repeat_id()==e.emote_id,"valid last emote can repeat")
	api.settings.owner_id="b";service.bind_store(api)
	check(service.slots==["","","","","","","",""],"new account never inherits former wheel")
	check(service.last_sent_id.is_empty(),"account switch clears last emote")
	api.settings.owner_id="a";service.bind_store(api)
	check(service.slots==selected,"returning account restores local wheel")
	var wheel := Wheel.new();wheel.service=service;wheel.slots=selected;wheel.size=Vector2(400,400);root.add_child(wheel)
	for i in 8:
		var angle := -PI/2.0+i*TAU/8.0
		check(wheel.sector(Vector2(200,200)+Vector2(cos(angle),sin(angle))*140)==i,"radial sector %d"%i)
	check(wheel.sector(Vector2(200,200))==-1,"center cancels")
	check(wheel.sector(Vector2(-20,-20))==-1,"outside cancels")
	var controller := Controller.new();root.add_child(controller);controller.emote_service=service;controller.emote_received.connect(func(player,id,point,display_scale):received.append([player,id,point,display_scale]))
	controller.mode="solo";controller.connected=true;controller.state={"winner":-1,"state_seq":22}
	controller.send_emote(e.emote_id);controller.send_emote(e.emote_id)
	check(received.size()==1,"practice send and anti-spam")
	check(controller.state.state_seq==22,"emotes never consume actions")
	controller._receive_cloud_emotes({"emote_events":[{"id":1,"player":1,"emote_id":e.emote_id}]})
	controller._receive_cloud_emotes({"emote_events":[{"id":1,"player":1,"emote_id":e.emote_id}]})
	check(received.size()==2,"cloud event replay is suppressed")
	controller._receive_cloud_emotes({"emote_events":[{"id":2,"player":1,"emote_id":e.emote_id,"scale_percent":150}]})
	check(received[-1][3]==1.5,"server scale overrides stale local catalog")
	service.set_muted(true);check(service.mute_opponent,"mute persists")
	controller.leave_game();check(controller._emote_seen==0,"leaving resets emote cursor")
	wheel.queue_free();controller.queue_free();service.queue_free();api.queue_free()
	await process_frame
	print("EMOTES: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
