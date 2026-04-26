extends Node3D

@export var body : RigidBody3D
@export var camera : Camera3D
@export var cam_pos : Node3D
@export var out_pos : Marker3D
@export var player_pos : Marker3D
@export var steer_tires_joint : Array
@export var steer_tires : Array
@export var drive_tires_joint : Array
@export var drive_tires : Array
@export var rear_steer_tires : Array

@export var engine_power = 60
@export var steer_force = 5
@export var steer_angle = 60
@export var steer_range = 0.1

var occupied = false:
	set(occ):
		occupied = occ
		camera.current = occ

var old_pos : Vector3
var v2_linear_velocity : Vector2
var amount : float

func _ready():
	camera.top_level = true

func _input(event):
	if occupied:
		if Input.is_action_just_pressed("fire"):
			body.linear_velocity.y = 0
			body.apply_central_impulse(Vector3(0,2500,0))
		elif Input.is_action_just_pressed("aim"):
			body.apply_impulse(Vector3(0,1000,0),Vector3(1,0,0))
		if Input.is_action_just_pressed("interact"):
			occupied = false
			get_tree().get_first_node_in_group("player").teleport(out_pos.global_position)
			get_tree().get_first_node_in_group("player").cam.current = true

func _process(delta):
	if occupied :
		get_tree().get_first_node_in_group("player").global_position = player_pos.global_position
		v2_linear_velocity = Vector2(body.linear_velocity.x,body.linear_velocity.z)
		#apply a central force wich is the horizontal speed vector length run through a exponential and start after 100 length
		#body.apply_central_force(Vector3(0,clamp((exp(v2_linear_velocity.length()) * -0.0001)+100,-INF,0),0))
		#$body/Label3D.text = str(int(v2_linear_velocity.length()*3.4))
		
	#	global_position = body.global_position
		
		old_pos = body.global_position
		
		camera.global_position = lerp(camera.global_position,cam_pos.global_position, delta * 10)
		camera.global_rotation.y = cam_pos.global_rotation.y
		camera.global_rotation.x = lerp_angle(camera.global_rotation.x,cam_pos.global_rotation.x,delta * 2)
		
		accel()
		steer()

func EnableMotor(enable):
	
		if !drive_tires_joint.is_empty():
			for i in drive_tires_joint:
				if i != null:
					var tire = get_node(i)
					tire.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, enable)

func steer():
	# Get raw steering input (-1 to 1)
	var steer_input = Input.get_action_strength("SteerRight") - Input.get_action_strength("SteerLeft")
	
	# Smoothly interpolate steering amount
	amount = lerpf(amount, steer_input, 5 * get_process_delta_time())  # Smoother interpolation
	
	if !steer_tires_joint.is_empty():
		for i in steer_tires_joint:
			if i != null:
				var tire = get_node(i)
				
				# Convert to radians once
				var max_angle = deg_to_rad(steer_angle)
				var angle = max_angle * amount
				
				# Always set both limits (fixed the duplicate lower limit issue)
				tire.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, angle)
				tire.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, angle)
				
				# Apply steering force only when there's significant input
				if abs(amount) > 0.1:
					tire.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, amount * steer_force)
				else:
					# Center the wheels when no input
					tire.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, 0)

#func steer():
	#amount = lerpf(amount, Input.get_action_strength("SteerRight") -Input.get_action_strength("SteerLeft"),1 * get_process_delta_time())
	#print(amount, " / " , Input.get_action_strength("SteerRight") -Input.get_action_strength("SteerLeft"),1 * get_process_delta_time())
	#if !steer_tires_joint.is_empty():
		#for i in steer_tires_joint:
			#if i != null:
				#var tire = get_node(i)
				#
				#if amount > 0.1 or amount < -0.1:
					#if amount > 0:
						#tire.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,(steer_angle) * amount)
						#tire.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,(steer_angle-steer_range) * amount)
						#tire.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY,amount * steer_force )
					#else:
						#tire.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,(steer_angle) * amount)
						#tire.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,(steer_angle-steer_range) * amount)
						#tire.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY,amount * steer_force )
				#else :
					#tire.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,0)
					#tire.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,0)
					#tire.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY,0)

func accel():
	var amount = Input.get_action_strength("Accelerate") - Input.get_action_strength("Decelerate")
	
	if amount == 0:
		EnableMotor(false)
	else:
		EnableMotor(true)
	
	if !drive_tires_joint.is_empty():
		for i in drive_tires_joint:
			if i != null:
				var tire = get_node(i)
				tire.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, -amount * engine_power)


func _on_interarea_interacted() -> void:
	occupied = true
