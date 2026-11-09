extends "res://scripts/main.gd"
func _startup_begin() -> void: _boot_loading=false
func _ready() -> void:
	super._ready()
	store.settings.backend_url="http://127.0.0.1:1";store._ensure_context()
	_run_capture.call_deferred()
func _run_capture() -> void:
	get_viewport().warp_mouse(Vector2(4,4))
	await get_tree().create_timer(2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../../preview090-home.png")
	menu_backdrop.stage.set_scene("atelier")
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../../preview090-home-day.png")
	get_tree().quit()
