class_name Enemy
extends Fighter

@export var config: EnemyConfig

var target: Node3D
var can_dash := false
var attack_charge_time_left := 0.0
var stun_time_left := 0.0
var dash_time_left := 0.0
var dash_cooldown_left := 0.0
var dash_direction := Vector3.ZERO
var domino_knockback_active := false
var domino_knockback_strength := 0.0
var domino_hit_bodies: Dictionary = {}
var domino_proximity_shape: CapsuleShape3D
var _wave_configuration_applied := false

@onready var body_collision_shape: CollisionShape3D = $BodyCollision


func _ready() -> void:
	if config != null:
		stats = config.fighter_stats
	super._ready()
	if not configuration_valid or not _validate_enemy_configuration():
		return
	if not _wave_configuration_applied:
		can_dash = config.can_dash_by_default
	var body_capsule := body_collision_shape.shape as CapsuleShape3D
	domino_proximity_shape = body_capsule.duplicate() as CapsuleShape3D
	domino_proximity_shape.radius *= config.domino_area_scale
	domino_proximity_shape.height *= config.domino_area_scale
	target = get_tree().get_first_node_in_group("player") as Node3D


func configure(enemy_config: EnemyConfig, dash_enabled: bool) -> bool:
	if is_node_ready():
		push_error("Enemy configuration must be assigned before adding it to the scene tree")
		return false
	if enemy_config == null or not enemy_config.get_validation_errors().is_empty():
		return false
	config = enemy_config
	stats = config.fighter_stats
	can_dash = config.can_dash_by_default or dash_enabled
	_wave_configuration_applied = true
	return true


func _validate_enemy_configuration() -> bool:
	var errors := PackedStringArray()
	if config == null:
		errors.append("config cannot be null")
	else:
		for config_error in config.get_validation_errors():
			errors.append("config: %s" % config_error)
		if config.attack != null:
			for scene_error in _get_attack_scene_errors(config.attack):
				errors.append("attack '%s': %s" % [config.attack.animation_name, scene_error])
	return _report_configuration_errors("Enemy", errors)


func _physics_process(delta: float) -> void:
	if not configuration_valid:
		return
	_update_stun(delta)
	_update_dash_before_movement(delta)
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D
	if not is_on_floor():
		move_direction = Vector3.ZERO
		if state == FighterState.DASH or state == FighterState.CHARGE:
			_change_state(FighterState.IDLE)
	elif state == FighterState.CHARGE:
		move_direction = Vector3.ZERO
		_update_attack_charge(delta)
	elif target != null and not is_busy():
		var offset := target.global_position - global_position
		offset.y = 0.0
		if offset.length() <= config.attack_range:
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
	if state == FighterState.DASH and not is_on_floor():
		_change_state(FighterState.IDLE)
	else:
		_update_dash_after_movement(delta)
	if domino_knockback_active:
		_spread_domino_knockback()
		if not _is_knocked_back():
			domino_knockback_active = false
			domino_knockback_strength = 0.0
			domino_hit_bodies.clear()


func receive_hit(attacker_position: Vector3, attack: AttackDefinition = null) -> void:
	if is_eliminated:
		return
	var is_strong_attack := attack != null and attack.is_domino_attack
	if is_strong_attack:
		_start_domino_knockback(attacker_position, null, true, attack.knockback_strength)
	else:
		_start_hit(attacker_position, false, true)


func receive_domino_hit(
	attacker_position: Vector3, source_enemy: Node, knockback_strength: float
) -> void:
	if is_eliminated:
		return
	_start_domino_knockback(attacker_position, source_enemy, false, knockback_strength)


func _start_domino_knockback(
	attacker_position: Vector3,
	source_enemy: Node = null,
	reset_domino_chain := true,
	knockback_strength := -1.0
) -> void:
	stun_time_left = config.stun_duration
	domino_knockback_active = true
	domino_knockback_strength = knockback_strength
	if domino_knockback_strength < 0.0:
		domino_knockback_strength = stats.default_knockback_strength
	if reset_domino_chain:
		domino_hit_bodies.clear()
	if source_enemy != null:
		domino_hit_bodies[source_enemy.get_instance_id()] = true
	_start_hit(attacker_position, true, true, true, domino_knockback_strength)


func _spread_domino_knockback() -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = domino_proximity_shape
	query.transform = body_collision_shape.global_transform
	query.collision_mask = CollisionLayers3D.FIGHTER_BODY
	query.exclude = [get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var enemy := hit.get("collider") as Enemy
		if enemy == null:
			continue
		var body_id := enemy.get_instance_id()
		if domino_hit_bodies.has(body_id):
			continue
		domino_hit_bodies[body_id] = true
		enemy.receive_domino_hit(global_position, self, domino_knockback_strength)


func _start_attack_charge() -> void:
	attack_charge_time_left = config.attack_charge_duration
	_change_state(FighterState.CHARGE)


func _update_attack_charge(delta: float) -> void:
	attack_charge_time_left = maxf(attack_charge_time_left - delta, 0.0)
	if attack_charge_time_left > 0.0:
		return
	if not start_attack(config.attack):
		_cancel_attack_charge()


func _cancel_attack_charge() -> void:
	attack_charge_time_left = 0.0
	if state == FighterState.CHARGE:
		_change_state(_locomotion_state())


func _try_start_dash(offset: Vector3) -> bool:
	if not can_dash or dash_cooldown_left > 0.0:
		return false
	dash_cooldown_left = maxf(
		stats.dash_cooldown
		+ randf_range(-config.dash_cooldown_jitter, config.dash_cooldown_jitter),
		0.1
	)
	if randf() >= config.dash_chance:
		return false
	dash_direction = offset.normalized()
	if dash_direction == Vector3.ZERO:
		dash_direction = Vector3.RIGHT.rotated(Vector3.UP, rotation.y)
	face_direction(dash_direction)
	return _change_state(FighterState.DASH)


func _update_dash_before_movement(delta: float) -> void:
	if state == FighterState.DASH:
		var dash_frame_fraction := minf(dash_time_left / delta, 1.0)
		forced_movement_velocity = dash_direction * stats.dash_speed * dash_frame_fraction
	else:
		dash_cooldown_left = maxf(dash_cooldown_left - delta, 0.0)


func _update_dash_after_movement(delta: float) -> void:
	if state != FighterState.DASH:
		return
	dash_time_left = maxf(dash_time_left - delta, 0.0)
	if dash_time_left <= 0.0:
		_change_state(_locomotion_state())


func _update_stun(delta: float) -> void:
	if stun_time_left <= 0.0:
		return
	stun_time_left = maxf(stun_time_left - delta, 0.0)
	if stun_time_left <= 0.0 and state == FighterState.STUNNED:
		if _is_knocked_back():
			_change_state(FighterState.KNOCKBACK)
		else:
			_change_state(_locomotion_state())


func _state_after_hit() -> FighterState:
	if stun_time_left > 0.0:
		return FighterState.STUNNED
	return super._state_after_hit()


func _on_state_entered(next_state: FighterState, previous_state: FighterState) -> void:
	super._on_state_entered(next_state, previous_state)
	if next_state == FighterState.DASH:
		dash_time_left = stats.dash_duration
		forced_movement_active = true
		forced_movement_velocity = dash_direction * stats.dash_speed


func _on_state_exited(previous_state: FighterState, next_state: FighterState) -> void:
	super._on_state_exited(previous_state, next_state)
	match previous_state:
		FighterState.DASH:
			dash_time_left = 0.0
			dash_direction = Vector3.ZERO
			forced_movement_active = false
			forced_movement_velocity = Vector3.ZERO
			velocity.x = 0.0
			velocity.z = 0.0
		FighterState.CHARGE:
			attack_charge_time_left = 0.0
