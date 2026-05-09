extends RigidBody3D
class_name Item

var _original_parent : Node = null
var _freeze_before : bool = false

func _ready() -> void:
	
	pass

func _input_event(camera: Camera3D, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if Input.is_action_just_pressed("fire"):
		print("inter")
