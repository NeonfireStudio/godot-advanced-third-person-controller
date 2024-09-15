extends Node3D

var enet_peer := ENetMultiplayerPeer.new()

func _ready() -> void:
	if Global.multiplayer_type != "None":
		$Player.queue_free()
	
	match Global.multiplayer_type:
		"Host": host()
		"Join": join()

func host():
	enet_peer.create_server(9999)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)
	
	add_player(multiplayer.get_unique_id())
	#if not Global.ip_address == "localhost": upnp_setup()

func join():
	enet_peer.create_client(Global.ip_address, 9999)
	multiplayer.multiplayer_peer = enet_peer

func add_player(peer_id):
	var player = preload("res://Player/player.tscn").instantiate()
	player.name = str(peer_id)
	add_child(player)
	player.position.y = 5

func remove_player(peer_id):
	var player = get_node_or_null(str(peer_id))
	if player: player.queue_free()

func upnp_setup():
	var upnp = UPNP.new()
	
	var discover_result = upnp.discover()
	if discover_result != UPNP.UPNP_RESULT_SUCCESS: print("UPNP Discover Failed! Error %s")

	if not (upnp.get_gateway() and upnp.get_gateway().is_valid_gateway()): print("UPNP Invalid Gateway!")

	var map_result = upnp.add_port_mapping(9999)
	if not map_result == UPNP.UPNP_RESULT_SUCCESS: print("UPNP Port Mapping Failed! Error %s" % map_result)
	
	print("Success! Join Address: %s" % upnp.query_external_address())
