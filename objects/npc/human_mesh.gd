@tool
extends Node3D

#@export var randomize_skin_color_palette : bool = false:
	#set(b):
		#randomize_color_palette()

#@onready var body = $human_mesh/skeletton/GeneralSkeleton/body
#@onready var skeleton = $human_mesh/skeletton/GeneralSkeleton
#@onready var anim = $AnimationPlayer
#@onready var anim_tree = $AnimationTree
#@onready var eyeR = $headattachement/eye_R
#@onready var eyeL = $headattachement/eye_L
#@onready var eyepoint = $eye_point

var shapes = {}

@export var male := false

@export var color_palette_array : Array

var walking_space_vector : Vector2

var looked_array : Array

#func _ready():
	#change_shape("Male", int(male))
	#update_clothes_shapes()
	#if !Engine.is_editor_hint():
		#anim_tree.active = true
		#anim_tree.set("parameters/blink/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

#func _process(_delta):
	#eyeL.look_at(eyepoint.global_position)
	#eyeR.look_at(eyepoint.global_position)
	#update_clothes_shapes()
	#if !Engine.is_editor_hint():
		#anim_tree.set("parameters/walking_space/blend_position", walking_space_vector)

#func update_clothes_shapes():
	#for i in range(body.get_blend_shape_count() - 1):
		#shapes[body.mesh.get_blend_shape_name(i)] = body.get_blend_shape_value(i)
		#for clothes in get_tree().get_nodes_in_group("clothes"):
			#if body.get_parent().get_children().has(clothes):
				#
				#clothes.set_blend_shape_value(i,body.get_blend_shape_value(i))
#
#func change_shape(shape : String, amount : float):
	#var n = "blend_shapes/"
	#body.set(n + shape, amount)
	#update_clothes_shapes()

#func randomize_color_palette():
	#randomize()
	#var color_array = color_palette_array.pick_random()
	#print("new colors: ", str(color_array))
	#print(body.get_surface_override_material(0).get_shader_parameter("skin_tone"))
	#body.get_surface_override_material(0).set_shader_parameter("skin_tone", color_array[0])
	#body.get_surface_override_material(0).set_shader_parameter("skin_tone2", color_array[1])

#func play(animname:String):
	#anim.play(animname)
