@tool
extends MeshInstance3D

@onready var coll = $StaticBody3D/CollisionShape3D
@export var colratio = 0.1
@export var Height = 20

var img = Image.new()
var shape = HeightMapShape3D.new()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	coll.shape = shape
	update_terrain()

func update_terrain():
	material_override.set("shader_param/height", Height)
	img.load("res://heightmapper-1743978607441.png")
	img.convert(Image.FORMAT_RF)
	img.resize(img.get_width()*colratio, img.get_height()*colratio)
	var data = img.get_data().to_float32_array()
	for i in range(0, data.size()):
		data[i] *= Height
	
	shape.map_width = img.get_width()
	shape.map_depth = img.get_height()  # Fixed: was map_width instead of map_depth
	shape.map_data = data
	coll.shape = shape
	coll.scale = Vector3(scale.x*1.05,1,scale.z*2.2)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		global_position.x = EditorInterface.get_editor_viewport_3d(0).get_camera_3d().global_position.x
		global_position.z = EditorInterface.get_editor_viewport_3d(0).get_camera_3d().global_position.z
	else :
			global_position.x = get_viewport().get_camera_3d().global_position.x
			global_position.z = get_viewport().get_camera_3d().global_position.z
