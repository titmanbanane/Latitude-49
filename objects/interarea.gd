extends Area3D

signal interacted

@export var msg = ""

func interact():
	print(msg)
	emit_signal("interacted")
