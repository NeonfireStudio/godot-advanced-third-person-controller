extends Node

var multiplayer_type : String = "None"
var ip_address : String = ""

func _input(_event: InputEvent) -> void:
	# Toggle between fullscreen and maximized window modes when "fullscreen" action is pressed
	if Input.is_action_just_pressed("fullscreen"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_MAXIMIZED)
