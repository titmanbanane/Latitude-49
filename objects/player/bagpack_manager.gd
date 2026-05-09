@tool
extends Node3D

@export var bag_comp : Node3D
@export var basepos : Marker3D
@export var openpos : Marker3D



func _on_bagpack_component_open_changed(new_state: bool) -> void:
	if new_state:
		bag_comp.global_transform = openpos.global_transform
	else:
		bag_comp.global_transform = basepos.global_transform
