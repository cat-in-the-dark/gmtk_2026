extends Camera3D

@export var target_group := &"player"
@export_range(0.1, 20.0, 0.1) var turn_speed := 2.5

var target: Node3D


func _ready() -> void:
	_find_target()


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		_find_target()
	if target == null:
		return
	var direction := target.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	var rotation_weight := 1.0 - exp(-turn_speed * delta)
	var next_rotation := global_rotation
	next_rotation.y = lerp_angle(next_rotation.y, target_yaw, rotation_weight)
	global_rotation = next_rotation


func _find_target() -> void:
	target = get_tree().get_first_node_in_group(target_group) as Node3D
