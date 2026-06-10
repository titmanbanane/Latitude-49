## NetworkManager — autoload singleton, pure transport layer.
## Wraps ENetMultiplayerPeer and re-emits connection events as typed signals.
## Does NOT contain any gameplay logic.
extends Node

const DEFAULT_PORT   := 7777
const MAX_CLIENTS    := 16

## Emitted on every peer (client side: only fires for the local connection).
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_connected
signal server_disconnected
signal connection_failed

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Start a dedicated / listen server.
func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err  := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		push_error("[NetworkManager] create_server failed: %s" % str(err))
		return err
	multiplayer.multiplayer_peer = peer
	print("[NetworkManager] Hosting on port ", port)
	return OK

## Connect to a remote server.
func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err  := peer.create_client(address, port)
	if err != OK:
		push_error("[NetworkManager] create_client failed: %s" % str(err))
		return err
	multiplayer.multiplayer_peer = peer
	print("[NetworkManager] Connecting to %s:%d" % [address, port])
	return OK

## Clean disconnect.
func disconnect_peer() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

func is_server() -> bool:
	return multiplayer.is_server()

func get_id() -> int:
	return multiplayer.get_unique_id()

## True when a network peer is active (multiplayer session is running).
func is_online() -> bool:
	return multiplayer.multiplayer_peer != null

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_peer_connected(id: int) -> void:
	print("[NetworkManager] Peer connected: %d" % id)
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	print("[NetworkManager] Peer disconnected: %d" % id)
	player_disconnected.emit(id)

func _on_connected_to_server() -> void:
	print("[NetworkManager] Connected. Our peer id: %d" % multiplayer.get_unique_id())
	server_connected.emit()

func _on_connection_failed() -> void:
	push_error("[NetworkManager] Connection failed")
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

func _on_server_disconnected() -> void:
	push_warning("[NetworkManager] Server disconnected")
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()
