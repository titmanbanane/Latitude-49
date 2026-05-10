extends Node

@export var hold_distance: float = 2.5
@export var follow_speed: float = 15.0
@export var pickup_range: float = 4.0

@onready var camera: Camera3D = get_parent()

var held_object: RigidBody3D = null
var hold_point: Node3D
var wants_pickup: bool = false  # flag set by input, consumed by physics

func _ready() -> void:
	hold_point = Node3D.new()
	hold_point.position = Vector3(0, 0, -hold_distance)
	camera.call_deferred("add_child", hold_point)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("mouse_pickup"):
		if held_object:
			drop_object()
		else:
			wants_pickup = true  # don't raycast here, just set the flag

func _physics_process(delta: float) -> void:
	if wants_pickup:
		wants_pickup = false
		try_pickup()

	if held_object:
		_move_held_object(delta)

func try_pickup() -> void:
	var space_state := camera.get_world_3d().direct_space_state
	if not space_state:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_end := ray_origin + camera.project_ray_normal(mouse_pos) * pickup_range

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [$"../../../.."]

	var result := space_state.intersect_ray(query)
	if result and result.collider is RigidBody3D and result.collider.is_in_group("item"):
		pickup_object(result.collider as RigidBody3D)

func pickup_object(body: RigidBody3D) -> void:
	held_object = body
	held_object.freeze = true
	held_object.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

func drop_object() -> void:
	if not held_object:
		return
	held_object.freeze = false
	held_object.linear_velocity = -camera.global_transform.basis.z * 2.0
	held_object = null

func _move_held_object(delta: float) -> void:
	if not hold_point.is_inside_tree():
		return
	
	var target_pos: Vector3 = hold_point.global_position
	held_object.global_position = held_object.global_position.lerp(
		target_pos,
		clamp(follow_speed * delta, 0.0, 1.0)
	)
	held_object.global_rotation = held_object.global_rotation.lerp(
		camera.global_rotation,
		clamp(follow_speed * 0.5 * delta, 0.0, 1.0)
	)
