@tool
extends Node

@export var tunel_mesh : CSGPolygon3D
@export var tunel_path : Path3D
@export var point_A : Marker3D
@export var point_B : Marker3D
@export_range(3,10000,1) var points_count: int = 3
@export_range(0,1000,1) var width_range : float = 3

@export var _generate : bool:
	set(g):
		generate()

func _ready() -> void:
	generate()

func generate() -> void:
	tunel_path.curve.clear_points()
	
	# Build positions array first
	var positions: Array[Vector3] = []
	for p in points_count:
		if p == 0:
			positions.append(point_A.global_position)
		elif p == points_count - 1:
			positions.append(point_B.global_position)
		else:
			var t = remap(p, 0, points_count - 1, 0, 1.0)
			var pos = lerp(point_A.global_position, point_B.global_position, t)
			pos.x -= randf_range(width_range / 2, -width_range / 2)
			positions.append(pos)
	
	# Add points with Catmull-Rom tangents for smoothing
	for i in positions.size():
		var local_pos = tunel_path.to_local(positions[i])
		
		# Get neighbour positions (clamp at endpoints)
		var prev = tunel_path.to_local(positions[max(i - 1, 0)])
		var next = tunel_path.to_local(positions[min(i + 1, positions.size() - 1)])
		
		# Tangent = direction from prev to next, scaled for smoothness
		var tangent = ((next - prev) * 0.25)
		
		tunel_path.curve.add_point(local_pos, -tangent, tangent)
