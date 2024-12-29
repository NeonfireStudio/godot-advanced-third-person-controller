extends Node3D

@export var rgb_light_enabled : bool = false

var is_loading : bool = false


func _ready() -> void:
	if rgb_light_enabled:
		$Light3D/AnimationPlayer.speed_scale = 1.5
		$Light3D/AnimationPlayer.play("light_change")
		$Light3D.show()


func change_scene_to_world() -> void:
	if is_loading: return
	
	is_loading = true
	
	var tween = get_tree().create_tween()
	tween.tween_property($MenuUI/FadeScreen, "color:a", 1.0, 1.5)
	tween.play()
	await tween.finished
	tween.kill()
	get_tree().change_scene_to_file("res://World/world.tscn")


func _on_single_player_button_pressed() -> void:
	change_scene_to_world()


func _on_multiplayer_button_pressed() -> void:
	$MenuUI/MenuButtons.hide()
	$MenuUI/HostJoinUI.show()


func _on_about_button_pressed() -> void:
	$MenuUI/MenuButtons.hide()
	$MenuUI/About.show()
	$MenuUI/ButtonBack.show()


func _on_exit_button_pressed() -> void:
	var tween = get_tree().create_tween()
	tween.tween_property($MenuUI/FadeScreen, "color:a", 1.0, 1.5)
	tween.play()
	await tween.finished
	tween.kill()
	get_tree().quit()


func _on_button_back_pressed() -> void:
	$MenuUI/About.hide()
	$MenuUI/ButtonBack.hide()
	$MenuUI/MenuButtons.show()


func _on_m_back_button_pressed() -> void:
	$MenuUI/HostJoinUI.hide()
	$MenuUI/MenuButtons.show()


func _on_host_button_pressed() -> void:
	Global.multiplayer_type = "Host"
	change_scene_to_world()


func _on_join_button_pressed() -> void:
	Global.multiplayer_type = "Join"
	Global.ip_address = $MenuUI/HostJoinUI/IPAddress.text
	change_scene_to_world()


func _on_about_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))
