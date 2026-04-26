@tool
extends Node3D

@export_enum("neutral", "low", "mid", "high", "aimed") var stance: int
var stance_val: int = 0

@export_group("neutral")
@export var neutral_pos: Vector3
@export var neutral_rot: Vector3
@export_group("low")
@export var low_pos: Vector3
@export var low_rot: Vector3
@export_group("mid")
@export var mid_pos: Vector3
@export var mid_rot: Vector3
@export_group("high")
@export var high_pos: Vector3
@export var high_rot: Vector3
@export_group("cam neutral")
@export var cam_neutral_pos: Vector3
@export var cam_neutral_rot: Vector3
@export_group("cam aimed")
@export var cam_aimed_pos: Vector3
@export var cam_aimed_rot: Vector3
@export_group("")

@onready var hand_l: Node3D = $"../../hand_l"
@onready var hand_r: Node3D = $"../../hand_r"
@onready var firecast: RayCast3D = $"../../firecast"
@onready var aimcast: RayCast3D = $"../../head/camera_rotation/Camera3D/aimcast"
@onready var fallback_aimpos: Marker3D = $"../../head/camera_rotation/Camera3D/fallback_aimpos"
@onready var weapon_target: Node3D = $weapon_target
@onready var aimpos: Node3D = $"../../head/camera_rotation/aimpos"
@onready var cam: Camera3D = $"../../head/camera_rotation/Camera3D"
@onready var debug_bullet: Node3D = $"../../debug bullet"

var weapon_snappiness: float = 10.0
var weapon: Node3D
var is_editor: bool
var is_aiming: bool = false
var was_aiming: bool = false

# Cache recoil vector to avoid creating new Vector3 each frame
const RECOIL_BASE: Vector3 = Vector3(0.0, 0.1, 0.05)

func _ready() -> void:
	is_editor = Engine.is_editor_hint()
	firecast.top_level = true
	if not is_editor:
		weapon_target.top_level = true
	
	# Cache weapon reference
	if weapon_target.get_child_count() > 0:
		weapon = weapon_target.get_child(0)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("fire"):
		_handle_fire()
	elif event.is_action_pressed("stance_up"):
		stance_val += 1
	elif event.is_action_pressed("stance_down"):
		stance_val -= 1

func _handle_fire() -> void:
	if not weapon:
		return
		
	# Apply recoil with random variation
	var recoil_variation := Vector3(
		RECOIL_BASE.x,
		randf_range(-RECOIL_BASE.y, RECOIL_BASE.y),
		randf_range(-RECOIL_BASE.z, RECOIL_BASE.z)
	)
	#weapon_target.rotation += recoil_variation
	#weapon_target.position.z += 0.25
	
	if firecast.is_colliding():
		debug_bullet.global_position = firecast.get_collision_point()

func _physics_process(delta: float) -> void:
	if not weapon:
		return
	
	# Cache aiming state to avoid multiple input checks
	if not is_editor:
		is_aiming = Input.is_action_pressed("aim") 
	var stance_changed := was_aiming != is_aiming
	was_aiming = is_aiming
	
	if not is_editor:
		stance = stance_val % 4
		if is_aiming:
			stance = 4
	
	_handle_stance_positioning(delta)
	_handle_camera_and_weapon_aiming(delta, stance_changed)
	_update_firecast_and_hands()

func _handle_stance_positioning(delta: float) -> void:
	match stance:
		0: # neutral
			position = neutral_pos
			rotation = neutral_rot
			weapon.dot.hide()
		1: # low
			position = low_pos
			rotation = low_rot
			weapon.dot.hide()
		2: # mid
			position = mid_pos
			_handle_mid_stance(delta)
		3: # high
			position = high_pos
			rotation = high_rot
			weapon.dot.hide()
			if Input.is_action_pressed("run"):
				var ik = $"../../human_mesh/skeletton/GeneralSkeleton/arm_L_ik"
				ik.active = false
			else:
				var ik = $"../../human_mesh/skeletton/GeneralSkeleton/arm_L_ik"
				ik.active = true
		4: # aimed
			_handle_aimed_stance(delta)

func _handle_mid_stance(delta: float) -> void:
	if is_editor:
		rotation = mid_rot
		return
	
	if is_aiming:
		cam.position = cam_aimed_pos
		cam.rotation = cam_aimed_rot
		weapon.dot.show()
		_aim_weapon_at_target(delta)
	else:
		weapon.dot.hide()
	
	# Handle look_at for mid stance (both aiming and non-aiming)
	if aimcast.is_colliding():
		look_at(aimcast.get_collision_point())
	else:
		look_at(fallback_aimpos.global_position)

func _handle_aimed_stance(delta: float) -> void:
	cam.position = cam_aimed_pos
	cam.rotation = cam_aimed_rot
	weapon.dot.show()
	var lerp_speed := weapon_snappiness * delta * 10
	weapon_target.global_position = lerp(weapon_target.global_position, aimpos.global_position, lerp_speed)
	_lerp_weapon_rotation_to_aimpos(delta)

func _aim_weapon_at_target(delta: float) -> void:
	var lerp_speed := weapon_snappiness * delta * 5.0
	weapon_target.global_position = weapon_target.global_position.lerp(aimpos.global_position, lerp_speed)
	_lerp_weapon_rotation_to_aimpos(delta)

func _lerp_weapon_rotation_to_aimpos(delta: float) -> void:
	if aimcast.is_colliding():
		look_at(aimcast.get_collision_point())
	else:
		look_at(fallback_aimpos.global_position)
	var lerp_speed := weapon_snappiness * delta
	weapon_target.global_rotation.x = lerp_angle(weapon_target.global_rotation.x, aimpos.global_rotation.x, 1)
	weapon_target.global_rotation.y = lerp_angle(weapon_target.global_rotation.y, aimpos.global_rotation.y, lerp_speed)
	weapon_target.global_rotation.z = lerp_angle(weapon_target.global_rotation.z, aimpos.global_rotation.z, lerp_speed)
	#print(weapon_target.global_rotation.x, " / ", aimpos.global_rotation.x)

func _handle_camera_and_weapon_aiming(delta: float, stance_changed: bool) -> void:
	var should_reset_camera := (not is_aiming or stance != 2) and stance != 4
	
	if should_reset_camera or (is_editor and stance != 4):
		if stance_changed or is_editor:  # Only update if state changed
			cam.position = cam_neutral_pos
			cam.rotation = cam_neutral_rot
		
		weapon_target.global_position = global_position
		
		var lerp_speed := weapon_snappiness * delta
		weapon_target.global_rotation.x = lerp_angle(weapon_target.global_rotation.x, global_rotation.x, 1)
		weapon_target.global_rotation.y = lerp_angle(weapon_target.global_rotation.y, global_rotation.y, lerp_speed)
		weapon_target.global_rotation.z = lerp_angle(weapon_target.global_rotation.z, global_rotation.z, lerp_speed)

func _update_firecast_and_hands() -> void:
	# Update firecast position
	firecast.global_position = weapon.muzzle.global_position
	firecast.global_rotation = weapon.muzzle.global_rotation
	
	# Update hand positions
	hand_r.global_position = weapon.right_marker.global_position
	hand_r.global_rotation = weapon.right_marker.global_rotation
	hand_l.global_position = weapon.left_marker.global_position
	hand_l.global_rotation = weapon.left_marker.global_rotation
