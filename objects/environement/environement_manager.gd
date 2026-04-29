@tool
extends Node3D

@export var envi: WorldEnvironment
@export var sun: DirectionalLight3D

@onready var anim = $AnimationPlayer

@export var in_water = false:
	set(i):
		in_water = i
		if i:
			anim.play("water")
		else:
			anim.play("air")

@export_range(0,100, 1) var fog: float = 8.0:
	set(f):
		fog = f
		update_weather()

@export var wind : float = 5.0:
	set(w):
		wind = w
		RenderingServer.global_shader_parameter_set("windspeed", wind)


func _ready() -> void:
	update_weather()

func update_weather():
	var f = remap(fog,0,100,0,0.005)
	#envi.environment.fog_density = f
	print(envi.environment.fog_density)
