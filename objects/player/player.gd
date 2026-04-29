extends CharacterBody3D

@onready var head_path = $head_path
@onready var head = $head
@onready var cam : Camera3D = $head/camera_rotation/Camera3D
@onready var cam_rot = $head/camera_rotation

@onready var intercast = $head/camera_rotation/Camera3D/intercast
@onready var floorcast := $floorcast
@onready var climbcast : RayCast3D = $climbcast
@onready var climb_destination : RayCast3D = $climb_destination
@onready var climb_clearence := $climb_clearence
@onready var climb_cancel : RayCast3D = $climb_cancel
@onready var small_climbcast : RayCast3D = $small_climbcast
@onready var reach : RayCast3D = $head/camera_rotation/Camera3D/reach
@onready var dofcast : RayCast3D = $head/camera_rotation/Camera3D/dofcast

@onready var foot_l = $foot_l_Spring/foot_l
@onready var foot_r = $foot_r_Spring/foot_r
@onready var hand_l = $hand_l
@onready var hand_r = $hand_r
@onready var weapon_manager = $upperchest/weapon_manager

@onready var anim = $human_mesh/AnimationPlayer
@onready var anim_tree = $human_mesh/AnimationTree

@onready var reticle = $gui/reticle
@onready var inventory := $inventory
var inv_arr = []

@onready var popup : Label = $gui/popup
@onready var pause_menu := $pause

@export var jump_multiplier = 1

@export var hands_snappiness : float = 12
@export var hands_returnspeed : float = 6 
@export var sway_smoothness : float = 10
@export var sway_multiplier : float = 1.5
@export var lean_speed : float = 0.0005

var mouse_sensitivity := 0.1
var controller_sensitivity := 4

var gravity := -0.6
var air_speed := 0.08
const jump_strength := 10.5
const speed := 0.7
var resistance = 1
var speed_penalty := 1

var fov = 80
var sensitivity_penalty = 1
@export var running_speed := 1.05
var friction := 0.15
var current_rotation : Vector3
var target_rotation : Vector3
var target_position : Vector3
var current_position : Vector3
var mouse_direction : Vector2
var mouse_vector : Vector2
var h_velocity : Vector2

var lean_progress = 0.5

var stats : Dictionary = {
	"hunger" = 100,
	"thirst" = 100,
	"stamina" = 100,
	"bounty" = 0,
	"sleepyness"= 0,
	"sadness"= 0,
	"temperature"= 25,
	"dirty"= 0,
}

var health : Dictionary = {
	"head" = 30,
	"torso" = 90,
	"stomac" = 80,
	"left_arm" = 50,
	"right_arm" = 50,
	"left_leg" = 50,
	"right_leg" = 50,
}

enum {
	paused,
	idle,
	running,
	climbing,
	in_inventory,
	aiming,
	interacting,
	sliding,
	crouching
}

var state = idle:
	set(new_state):
		state = new_state
		match  state:
			crouching:
				friction = 0.15
				var t = get_tree().create_tween()
				t.tween_property($CollisionShape3D, "scale",Vector3(1,0.25,1),0.2)
			idle:
				friction = 0.15
				var t = get_tree().create_tween()
				t.tween_property($CollisionShape3D, "scale",Vector3(1,1,1),0.2)
			sliding:
				friction = 0.02
				var t = get_tree().create_tween()
				t.tween_property($CollisionShape3D, "scale",Vector3(1,0.25,1),0.2)


func _ready() -> void:
	health_check()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	$human_mesh.top_level = true
	for ik in get_tree().get_nodes_in_group("ik"):
		ik.start()

func _input(event) -> void:
	
	rotate_y(deg_to_rad(get_right_stick().y * controller_sensitivity))
	head.rotate_x(deg_to_rad(get_right_stick().x * controller_sensitivity))
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-60), deg_to_rad(85))
	
	if event is InputEventMouseMotion:
		if Input.is_action_pressed("lean"):
			lean_progress += event.relative.x * lean_speed
			lean_progress = clamp(lean_progress,0.1,0.9)
		
		else:
			rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity * sensitivity_penalty))
			head.rotate_x(deg_to_rad(-event.relative.y * mouse_sensitivity * sensitivity_penalty))
			head.rotation.x = clamp(head.rotation.x, deg_to_rad(-60), deg_to_rad(85))
			head.rotation.z = clamp(head.rotation.z,0,0)
			head.rotation.y = clamp(head.rotation.y,0,0)
			
			mouse_vector = -event.relative  * (int(head.rotation.x >= deg_to_rad(-74) and head.rotation.x <= deg_to_rad(84)))
	
	
	if Input.is_action_just_pressed("lean"):
		var t = get_tree().create_tween()
		t.tween_property(self, "lean_progress",0.5,0.2)
		await t.finished
		lean_progress = 0.5
	
	
	if Input.is_action_just_pressed("ui_cancel"):
		state = idle
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		pause_menu.show()
		get_tree().paused = true
	
	#if Input.is_action_just_pressed("action_right") and state != in_inventory:
		#if state == idle:
				#state = aiming
	#if Input.is_action_just_released("action_right") and state != in_inventory:
			#state = idle
	if Input.is_action_just_pressed("crouch"):
		if state == sliding or state == crouching:
			state = idle
		elif h_velocity.length() < 5:
			state = sliding
		else:
			state = crouching
	
	if Input.is_action_pressed("run") or Input.is_action_pressed("jump"):
		if state == crouching:
			state = idle
	
	if intercast.is_colliding() and Input.is_action_just_pressed("interact"):
		var i = intercast.get_collider()
		if i.is_in_group("interactible"):
			i.interact()

func _process(delta) -> void:
	if intercast.is_colliding() and intercast.get_collider().is_in_group("interactible"):
		reticle.show()
	else :
		reticle.hide()
	
	$human_mesh.global_position = global_position
	if Vector2(velocity.x, velocity.z).length() < 0.1:
		if abs(($human_mesh.global_rotation.y - global_rotation.y)) > deg_to_rad(30):
			$human_mesh.global_rotation.y = lerp_angle($human_mesh.global_rotation.y,  global_rotation.y, delta * 3 * abs($human_mesh.global_rotation.y - global_rotation.y))
	else :
		$human_mesh.global_rotation.y = global_rotation.y
	
	var walking_space_vector : Vector2 = Vector2(velocity.x, velocity.z).rotated(global_rotation.y)*0.1
	anim_tree.set("parameters/locomotion/blend_position", walking_space_vector)
	if Input.is_action_pressed("ui_cancel"):
		anim_tree.set("parameters/fightstance/blend_amount", clamp(abs(walking_space_vector.length()*3), 0, 1))
		anim_tree.tree_root.get_node("fightstance").filter_enabled = true
		if Input.is_action_just_pressed("fire"):
			anim_tree.set("parameters/punchshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	else: 
		anim_tree.set("parameters/fightstance/blend_amount", 1)
		anim_tree.tree_root.get_node("fightstance").filter_enabled = false
	
	for i in stats:
		match i:
			"health":
				stats[i] = clamp(stats[i],-100,100)
				if stats[i] <= 0:
					die()
	
	if reach.is_colliding():
		if reach.get_collider().is_in_group("interactible"):
			popup.show()
			popup.position = get_viewport().get_camera_3d().unproject_position(reach.get_collider().global_transform.origin)
			popup.text = reach.get_collider().const_name
			if Input.is_action_just_released("inter_right"):
				if reach.get_collider().is_in_group("gun"):
					var gun : RigidBody3D = reach.get_collider()
					gun.queue_free()
		elif popup.visible:
			popup.hide()
	
	mouse_direction = lerp(mouse_direction, mouse_vector, 10 * get_process_delta_time())
	
	
	$gui/fps_label.text = "fps: " + str(Performance.get_monitor(Performance.TIME_FPS))
	$gui/npc_label.text = "npc: " + str(get_tree().get_nodes_in_group("npc").size())
	$gui/speed_label.text = "speed: " + str(int(velocity.length()))
	
	if Input.is_action_just_pressed("inventory") and state == idle:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		state = in_inventory
	elif Input.is_action_just_pressed("inventory") and state == in_inventory:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		state = idle
	
	h_velocity = Vector2(velocity.x,velocity.z)
	
	var target_fov = fov + h_velocity.length() * 2
	cam.fov = lerp(cam.fov,target_fov,delta * 15.0)
	cam.fov = clamp(cam.fov,50,110)
	
	match  state:
		in_inventory:
			inventory.show()
			sensitivity_penalty = 0.5
		idle:
			inventory.hide()
			sensitivity_penalty = 1
		climbing:
			sensitivity_penalty = 0.3
		sliding:
			if h_velocity.length() < 6:
				state = crouching
	
	$gui/stats.text = str(stats)
	
	head_path.get_child(0).progress_ratio = lean_progress
	head.global_position = head_path.get_child(0).global_position
	
	#parkour_system()


func _physics_process(delta) -> void:
	
	var input := get_forward_acceleration() + get_side_acceleration()
	
	if state != climbing:
		if is_on_wall() and Input.is_action_just_pressed("jump"):
			velocity += get_wall_normal() * (jump_strength * 0.9)
			state = sliding
		if (is_on_floor() or floorcast.is_colliding()) and state != sliding:
			input = input.normalized()
			var vect_input = Vector2((Input.get_action_strength("right") - Input.get_action_strength("left"))/2, Input.get_action_strength("front") - (Input.get_action_strength("back")/2))
			var run_action_strengh = Input.get_action_strength("run") * vect_input.length()
			velocity += input * ((speed + (running_speed * run_action_strengh)) / speed_penalty)
			
			velocity.x *= 1 - friction
			velocity.z *= 1 - friction
			
			if Input.is_action_just_pressed("jump"):
				velocity.y = (jump_strength * jump_multiplier) / speed_penalty
		else:
			velocity += input * air_speed
			if state == sliding:
				velocity.x *= 1 - friction
				velocity.z *= 1 - friction
		
		if !is_on_floor() or state == sliding:
			velocity += (Vector3(0,gravity,0) * 1+get_floor_normal()) * (1-delta)
		elif  (is_on_floor() or floorcast.is_colliding()) and !Input.is_action_pressed("jump"):
			velocity.y = 0
	
	
	#if h_velocity.length() >0.5:
		#anim.play("walk")
		#var target_speed = h_velocity.length() * 0.2
		#anim.speed_scale = lerp(anim.speed_scale,target_speed * (0.5 + (0.5 * int(state != aiming))),delta * 15.0)
	#else:
		#anim.play("RESET")
	move_and_slide()
	collide_with_physics_bodies()

func collide_with_physics_bodies() -> void:
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var collider := collision.get_collider()
		
		# Calculate impulse properties
		var impulse_direction := -collision.get_normal()
		var impulse_strength := velocity.length() * 0.05
		var impulse_point := collision.get_position()
		
		# Apply impulse based on body type
		if collider is RigidBody3D:
			collider.apply_impulse(impulse_direction * impulse_strength, impulse_point)
		
		elif collider is VehicleBody3D:
			# VehicleBody needs slightly different handling
			collider.apply_impulse(impulse_direction * impulse_strength * 0.7, impulse_point)
		
		elif collider is PhysicalBone3D:
			# For ragdolls, we apply to both the bone and its parent skeleton
			collider.apply_impulse(impulse_direction * impulse_strength * 0.5, impulse_point)
			
			# Also apply to the parent skeleton for better reaction
			var skeleton : Skeleton3D = collider.find_parent("Skeleton3D")
			if skeleton:
				skeleton.apply_impulse(impulse_direction * impulse_strength * 0.3, impulse_point)

#func parkour_system() -> void:
	#
	#climb_clearence.global_transform.origin = climb_destination.get_collision_point() + Vector3(0,1.2,0)
	#
	#if Input.is_action_just_pressed("jump") and (state != in_inventory or state != climbing):
		#if !climb_clearence.is_colliding() and !climb_cancel.is_colliding() and climbcast.is_colliding() and climb_destination.is_colliding():
			#state = climbing
			#var tween = get_tree().create_tween()
			#tween.tween_property(self, "position",climbcast.get_collision_point() + Vector3(0,0.2,0),0.2)
			#tween.tween_property(self, "position",climb_destination.get_collision_point() + Vector3(0,0.1,0),0.25)
			##cam_anim.play("climb")
			#tween.tween_property(self, "state",idle,0)
			#velocity = Vector3()
	#
	#if Input.is_action_pressed("front") and state != climbing:
		#if !is_on_floor() and small_climbcast.is_colliding():
			#if !climb_clearence.is_colliding() and climb_destination.is_colliding() and !climbcast.is_colliding():
				#var tween = get_tree().create_tween()
				#tween.tween_property(self, "position",climb_destination.get_collision_point() + Vector3(0,0.1,0),0.15).set_ease(Tween.EASE_OUT)

func recoil_fire(recoil : Vector3 =  Vector3(0.2,0.1,0.05)):
	target_rotation += Vector3(recoil.x,randf_range(-recoil.y,recoil.y),randf_range(-recoil.z,recoil.z))


func take_damage(damage,_source = null, part = "head"):
	health[part] -= damage
	health_check()

func health_check():
	if health["head"] <= 0:
		print("dead")
	
	if health["left_leg"] <= 0 or health["right_leg"] <= 0:
		speed_penalty = 2
	else:
		speed_penalty = 1
	
	if health["left_arm"] <= 0 or health["right_arm"] <= 0:
		weapon_manager.aim_tween_duration = 1
		weapon_manager.stance_tween_duration = 3
	else:
		weapon_manager.aim_tween_duration = 0.15
		weapon_manager.stance_tween_duration = 0.5

func teleport(_position : Vector3):
	global_position = _position

func die():
	queue_free()

func get_side_acceleration() -> Vector3:
	return global_transform.basis.x * (
		Input.get_action_strength("right") - Input.get_action_strength("left")
	)

func put_hand_to(hand : String,destination : Vector3, rot : Vector3 = Vector3(0,0,0) ):
	weapon_manager.put_hand_to(hand,destination,rot)


func get_forward_acceleration() -> Vector3:
	return global_transform.basis.z * (
		Input.get_action_strength("back") - Input.get_action_strength("front")
	)


func get_right_stick() -> Vector2:
	return Vector2(
		Input.get_action_strength("look_down")-Input.get_action_strength("look_up"),
		Input.get_action_strength("look_right")-Input.get_action_strength("look_left")
	)


func _on_resume_button_down():
	get_tree().paused = false
	pause_menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_quit_button_down():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _on_player_zone_body_entered(body: Node3D) -> void:
	if body.is_in_group("npc"):
		var npc = body
		if npc.type == "zombie" and npc.state != npc. dead:
			npc.state = npc.attack
