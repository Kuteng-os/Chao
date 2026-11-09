extends Node

func _ready() -> void:
	_start.call_deferred()

func _start() -> void:
	var error := get_tree().change_scene_to_file("res://scenes/main.tscn")
	if error != OK:
		var label := Label.new()
		label.text = "启动失败，请关闭后重新打开游戏以恢复基础版本。"
		add_child(label)
