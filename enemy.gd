extends Fighter

@export var attack_range := 1.7
@export var attack_jitter_min := 0.2
@export var attack_jitter_max := 0.55
@export var domino_area_scale := 1.5

var target: Node3D
var attack_at := -1.0
var domino_knockback_active := false
var domino_hit_bodies: Dictionary = {}
var domino_proximity_shape: CapsuleShape3D

@onready var body_collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	super._ready()
	var body_capsule := body_collision_shape.shape as CapsuleShape3D
	domino_proximity_shape = body_capsule.duplicate() as CapsuleShape3D
	domino_proximity_shape.radius *= domino_area_scale
	domino_proximity_shape.height *= domino_area_scale
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
	if domino_knockback_active:
		_spread_domino_knockback()
		if not _is_knocked_back():
			domino_knockback_active = false
			domino_hit_bodies.clear()


func receive_hit(attacker_position: Vector3, attack_name: StringName = &"") -> void:
	var is_strong_attack := attack_name == &"attack3"
	if is_strong_attack:
		_start_domino_knockback(attacker_position)
	else:
		_start_hit(attacker_position, false, true)
	attack_at = -1.0


func receive_domino_hit(attacker_position: Vector3, source_enemy: Node) -> void:
	if domino_knockback_active:
		return
	_start_domino_knockback(attacker_position, source_enemy)


func _start_domino_knockback(attacker_position: Vector3, source_enemy: Node = null) -> void:
	domino_knockback_active = true
	domino_hit_bodies.clear()
	if source_enemy != null:
		domino_hit_bodies[source_enemy.get_instance_id()] = true
	_start_hit(attacker_position, true, true, true)
	attack_at = -1.0


func _spread_domino_knockback() -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = domino_proximity_shape
	query.transform = body_collision_shape.global_transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var body := hit.get("collider") as Node
		if body == null or not body.is_in_group(&"enemies"):
			continue
		var body_id := body.get_instance_id()
		if domino_hit_bodies.has(body_id):
			continue
		domino_hit_bodies[body_id] = true
		if body.has_method("receive_domino_hit"):
			body.receive_domino_hit(global_position, self)


func _can_attack_body(body: Node) -> bool:
	return not body.is_in_group(&"enemies")


func _on_attack_interrupted() -> void:
	attack_at = -1.0
