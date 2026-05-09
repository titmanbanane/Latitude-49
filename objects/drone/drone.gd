extends RigidBody3D

# ═══════════════════════════════════════════════════════════════════════════════
#  FPV DRONE CONTROLLER — Godot 4
#  Single-file. Assign propellers and audio node via exports in the Inspector.
# ═══════════════════════════════════════════════════════════════════════════════

# ─── Propellers (assign MeshInstance3D nodes in Inspector) ───────────────────
@export_group("Propellers")
@export var prop_fl: Node3D  ## Front-Left  — spins CW
@export var prop_fr: Node3D  ## Front-Right — spins CCW
@export var prop_bl: Node3D  ## Back-Left   — spins CCW
@export var prop_br: Node3D  ## Back-Right  — spins CW

@export var prop_max_spin_rps: float = 12.0
## Visual rotations per second at full throttle (radians/s = this × TAU)

# ─── Audio (assign AudioStreamPlayer3D in Inspector) ─────────────────────────
@export_group("Motor Audio")
@export var motor_sound: AudioStreamPlayer3D
## If no stream is assigned on the node, a procedural buzz is generated instead.

@export var motor_pitch_idle:  float = 0.7  ## pitch_scale at zero throttle
@export var motor_pitch_full:  float = 1.2  ## pitch_scale at full throttle

# ─── Thrust ───────────────────────────────────────────────────────────────────
@export_group("Thrust")
@export var max_thrust:          float = 28.0
## Total upward force (N) at full throttle. Rule of thumb: ~2.5× (mass × 9.8).

@export var hover_thrust_ratio:  float = 0.55
## Throttle fraction (0-1) needed to hover.
## Formula: (mass_kg × 9.8) / max_thrust

# ─── Torques ──────────────────────────────────────────────────────────────────
@export_group("Torques")
@export var pitch_torque: float = 12.0
@export var roll_torque:  float = 12.0
@export var yaw_torque:   float = 6.0

# ─── Feel ─────────────────────────────────────────────────────────────────────
@export_group("Feel")
@export var angular_damp_factor: float = 4.0
## Extra angular damping applied each physics tick — higher = snappier stops.

@export var linear_damp_factor:  float = 0.8
## Horizontal air-resistance drag coefficient.

@export var motor_ramp_speed:    float = 6.0
## How fast motor_speed (audio + prop visuals) ramps toward target (units/s).

# ─── Controller ───────────────────────────────────────────────────────────────
@export_group("Controller")
@export var gamepad_deadzone: float = 0.15

@export var mouse_sensitivity: float = 0.003
## Mouse motion → pitch / yaw input scale (radians per pixel).
## Typical range: 0.001 (slow) – 0.006 (fast).

@export var mouse_input_decay: float = 100.0
## How quickly mouse pitch/yaw input fades when the mouse is still (units/s).
## Higher = snappier return to neutral after moving the mouse.

# ─── Camera ───────────────────────────────────────────────────────────────────
@export_group("FPV Camera")
@export var camera_tilt_deg: float = 14.0
## Forward tilt of the FPV camera in degrees (typical freestyle: 10-25°).

# ══════════════════════════════════════════════════════════════════════════════
#  PRIVATE STATE
# ══════════════════════════════════════════════════════════════════════════════

# Inputs  (-1 … 1)
var _throttle := 0.0
var _pitch    := 0.0
var _roll     := 0.0
var _yaw      := 0.0

# Mouse accumulated delta this frame (reset each _process tick)
var _mouse_pitch := 0.0
var _mouse_yaw   := 0.0

## Public — read by external scripts if needed (e.g. HUD)
var motor_speed := 0.0   # 0-1, smoothed

# Camera rig created at runtime
var _cam_rig:  Node3D  = null
var _camera:   Camera3D = null

# Procedural audio
var _gen_playback: AudioStreamGeneratorPlayback = null
var _gen_phase:    float = 0.0

const _SAMPLE_HZ   := 44100.0
const _BUF_SEC     := 0.1

# ══════════════════════════════════════════════════════════════════════════════
#  READY
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_camera()
	_init_audio()

func _build_camera() -> void:
	_cam_rig = Node3D.new()
	_cam_rig.name = "FPVCameraRig"
	get_tree().root.add_child(_cam_rig)   # top-level → no transform inheritance
	_cam_rig.top_level = true

	_camera = Camera3D.new()
	_camera.name = "FPVCamera"
	_camera.fov   = 90.0
	# Tilt forward and offset slightly forward on the body
	_camera.position = Vector3(0.0, 0.05, 0.12)
	_camera.rotation_degrees = Vector3(-camera_tilt_deg, 0.0, 0.0)
	_cam_rig.add_child(_camera)
	_camera.make_current()

func _init_audio() -> void:
	if motor_sound == null:
		return

	# If the user left the stream empty → generate procedurally
	if motor_sound.stream == null:
		var gen := AudioStreamGenerator.new()
		gen.mix_rate      = _SAMPLE_HZ
		gen.buffer_length = _BUF_SEC
		motor_sound.stream = gen

	motor_sound.play()

	if motor_sound.stream is AudioStreamGenerator:
		_gen_playback = motor_sound.get_stream_playback()

# ══════════════════════════════════════════════════════════════════════════════
#  INPUT EVENTS  (mouse motion + cursor toggle)
# ══════════════════════════════════════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Accumulate — will be consumed in _read_input and reset
		_mouse_pitch += event.relative.y * mouse_sensitivity
		_mouse_yaw   += event.relative.x * mouse_sensitivity

	elif event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			# Toggle cursor capture so the player can alt-tab / quit
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ══════════════════════════════════════════════════════════════════════════════
#  PER-FRAME  (input + visuals + audio)
# ══════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	_read_input(delta)
	_update_motor_speed(delta)
	_update_camera()
	_spin_props(delta)
	_update_audio(delta)

# ── Input ─────────────────────────────────────────────────────────────────────

func _read_input(delta: float) -> void:
	# ── Keyboard: throttle + roll only ───────────────────────────────────────
	var kb_thr := Input.get_action_strength("drone_throttle_up")  - Input.get_action_strength("drone_throttle_down")
	var kb_rol := Input.get_action_strength("drone_roll_right")   - Input.get_action_strength("drone_roll_left")

	# ── Mouse → pitch (Y) and yaw (X) for keyboard mode ──────────────────────
	# _mouse_pitch/_yaw were filled by _unhandled_input this frame.
	# Clamp so a sudden fast swipe can't give >1 and decay toward 0 each frame.
	var mouse_pit := clampf(_mouse_pitch, -1.0, 1.0)
	var mouse_yaw := clampf(_mouse_yaw,   -1.0, 1.0)
	# Decay: bleed toward zero so releasing the mouse returns to neutral
	_mouse_pitch = move_toward(_mouse_pitch, 0.0, mouse_input_decay * delta)
	_mouse_yaw   = move_toward(_mouse_yaw,   0.0, mouse_input_decay * delta)

	# ── Gamepad — Mode 2: left stick = throttle+yaw, right stick = pitch+roll ─
	var gp_thr := _dead(Input.get_action_strength("drone_gp_throttle_up")  - Input.get_action_strength("drone_gp_throttle_down"))
	var gp_pit := -_dead(Input.get_action_strength("drone_gp_pitch_back")   - Input.get_action_strength("drone_gp_pitch_forward"))
	var gp_rol := _dead(Input.get_action_strength("drone_gp_roll_right")   - Input.get_action_strength("drone_gp_roll_left"))
	var gp_yaw := _dead(Input.get_action_strength("drone_gp_yaw_right")    - Input.get_action_strength("drone_gp_yaw_left"))

	# Merge: gamepad wins its axes; keyboard+mouse win theirs.
	# If a gamepad axis is active it overrides the mouse on that axis.
	_throttle = clampf(kb_thr  + gp_thr, -1.0, 1.0)
	_roll     = clampf(kb_rol  + gp_rol, -1.0, 1.0)
	_pitch    = clampf(mouse_pit + gp_pit/50, -1.0, 1.0)
	_yaw      = clampf(mouse_yaw + gp_yaw/50, -1.0, 1.0)

func _dead(v: float) -> float:
	if absf(v) < gamepad_deadzone:
		return 0.0
	return sign(v) * (absf(v) - gamepad_deadzone) / (1.0 - gamepad_deadzone)

# ── Motor speed (shared by audio + props) ─────────────────────────────────────

func _update_motor_speed(delta: float) -> void:
	# Target: throttle contribution + a little from actual velocity (kinetic feel)
	var target := clampf(
		_throttle * 0.6 + linear_velocity.length() * 0.04 + 0.4,
		0.0, 1.0
	)
	motor_speed = move_toward(motor_speed, target, motor_ramp_speed * delta)

# ── Camera ────────────────────────────────────────────────────────────────────

func _update_camera() -> void:
	if _cam_rig == null:
		return
	_cam_rig.global_position = global_position
	# Full rotation copy → authentic FPV tilt with pitch/roll/yaw
	_cam_rig.global_rotation = global_rotation

# ── Propeller spin ────────────────────────────────────────────────────────────

func _spin_props(delta: float) -> void:
	var rads := motor_speed * prop_max_spin_rps * TAU * delta
	# Alternate directions: FL+BR = CW (+), FR+BL = CCW (-)
	if prop_fl: prop_fl.rotate_y( rads)
	if prop_fr: prop_fr.rotate_y(-rads)
	if prop_bl: prop_bl.rotate_y(-rads)
	if prop_br: prop_br.rotate_y( rads)

# ── Audio ─────────────────────────────────────────────────────────────────────

func _update_audio(_delta: float) -> void:
	if motor_sound == null:
		return

	var target_pitch := lerpf(motor_pitch_idle, motor_pitch_full, motor_speed)
	motor_sound.pitch_scale = target_pitch

	# Procedural path: fill the generator buffer
	if _gen_playback != null:
		_fill_generator_buffer(target_pitch)

func _fill_generator_buffer(pitch_scale: float) -> void:
	var frames := _gen_playback.get_frames_available()
	if frames == 0:
		return

	# Map pitch_scale (0.7–1.2) → base frequency (80–220 Hz)
	var base_hz  := remap(pitch_scale, motor_pitch_idle, motor_pitch_full, 80.0, 220.0)
	var increment := base_hz / _SAMPLE_HZ

	for _i in frames:
		_gen_phase = fmod(_gen_phase + increment, 1.0)
		var saw    := _gen_phase * 2.0 - 1.0                   # fundamental sawtooth
		var harm3  := sin(_gen_phase * TAU * 3.0) * 0.25       # 3rd harmonic grit
		var sample := (saw * 0.6 + harm3) * 0.35               # master volume
		_gen_playback.push_frame(Vector2(sample, sample))

# ══════════════════════════════════════════════════════════════════════════════
#  PHYSICS
# ══════════════════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	# ── Thrust along drone's local up axis ───────────────────────────────────
	var eff_thr := clampf(_throttle * 0.5 + hover_thrust_ratio, 0.0, 1.0)
	apply_central_force(transform.basis.y * (eff_thr * max_thrust))

	# ── Control torques in local frame ───────────────────────────────────────
	apply_torque(transform.basis * Vector3(
		-_pitch * pitch_torque,
		-_yaw   * yaw_torque,
		-_roll  * roll_torque
	))

	# ── Extra angular damping (crisp FPV feel) ───────────────────────────────
	angular_velocity -= angular_velocity * angular_damp_factor * delta

	# ── Horizontal air drag ──────────────────────────────────────────────────
	var flat_vel := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	apply_central_force(-flat_vel * linear_damp_factor)
