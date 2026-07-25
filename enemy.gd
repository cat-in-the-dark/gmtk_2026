extends Fighter

@export var attack_range := 1.7
@export var attack_jitter_min := 0.2
@export var attack_jitter_max := 0.55

var target: Node3D
var attack_at := -1.0


func _ready() -> void:
	super._ready()
	target = get_tree().get_first_node_in_group("player") as Node3D


func _physics_process(delta: float) -> void:
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D
	if target != null and not is_busy():
		var offset := target.global_position - global_position
		offset.y = 0.0
		if offset.length() > attack_range:
			move_direction = offset.normalized()
			attack_at = -1.0
		else:
			move_direction = Vector3.ZERO
			face_direction(offset)
			if attack_at < 0.0:
				attack_at = Time.get_ticks_msec() * 0.001 + randf_range(
					attack_jitter_min, attack_jitter_max
				)
			elif Time.get_ticks_msec() * 0.001 >= attack_at:
				attack_at = -1.0
				start_attack(&"attack1")
	else:
		move_direction = Vector3.ZERO
	super._physics_process(delta)


func receive_hit(attacker_position: Vector3, attack_name: StringName = &"") -> void:
	var is_strong_attack := attack_name == &"attack3"
	_start_hit(attacker_position, is_strong_attack, true, is_strong_attack)
	attack_at = -1.0


func _on_attack_interrupted() -> void:
	attack_at = -1.0
