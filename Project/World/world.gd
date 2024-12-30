extends Node3D

var enet_peer := ENetMultiplayerPeer.new()

var player

func _ready() -> void:
	if Global.multiplayer_type != "None":
		$Player.queue_free()
	
	match Global.multiplayer_type:
		"Host": host()
		"Join": join()


func host() -> void:
	enet_peer.create_server(9999)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)
	
	add_player(multiplayer.get_unique_id())
	if not Global.ip_address == "localhost": upnp_setup()


func join() -> void:
	enet_peer.create_client(Global.ip_address, 9999)
	multiplayer.multiplayer_peer = enet_peer


func add_player(peer_id) -> void:
	var _player = preload("res://Player/player.tscn").instantiate()
	_player.name = str(peer_id)
	add_child(_player)
	_player.position.y = 5
	player = _player


func remove_player(peer_id) -> void:
	var _player = get_node_or_null(str(peer_id))
	if _player: _player.queue_free()


func upnp_setup() -> void:
	var upnp = UPNP.new()
	
	var discover_result = upnp.discover()
	if discover_result != UPNP.UPNP_RESULT_SUCCESS: print("UPNP Discover Failed! Error %s")

	if not (upnp.get_gateway() and upnp.get_gateway().is_valid_gateway()): print("UPNP Invalid Gateway!")

	var map_result = upnp.add_port_mapping(9999)
	if not map_result == UPNP.UPNP_RESULT_SUCCESS: print("UPNP Port Mapping Failed! Error %s" % map_result)
	
	print("Success! Join Address: %s" % upnp.query_external_address())


func _on_kill_zone_body_entered(body: Node3D) -> void:
	if $HUD/AnimationPlayer.is_playing(): return
	
	if body is Player:
		$HUD/AnimationPlayer.play("fade_in")
		await $HUD/AnimationPlayer.animation_finished
		body.position = Vector3(0, 2.0241, 0)
		$HUD/AnimationPlayer.play("fade_out")


func _physics_process(_delta: float) -> void:
	if has_node("GodotPlush") and !$Labels/Label3D16.visible: $Labels/Label3D16.show()
	
	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://Menu/menu.tscn")

