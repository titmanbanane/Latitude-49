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
@export_group("tween")
@export var stance_tween_duration: float = 0.2
@export var aim_tween_duration: float = 0.15
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
@onready var player : CharacterBody3D = $"../.."
@onready var arm_l_ik = $"../../human_mesh/skeletton/GeneralSkeleton/arm_L_ik"
@onready var bagpack_component = $"../bagpack_manager/bagpack_component"

var weapon_snappiness: float = 10.0
var weapon: Node3D
var is_editor: bool
var is_aiming: bool = false
var was_aiming: bool = false

# Tween references so we can kill them before starting a new one
var _stance_tween: Tween
var _cam_tween: Tween

var _last_stance: int = -1

# Captured start/end rotations for method tweens (lerp_angle needs both endpoints)
var _stance_rot_from: Vector3
var _stance_rot_to: Vector3
var _cam_rot_from: Vector3
var _cam_rot_to: Vector3

# Cache recoil vector to avoid creating new Vector3 each frame
const RECOIL_BASE: Vector3 = Vector3(0.0, 0.1, 0.05)

func _ready() -> void:
	is_editor = Engine.is_editor_hint()
	firecast.top_level = true
	if not is_editor:
		weapon_target.top_level = true

	if weapon_target.get_child_count() > 0:
		weapon = weapon_target.get_child(0)

func _input(event: InputEvent) -> void:
	if not player._is_local_player:
		return
	if event.is_action_pressed("fire"):
		_handle_fire()
	elif event.is_action_pressed("stance_up"):
		stance_val += 1
	elif event.is_action_pressed("stance_down"):
		stance_val -= 1

func _handle_fire() -> void:
	if not weapon:
		return

	var recoil_variation := Vector3(
		RECOIL_BASE.x,
		randf_range(-RECOIL_BASE.y, RECOIL_BASE.y),
		randf_range(-RECOIL_BASE.z, RECOIL_BASE.z)
	)

	if firecast.is_colliding():
		debug_bullet.global_position = firecast.get_collision_point()
		var hit := firecast.get_collider()
		if NetworkManager.is_online():
			# In online mode send hit info to the server for authoritative damage.
			player.relay_hit_to_server(hit, firecast.get_collision_point())
		else:
			# Offline / single-player: apply damage locally.
			_apply_local_hit(hit)

func _apply_local_hit(hit: Node) -> void:
	if hit.get_class() == "PhysicalBone3D":
		var bone : Node = hit
		if bone.is_in_group("limb_bone"):
			bone.scale = Vector3(0, 0, 0)
		var npc := bone.get_parent().get_parent().get_parent().get_parent().get_parent()
		if npc.state != npc.dead:
			if bone.is_in_group("head"):
				npc.health["head"] -= 30
			elif bone.is_in_group("torso"):
				npc.health["torso"] -= 30
			npc.health_check()

func take_damage(part, damage_origin):
	pass

func _process(delta: float) -> void:
	if not weapon:
		return

	if player._is_local_player:
		_process_local(delta)
	else:
		_process_remote(delta)

func _process_local(delta: float) -> void:
	if not is_editor:
		is_aiming = Input.is_action_pressed("aim")
	var stance_changed := was_aiming != is_aiming
	was_aiming = is_aiming

	if not is_editor:
		stance = stance_val % 4
		if is_aiming:
			stance = 4

	# Write to synced vars so all remote peers can read them.
	player._net_stance = stance
	player._net_is_aiming = is_aiming

	_handle_stance_positioning(delta, stance_changed)
	_handle_camera_and_weapon_aiming(delta, stance_changed)
	_update_firecast_and_hands()

func _process_remote(delta: float) -> void:
	var new_stance    : int  = player._net_stance
	var new_aiming    : bool = player._net_is_aiming
	var stance_changed : bool = (new_stance != _last_stance) or (new_aiming != was_aiming)
	was_aiming = new_aiming
	stance = new_stance

	# Trigger weapon tween when stance changes (reuses local tween logic).
	if stance != _last_stance:
		_last_stance = stance
		_tween_to_stance(stance)

	# Drive arm IK and weapon dot per stance, no Input dependency.
	match stance:
		0, 1:
			weapon.dot.hide()
			arm_l_ik.active = true
		2:
			if new_aiming: weapon.dot.show() 
			else: weapon.dot.hide()
			arm_l_ik.active = true
		3:
			weapon.dot.hide()
			arm_l_ik.active = true
		4:
			weapon.dot.show()
			arm_l_ik.active = true

	# weapon_target has top_level=true — anchor it to this player's world position.
	var lerp_speed := minf(weapon_snappiness * delta, 1.0)
	weapon_target.global_position = player.global_position
	weapon_target.global_rotation.x = lerp_angle(weapon_target.global_rotation.x, 0.0, lerp_speed * 3.0)
	weapon_target.global_rotation.y = lerp_angle(weapon_target.global_rotation.y, player.global_rotation.y, lerp_speed)
	weapon_target.global_rotation.z = lerp_angle(weapon_target.global_rotation.z, 0.0, lerp_speed)

	# Keep IK hand markers following the weapon for skeleton IK.
	hand_l.global_position = weapon.left_marker.global_position
	hand_l.global_rotation = weapon.left_marker.global_rotation
	hand_r.global_position = weapon.right_marker.global_position
	hand_r.global_rotation = weapon.right_marker.global_rotation

# ---------------------------------------------------------------------------
# Stance positioning
# ---------------------------------------------------------------------------

func _handle_stance_positioning(delta: float, stance_changed: bool) -> void:
	if stance != _last_stance:
		_last_stance = stance
		_tween_to_stance(stance)

	match stance:
		0:
			weapon.dot.hide()
			arm_l_ik.active = true
		1:
			weapon.dot.hide()
			arm_l_ik.active = true
		2:
			_handle_mid_stance(delta)
			arm_l_ik.active = true
		3:
			weapon.dot.hide()
			arm_l_ik.active = not Input.is_action_pressed("run")
		4:
			arm_l_ik.active = true
			_handle_aimed_stance(delta)

func _tween_to_stance(new_stance: int) -> void:
	if _stance_tween and _stance_tween.is_valid():
		_stance_tween.kill()

	var target_pos: Vector3
	var target_rot: Vector3

	match new_stance:
		0:
			target_pos = neutral_pos
			target_rot = neutral_rot
		1:
			target_pos = low_pos
			target_rot = low_rot
		2:
			target_pos = mid_pos
			target_rot = mid_rot
		3:
			target_pos = high_pos
			target_rot = high_rot
		4:
			player.speed_penalty = 1.5
			return
		!4:
			player.speed_penalty = 1

	# Snapshot current rotation as the start point for lerp_angle
	_stance_rot_from = rotation
	_stance_rot_to = target_rot

	_stance_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_stance_tween.tween_property(self, "position", target_pos, stance_tween_duration)
	# Method tween drives _set_stance_rotation(t) from 0->1.
	# Each axis is interpolated with lerp_angle so the weapon always
	# takes the shortest rotational path regardless of angle wrap-around.
	_stance_tween.tween_method(_set_stance_rotation, 0.0, 1.0, stance_tween_duration)

# Called every tween step — applies shortest-path rotation to self.
func _set_stance_rotation(t: float) -> void:
	rotation = Vector3(
		lerp_angle(_stance_rot_from.x, _stance_rot_to.x, t),
		lerp_angle(_stance_rot_from.y, _stance_rot_to.y, t),
		lerp_angle(_stance_rot_from.z, _stance_rot_to.z, t)
	)

# ---------------------------------------------------------------------------
# Mid & aimed stances (per-frame lerp for live tracking)
# ---------------------------------------------------------------------------

func _handle_mid_stance(delta: float) -> void:
	if is_editor:
		rotation = mid_rot
		return

	if is_aiming:
		weapon.dot.show()
		_aim_weapon_at_target(delta)
	else:
		weapon.dot.hide()

	if aimcast.is_colliding():
		look_at(aimcast.get_collision_point())
	else:
		look_at(fallback_aimpos.global_position)

func _handle_aimed_stance(delta: float) -> void:
	weapon.dot.show()
	var lerp_speed := minf(weapon_snappiness * delta * 10, 1.0)
	weapon_target.global_position = lerp(weapon_target.global_position, aimpos.global_position, lerp_speed)
	_lerp_weapon_rotation_to_aimpos(delta)

func _aim_weapon_at_target(delta: float) -> void:
	var lerp_speed := minf(weapon_snappiness * delta * 5.0, 1.0)
	weapon_target.global_position = weapon_target.global_position.lerp(aimpos.global_position, lerp_speed)
	_lerp_weapon_rotation_to_aimpos(delta)

func _lerp_weapon_rotation_to_aimpos(delta: float) -> void:
	if aimcast.is_colliding():
		look_at(aimcast.get_collision_point())
	else:
		look_at(fallback_aimpos.global_position)
	var lerp_speed := minf(weapon_snappiness * delta, 1.0)
	weapon_target.global_rotation.x = lerp_angle(weapon_target.global_rotation.x, aimpos.global_rotation.x, minf(lerp_speed * 3.0, 1.0))
	weapon_target.global_rotation.y = lerp_angle(weapon_target.global_rotation.y, aimpos.global_rotation.y, lerp_speed)
	weapon_target.global_rotation.z = lerp_angle(weapon_target.global_rotation.z, aimpos.global_rotation.z, lerp_speed)
	#print(weapon_target.global_rotation.x, " / ", aimpos.global_rotation.x)

# ---------------------------------------------------------------------------
# Camera aiming tween + weapon_target reset
# ---------------------------------------------------------------------------

func _handle_camera_and_weapon_aiming(delta: float, stance_changed: bool) -> void:
	var should_reset_camera := (not is_aiming or stance != 2) and stance != 4

	if should_reset_camera or (is_editor and stance != 4):
		if stance_changed or is_editor:
			_tween_camera(cam_neutral_pos, cam_neutral_rot)

		weapon_target.global_position = global_position

		var lerp_speed := minf(weapon_snappiness * delta, 1.0)
		weapon_target.global_rotation.x = lerp_angle(weapon_target.global_rotation.x, global_rotation.x, minf(lerp_speed * 3.0, 1.0))
		weapon_target.global_rotation.y = lerp_angle(weapon_target.global_rotation.y, global_rotation.y, lerp_speed)
		weapon_target.global_rotation.z = lerp_angle(weapon_target.global_rotation.z, global_rotation.z, lerp_speed)
	else:
		if stance_changed:
			_tween_camera(cam_aimed_pos, cam_aimed_rot)

func _tween_camera(target_pos: Vector3, target_rot: Vector3) -> void:
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()

	# Snapshot current camera rotation as start point for lerp_angle
	_cam_rot_from = cam.rotation
	_cam_rot_to = target_rot

	_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_cam_tween.tween_property(cam, "position", target_pos, aim_tween_duration)
	# Method tween drives _set_cam_rotation(t) from 0->1.
	# Each axis uses lerp_angle so the camera always rotates the short way.
	_cam_tween.tween_method(_set_cam_rotation, 0.0, 1.0, aim_tween_duration)

# Called every tween step — applies shortest-path rotation to the camera.
func _set_cam_rotation(t: float) -> void:
	cam.rotation = Vector3(
		lerp_angle(_cam_rot_from.x, _cam_rot_to.x, t),
		lerp_angle(_cam_rot_from.y, _cam_rot_to.y, t),
		lerp_angle(_cam_rot_from.z, _cam_rot_to.z, t)
	)

# ---------------------------------------------------------------------------

func _update_firecast_and_hands() -> void:
	firecast.global_position = weapon.muzzle.global_position
	firecast.global_rotation = weapon.muzzle.global_rotation
	
	if !is_editor and player.state == player.in_inventory:
		hand_l.global_position = bagpack_component.handpos.global_position
		hand_l.global_rotation = bagpack_component.handpos.global_rotation
	else:
		hand_l.global_position = weapon.left_marker.global_position
		hand_l.global_rotation = weapon.left_marker.global_rotation
	
	hand_r.global_position = weapon.right_marker.global_position
	hand_r.global_rotation = weapon.right_marker.global_rotation
	
