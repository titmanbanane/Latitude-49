extends Node

@export var hold_distance: float = 2.5
@export var follow_speed: float = 15.0
@export var pickup_range: float = 4.0

@onready var camera: Camera3D = get_parent()

var held_object: RigidBody3D = null
var hold_point: Node3D
var wants_pickup: bool = false
var wants_store: bool = false
var target_rot: Vector3
var over_backpack: bool = false

func _ready() -> void:
	hold_point = Node3D.new()
	hold_point.position = Vector3(0, 0, -hold_distance)
	camera.call_deferred("add_child", hold_point)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("mouse_pickup"):
		if held_object:
			# if hovering backpack, store it; otherwise drop it
			if over_backpack:
				wants_store = true
			else:
				drop_object()
		else:
			wants_pickup = true

func _physics_process(delta: float) -> void:
	if wants_pickup:
		wants_pickup = false
		try_pickup()
	if wants_store:
		wants_store = false
		try_store()
	if held_object:
		_move_held_object(delta)

func try_pickup() -> void:
	var space_state := camera.get_world_3d().direct_space_state
	if not space_state:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_end := ray_origin + camera.project_ray_normal(mouse_pos) * pickup_range

	# First check if we're clicking a stored item to unstore it
	var area_query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	area_query.collide_with_areas = true
	var area_result := space_state.intersect_ray(area_query)
	if area_result and area_result.collider.is_in_group("bagpack_area"):
		# Check if there's a stored item child to pick back up
		var bag_area = area_result.collider
		for child in bag_area.get_children():
			if child is RigidBody3D and child.is_in_group("item"):
				unstore_object(child, bag_area)
				return

	# Otherwise try to pick up a world item
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	var result := space_state.intersect_ray(query)
	if result and result.collider is RigidBody3D and result.collider.is_in_group("item"):
		pickup_object(result.collider as RigidBody3D)

func pickup_object(body: RigidBody3D) -> void:
	held_object = body
	held_object.freeze = true
	held_object.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

func try_store() -> void:
	var backpack_pos = _get_backpack_result()
	if not backpack_pos:
		return
	
	var bag_area = backpack_pos["collider"]
	# Check if not overlapping stored item here
	
	held_object.freeze = false
	held_object.reparent(bag_area.get_parent())
	held_object = null

func unstore_object(body: RigidBody3D, bag_area: Node3D) -> void:
	
	body.reparent(get_tree().current_scene)
	held_object.freeze = false
	pickup_object(body)

func drop_object() -> void:
	if not held_object:
		return
	# Make sure it's in the scene root, not still parented to the bag
	if held_object.get_parent() != get_tree().current_scene:
		var saved_transform := held_object.global_transform
		held_object.reparent(get_tree().current_scene, false)
		held_object.global_transform = saved_transform
	held_object.freeze = false
	held_object.linear_velocity = -camera.global_transform.basis.z * 2.0
	held_object = null

func _move_held_object(delta: float) -> void:
	if not hold_point.is_inside_tree():
		return

	var backpack_result = _get_backpack_result()
	var target_pos: Vector3

	if backpack_result:
		over_backpack = true
		target_pos = backpack_result["position"]
		target_rot = backpack_result["collider"].global_rotation
	else:
		over_backpack = false
		target_pos = hold_point.global_position
		target_rot = camera.global_rotation

	held_object.global_position = held_object.global_position.lerp(
		target_pos,
		clamp(follow_speed * delta, 0.0, 1.0)
	)
	held_object.global_rotation = held_object.global_rotation.lerp(
		target_rot,
		clamp(follow_speed * 0.5 * delta, 0.0, 1.0)
	)

# Returns the full result dict if hovering backpack, null otherwise
func _get_backpack_result() -> Variant:
	var space_state := camera.get_world_3d().direct_space_state
	if not space_state:
		return null

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_end := ray_origin + camera.project_ray_normal(mouse_pos) * 10.0

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = true
	if held_object:
		query.exclude = [held_object.get_rid()]

	var result := space_state.intersect_ray(query)
	if result and result.collider.is_in_group("bagpack_area"):
		return result
	
	return null
