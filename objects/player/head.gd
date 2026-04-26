@tool
extends Node3D
@onready var marker = $"../head_path/headPathFollow/Marker3D"

func _process(delta: float) -> void:
	global_position = marker.global_position
