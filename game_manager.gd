## GameManager — autoload singleton that owns player spawning / despawning
## and the damage relay between peers and the server.
##
## Spawn flow (dedicated server):
##   1. Client connects  → server sends _request_spawn RPC to that client
##   2. Client responds  → sends its desired spawn position back to server
##   3. Server calls     → _spawn_player.rpc() so ALL peers add the node
##
## The player node name is always str(peer_id) so paths are identical on every peer.
extends Node

const PLAYER_SCENE_PATH := "res://objects/player/player.tscn"
const GAME_WORLD_PATH   := "res://main.tscn"
const LOBBY_SCENE_PATH  := "res://lobby/lobby.tscn"
const SPAWN_AREA_HALF   := 5.0   ## Random spawn radius from origin
const SPAWN_HEIGHT      := 50.0

var _player_scene : PackedScene

## peer_id → CharacterBody3D  (valid on all peers for all connected players)
var spawned_players : Dictionary = {}

# ---------------------------------------------------------------------------
# Init
# ---------------------------------------------------------------------------

func _ready() -> void:
	_player_scene = load(PLAYER_SCENE_PATH)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_connected.connect(_on_server_connected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

# ---------------------------------------------------------------------------
# Public API called by the Lobby
# ---------------------------------------------------------------------------

## Host a dedicated or listen server then load the game world.
func host_and_load(port: int = NetworkManager.DEFAULT_PORT) -> void:
	var err := NetworkManager.host(port)
	if err != OK:
		push_error("[GameManager] Failed to host: %s" % str(err))
		return
	await _load_game_world()
	# If this is a dedicated server it will have no local player.
	# If running as a listen server, spawn the host's player now.
	if not _is_headless():
		var spawn_pos := _random_spawn()
		_spawn_player.rpc(NetworkManager.get_id(), spawn_pos)

## Join a remote server then load the game world.
## The server will instruct us to spawn once we are ready.
func join_and_load(address: String, port: int = NetworkManager.DEFAULT_PORT) -> void:
	var err := NetworkManager.join(address, port)
	if err != OK:
		push_error("[GameManager] Failed to join: %s" % str(err))
		return
	# Wait for the connection to succeed before changing scene
	await NetworkManager.server_connected
	await _load_game_world()
	# Tell the server we are ready
	_client_ready.rpc_id(1)

## Start a fully offline single-player session.
func play_offline() -> void:
	await _load_game_world()
	# In offline mode the pre-placed player in main.tscn handles everything.

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _random_spawn() -> Vector3:
	return Vector3(
		randf_range(-SPAWN_AREA_HALF, SPAWN_AREA_HALF),
		SPAWN_HEIGHT,
		randf_range(-SPAWN_AREA_HALF, SPAWN_AREA_HALF)
	)

func _load_game_world() -> void:
	get_tree().change_scene_to_file(GAME_WORLD_PATH)
	# Wait two frames: tree_changed fires mid-setup; process_frame ensures
	# the new scene is fully added and all _ready() calls have completed.
	await get_tree().process_frame
	await get_tree().process_frame
	# Remove the single-player placeholder player that lives in main.tscn,
	# but only when we are in an online session.
	if NetworkManager.is_online():
		var world := get_tree().current_scene
		var placeholder := world.get_node_or_null("player")
		if placeholder:
			placeholder.queue_free()

func _get_game_world() -> Node:
	return get_tree().current_scene

# ---------------------------------------------------------------------------
# Peer event handlers
# ---------------------------------------------------------------------------

func _on_player_connected(_peer_id: int) -> void:
	pass
	# Intentionally empty: sending RPCs here races against the client loading
	# the game world. We wait for the client to call _client_ready instead.

func _on_player_disconnected(peer_id: int) -> void:
	if NetworkManager.is_server():
		_despawn_player.rpc(peer_id)
	else:
		_despawn_player_local(peer_id)

func _on_server_connected() -> void:
	pass  # We send _client_ready after scene loads (see join_and_load).

func _on_server_disconnected() -> void:
	for id in spawned_players.keys():
		_despawn_player_local(id)
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)

# ---------------------------------------------------------------------------
# RPCs
# ---------------------------------------------------------------------------

## Client → Server : "I am loaded and ready, please spawn me"
@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if not NetworkManager.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var pos    := _random_spawn()
	# Give the newly-ready client a snapshot of every already-spawned player.
	for existing_id in spawned_players:
		_spawn_player.rpc_id(sender, existing_id, spawned_players[existing_id].position)
	# Spawn the new player on ALL peers (server + all existing clients + new client).
	_spawn_player.rpc(sender, pos)

## Server → All : "create player for this peer at this position"
@rpc("authority", "call_local", "reliable")
func _spawn_player(peer_id: int, spawn_pos: Vector3) -> void:
	if spawned_players.has(peer_id):
		return
	var world := _get_game_world()
	if world == null:
		push_error("[GameManager] _spawn_player called but no world scene is loaded")
		return

	var player : CharacterBody3D = _player_scene.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)

	# Pre-disable the camera BEFORE the node enters the scene tree.
	# Camera3D nodes entering the tree with current=true (the .tscn default)
	# will steal the active camera slot from the host's own camera before
	# _ready() gets a chance to set current=false. Accessing child nodes on
	# an unparented instance is safe.
	var pre_cam := player.get_node_or_null("head/camera_rotation/Camera3D")
	if pre_cam:
		pre_cam.current = false

	world.add_child(player)

	# global_position requires the node to already be inside the tree.
	player.global_position = spawn_pos

	spawned_players[peer_id] = player

	if peer_id == NetworkManager.get_id():
		# Defer so _ready() on the new player node runs first,
		# populating all @onready vars before activate_local_player() touches them.
		player.activate_local_player.call_deferred()

## Server → All : "remove this player"
@rpc("authority", "call_local", "reliable")
func _despawn_player(peer_id: int) -> void:
	_despawn_player_local(peer_id)

func _despawn_player_local(peer_id: int) -> void:
	if spawned_players.has(peer_id):
		if is_instance_valid(spawned_players[peer_id]):
			spawned_players[peer_id].queue_free()
		spawned_players.erase(peer_id)

# ---------------------------------------------------------------------------
# Damage relay (client → server → victim)
# ---------------------------------------------------------------------------

## Any client fires this at the server (peer 1) when it hits another player.
## part  : body part key ("head", "torso", etc.)
## amount: raw damage value
@rpc("any_peer", "call_remote", "reliable")
func relay_player_damage(target_peer_id: int, part: String, amount: int) -> void:
	if not NetworkManager.is_server():
		return
	if not spawned_players.has(target_peer_id):
		return
	# Tell the owning client to apply the damage locally.
	_apply_damage_on_client.rpc_id(target_peer_id, part, amount)

## Server → owning client : "you were hit"
@rpc("authority", "call_remote", "reliable")
func _apply_damage_on_client(part: String, amount: int) -> void:
	var my_id := NetworkManager.get_id()
	if spawned_players.has(my_id):
		spawned_players[my_id].take_damage(amount, null, part)

## Any client fires this at the server when it hits an NPC bone.
## npc_path : absolute NodePath to the NPC (identical on all peers when properly spawned)
## bone_group: "head" or "torso"
## amount   : damage
@rpc("any_peer", "call_remote", "reliable")
func relay_npc_damage(npc_path: NodePath, bone_group: String, amount: int) -> void:
	if not NetworkManager.is_server():
		return
	var npc := get_node_or_null(npc_path)
	if npc == null or not npc.has_method("take_damage_server"):
		return
	npc.take_damage_server(bone_group, amount)
