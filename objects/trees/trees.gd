@tool
extends Node3D
var rand = RandomNumberGenerator.new()

@export var _randomize = false:
	set(r):
		radomize_tree()
		_randomize = false

func _ready() -> void:
	radomize_tree()

func radomize_tree():
	for i in $meshes.get_children():
		i.hide()
	rand.seed = int($meshes.global_position.x + $meshes.global_position.y + $meshes.global_position.z)
	$meshes.get_child(rand.randi_range(0, $meshes.get_child_count()-1)).show()
	rotate(Vector3.UP,deg_to_rad(rand.randi_range(0,360)))
