@tool
extends Node3D

@export var light : Node3D
@export var handpos : Marker3D

var tween : Tween
signal open_changed(new_state : bool)

@export var open = false:
	set(o):
		open = o
		if not is_node_ready():
			return
		light.visible = open
		child_collision_state(open)
		emit_signal("open_changed", open)
		manage_opening(open)

func child_collision_state(enabled : bool):
	for child in get_children():
		if child is RigidBody3D and child.is_in_group("item"):
			child.collision_layer = 1 if enabled else 0
			child.collision_mask = 1 if enabled else 0

func manage_opening(open):
	for i in get_tree().get_nodes_in_group("bagpack"):
		if get_children().has(i):
			var bagpack : MeshInstance3D = i
			var mat : StandardMaterial3D = bagpack.get_surface_override_material(1)
			if tween:
				tween.kill()
			tween = create_tween()
			tween.set_parallel(true)
			if open:
				if mat:
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				tween.tween_method(
					func(v): bagpack.set("blend_shapes/open", v),
					bagpack.get("blend_shapes/open"), 1.0, 0.2
				)
				if mat:
					tween.tween_method(
						func(v): mat.albedo_color.a = v,
						mat.albedo_color.a, 0.25, 0.2
					)
			else:
				tween.tween_method(
					func(v): bagpack.set("blend_shapes/open", v),
					bagpack.get("blend_shapes/open"), 0.0, 0.2
				)
				if mat:
					tween.tween_method(
						func(v): mat.albedo_color.a = v,
						mat.albedo_color.a, 1.0, 0.2
					)
					tween.tween_callback(
						func(): mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					).set_delay(0.2)
