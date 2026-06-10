## Lobby scene — entry point for multiplayer and offline sessions.
## All UI is built in code so no external resources are needed.
extends Control

# UI node refs (built in _ready)
var _address_field  : LineEdit
var _port_field     : LineEdit
var _status_label   : Label

func _ready() -> void:
	_build_ui()
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	anchor_right  = 1.0
	anchor_bottom = 1.0

	var center := CenterContainer.new()
	center.anchor_right  = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(380, 0)
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	# --- Title ---
	var title := Label.new()
	title.text = "LATITUDE 49"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	_add_separator(vbox)

	# --- Server address ---
	var addr_label := Label.new()
	addr_label.text = "Server address"
	vbox.add_child(addr_label)

	_address_field = LineEdit.new()
	_address_field.text = "127.0.0.1"
	_address_field.placeholder_text = "e.g. 192.168.1.100"
	vbox.add_child(_address_field)

	# --- Port ---
	var port_label := Label.new()
	port_label.text = "Port"
	vbox.add_child(port_label)

	_port_field = LineEdit.new()
	_port_field.text = str(NetworkManager.DEFAULT_PORT)
	vbox.add_child(_port_field)

	_add_separator(vbox)

	# --- Buttons ---
	var host_btn := Button.new()
	host_btn.text = "Host (Dedicated / Listen)"
	host_btn.pressed.connect(_on_host_pressed)
	vbox.add_child(host_btn)

	var join_btn := Button.new()
	join_btn.text = "Join Game"
	join_btn.pressed.connect(_on_join_pressed)
	vbox.add_child(join_btn)

	_add_separator(vbox)

	var solo_btn := Button.new()
	solo_btn.text = "Play Offline"
	solo_btn.pressed.connect(_on_solo_pressed)
	vbox.add_child(solo_btn)

	_add_separator(vbox)

	# --- Status ---
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.modulate = Color(1, 0.6, 0.2)
	vbox.add_child(_status_label)

func _add_separator(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)

# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------

func _on_host_pressed() -> void:
	var port := int(_port_field.text) if _port_field.text.is_valid_int() else NetworkManager.DEFAULT_PORT
	_set_status("Starting server on port %d …" % port)
	GameManager.host_and_load(port)

func _on_join_pressed() -> void:
	var address := _address_field.text.strip_edges()
	var port    := int(_port_field.text) if _port_field.text.is_valid_int() else NetworkManager.DEFAULT_PORT
	if address.is_empty():
		_set_status("Enter a server address.")
		return
	_set_status("Connecting to %s:%d …" % [address, port])
	GameManager.join_and_load(address, port)

func _on_solo_pressed() -> void:
	_set_status("Loading …")
	GameManager.play_offline()

# ---------------------------------------------------------------------------
# Network error feedback
# ---------------------------------------------------------------------------

func _on_connection_failed() -> void:
	_set_status("Connection failed. Check address and try again.")

func _on_server_disconnected() -> void:
	_set_status("Disconnected from server.")

func _set_status(msg: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = msg
