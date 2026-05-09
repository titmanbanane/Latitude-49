@tool
extends Node3D

@export var left_marker : Node3D
@export var right_marker : Node3D
@export var muzzle : Node3D
@export var dot : Node3D
@export var set_pos = Vector3()

@export var mag_contents = 0
var firemode = 0
var chamber = 0


func _ready() -> void:
	position = set_pos
