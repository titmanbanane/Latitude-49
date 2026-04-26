@tool
extends Node3D

@export var floor: Node3D
@export var wall: Node3D
@export var cornerr: Node3D
@export var roof: Node3D

@export var dimentions: Vector3i:
	set(d):
		dimentions = d
		generate()

func _ready() -> void:
	generate()


func generate() -> void:
	for c in get_children():
		if c.name.contains("@"):
			c.queue_free()
		print(c.name)
	for x in dimentions.x:
		for z in dimentions.z:
			var f
			var r 
			if floor != null and roof != null:
				f = floor.duplicate()
				r = roof.duplicate()
				add_child(f)
				add_child(r)
				f.global_position.z = global_position.z + z
				f.global_position.x = global_position.x + x
				r.global_position.z = global_position.z + z
				r.global_position.x = global_position.x + x
