extends CharacterBody3D

@export var npc_name : String = ""

@onready var nav = $NavAgent
@onready var head
@onready var mesh = $human_mesh
@onready var arm_R_ik = $human_mesh/skeletton/GeneralSkeleton/arm_R_ik
@onready var arm_L_ik = $human_mesh/skeletton/GeneralSkeleton/arm_L_ik
@onready var leg_R_ik = $human_mesh/skeletton/GeneralSkeleton/leg_R_ik
@onready var leg_L_ik = $human_mesh/skeletton/GeneralSkeleton/leg_L_ik




@export var speed := 1.5
var accel := 10.0
var player : CharacterBody3D
var path_to_follow = []

var health : Dictionary = {
	"head" = 30,
	"torso" = 90,
	"stomac" = 80,
	"left_arm" = 50,
	"right_arm" = 50,
	"left_leg" = 50,
	"right_leg" = 50,
}

var type = "zombie"

var stats : Dictionary = {}

var schedule : Dictionary = {
	
}

enum {
	idle,
	walk,
	attack,
	flee,
	roam,
	interacting,
	folow,
	dead
}

signal state_changed(new_state)

var state = idle:
	set(new_state):
		state = new_state
		emit_signal("state_changed",new_state)

var look_dir := Vector2()

func _ready():
	player = get_tree().get_first_node_in_group("player")
	_setup_npc_sync()

func _setup_npc_sync() -> void:
	if not NetworkManager.is_online():
		return
	var sync := MultiplayerSynchronizer.new()
	sync.name = "_npc_sync"
	var cfg  := SceneReplicationConfig.new()
	cfg.add_property(NodePath(":global_position"))
	cfg.add_property(NodePath(":rotation"))
	cfg.add_property(NodePath(":state"))
	sync.replication_config = cfg
	add_child(sync)

func _process(_delta):
	# NPC AI runs only on the server in multiplayer.
	if NetworkManager.is_online() and not NetworkManager.is_server():
		return
	match state:
		idle, dead:
			velocity = Vector3(0,velocity.y,0)
		folow:
			update_target_location(player.global_position + (-player.global_transform.basis.z.normalized() * 1))
		attack:
			update_target_location(player.global_position + (-player.global_transform.basis.z.normalized() * 1))

func _physics_process(delta):
	# NPC physics driven by server only in multiplayer.
	if NetworkManager.is_online() and not NetworkManager.is_server():
		return
	var direction = Vector3()
	
	direction = nav.get_next_path_position() - global_position
	direction = direction.normalized()
	
	velocity = velocity.lerp(direction * speed, accel * delta)
	
	if velocity.length() > 0.2:
			look_dir = lerp(look_dir, Vector2(-velocity.z, -velocity.x), 3 * delta)
			mesh.walking_space_vector.y = look_dir.length()/1.8
			mesh.walking_space_vector.x = look_dir.angle()/10
			rotation.y = look_dir.angle()
	
	move_and_slide()

func health_check():
	if health["head"] <= 0 or health["torso"] <= 0:
		state = dead

## Called by GameManager.relay_npc_damage() on the server.
func take_damage_server(bone_group: String, amount: int) -> void:
	if not NetworkManager.is_server() and NetworkManager.is_online():
		return
	health[bone_group] -= amount
	health_check()

func update_target_location(target_move):
	nav.target_position = target_move

func _on_nav_agent_target_reached():
	if state == walk:
		state = idle

func _on_state_changed(new_state):
	match new_state:
		dead:
			$CollisionShape3D.disabled = true
			update_target_location(global_position)
			velocity = Vector3(0,velocity.y,0)
			$human_mesh/skeletton/GeneralSkeleton/PhysicalBoneSimulator3D.physical_bones_start_simulation()
			$AudioStreamPlayer3D.play()
			arm_L_ik.influence = 0
			arm_R_ik.influence = 0
			leg_L_ik.influence = 0
			leg_R_ik.influence = 0
