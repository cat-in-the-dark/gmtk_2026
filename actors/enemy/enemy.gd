extends Fighter

@export var attack_range := 1.7
@export var attack_charge_duration := 0.5
@export var domino_area_scale := 1.5
@export var stun_duration := 1.5
@export var can_dash := false
@export_range(0.0, 1.0, 0.05) var dash_chance := 0.3
@export var dash_speed := 12.0
@export_range(0.05, 1.0, 0.01) var dash_duration := 0.18
@export var dash_cooldown := 2.5
@export var dash_cooldown_jitter := 0.75

var target: Node3D
var is_charging_attack := false
var attack_charge_time_left := 0.0
var stun_time_left := 0.0
var is_dashing := false
var dash_time_left := 0.0
var dash_cooldown_left := 0.0
var dash_direction := Vector3.ZERO
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
	var stunned_animation := model_animations.get_animation(&"stunned")
	if stunned_animation != null:
		stunned_animation.loop_mode = Animation.LOOP_LINEAR
	var charge_animation := model_animations.get_animation(&"attack_charge")
	if charge_animation != null:
		charge_animation.loop_mode = Animation.LOOP_NONE
	target = get_tree().get_first_node_in_group("player") as Node3D


func _physics_process(delta: float) -> void:
	_update_stun(delta)
	_update_dash_before_movement(delta)
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D
	if not is_on_floor():
		if is_dashing:
			_finish_dash()
		if is_charging_attack:
			_cancel_attack_charge()
		move_direction = Vector3.ZERO
	elif is_charging_attack:
		move_direction = Vector3.ZERO
		_update_attack_charge(delta)
	elif target != null and not is_busy():
		var offset := target.global_position - global_position
		offset.y = 0.0
		if offset.length() <= attack_range:
			move_direction = Vector3.ZERO
			face_direction(offset)
			_start_attack_charge()
		elif _try_start_dash(offset):
			move_direction = Vector3.ZERO
		else:
			move_direction = offset.normalized()
	else:
		move_direction = Vector3.ZERO
	super._physics_process(delta)
	if is_dashing and not is_on_floor():
		_finish_dash()
	else:
		_update_dash_after_movement(delta)
	if domino_knockback_active:
		_spread_domino_knockback()
		if not _is_knocked_back():
			domino_knockback_active = false
			domino_hit_bodies.clear()
	_update_stunned_animation()


func is_busy() -> bool:
	return (
		super.is_busy()
		or is_charging_attack
		or stun_time_left > 0.0
		or is_dashing
	)


func receive_hit(attacker_position: Vector3, attack_name: StringName = &"") -> void:
	if is_dashing:
		_finish_dash()
	if is_charging_attack:
		_cancel_attack_charge()
	var is_strong_attack := attack_name == &"attack3"
	if is_strong_attack:
		_start_domino_knockback(attacker_position)
	else:
		_start_hit(attacker_position, false, true)


func receive_domino_hit(attacker_position: Vector3, source_enemy: Node) -> void:
	if is_dashing:
		_finish_dash()
	if is_charging_attack:
		_cancel_attack_charge()
	_start_domino_knockback(attacker_position, source_enemy, false)


func _start_domino_knockback(
	attacker_position: Vector3,
	source_enemy: Node = null,
	reset_domino_chain := true
) -> void:
	stun_time_left = stun_duration
	domino_knockback_active = true
	if reset_domino_chain:
		domino_hit_bodies.clear()
	if source_enemy != null:
		domino_hit_bodies[source_enemy.get_instance_id()] = true
	_start_hit(attacker_position, true, true, true)


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


func _start_attack_charge() -> void:
	is_charging_attack = true
	attack_charge_time_left = attack_charge_duration
	model_animations.play(&"attack_charge")


func _update_attack_charge(delta: float) -> void:
	attack_charge_time_left = maxf(attack_charge_time_left - delta, 0.0)
	if attack_charge_time_left > 0.0:
		return
	is_charging_attack = false
	if not start_attack(&"attack1"):
		_cancel_attack_charge()


func _cancel_attack_charge() -> void:
	is_charging_attack = false
	attack_charge_time_left = 0.0


func _try_start_dash(offset: Vector3) -> bool:
	if not can_dash or dash_cooldown_left > 0.0:
		return false
	dash_cooldown_left = maxf(
		dash_cooldown + randf_range(-dash_cooldown_jitter, dash_cooldown_jitter),
		0.1
	)
	if randf() >= dash_chance:
		return false
	dash_direction = offset.normalized()
	if dash_direction == Vector3.ZERO:
		dash_direction = Vector3.RIGHT.rotated(Vector3.UP, rotation.y)
	is_dashing = true
	dash_time_left = dash_duration
	forced_movement_active = true
	forced_movement_velocity = dash_direction * dash_speed
	face_direction(dash_direction)
	model_animations.play(&"stunned")
	return true


func _update_dash_before_movement(delta: float) -> void:
	if is_dashing:
		var dash_frame_fraction := minf(dash_time_left / delta, 1.0)
		forced_movement_velocity = dash_direction * dash_speed * dash_frame_fraction
	else:
		dash_cooldown_left = maxf(dash_cooldown_left - delta, 0.0)


func _update_dash_after_movement(delta: float) -> void:
	if not is_dashing:
		return
	dash_time_left = maxf(dash_time_left - delta, 0.0)
	if dash_time_left <= 0.0:
		_finish_dash()


func _finish_dash() -> void:
	is_dashing = false
	dash_time_left = 0.0
	dash_direction = Vector3.ZERO
	forced_movement_active = false
	forced_movement_velocity = Vector3.ZERO
	velocity.x = 0.0
	velocity.z = 0.0
	if stun_time_left <= 0.0 and model_animations.assigned_animation == &"stunned":
		model_animations.play(&"idle")


func _update_stun(delta: float) -> void:
	if stun_time_left <= 0.0:
		return
	stun_time_left = maxf(stun_time_left - delta, 0.0)
	if stun_time_left <= 0.0 and model_animations.assigned_animation == &"stunned":
		model_animations.play(&"idle")


func _update_stunned_animation() -> void:
	if (
		stun_time_left <= 0.0
		or is_hit
		or (
			model_animations.assigned_animation == &"stunned"
			and model_animations.is_playing()
		)
	):
		return
	model_animations.play(&"stunned")


func _can_attack_body(body: Node) -> bool:
	return not body.is_in_group(&"enemies")
