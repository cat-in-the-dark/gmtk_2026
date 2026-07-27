extends Fighter

@export var attack_sequence: AttackSequence

var combo_step := 0
var attack_buffered := false
var dash_time_left := 0.0
var dash_cooldown_left := 0.0
var dash_direction := Vector3.ZERO


func _ready() -> void:
	super._ready()
	if not configuration_valid or not _validate_player_configuration():
		return
	attack_finished.connect(_on_attack_finished)


func _validate_player_configuration() -> bool:
	var errors := PackedStringArray()
	if attack_sequence == null:
		errors.append("attack_sequence cannot be null")
	else:
		for sequence_error in attack_sequence.get_validation_errors():
			errors.append("attack_sequence: %s" % sequence_error)
		var validated_attacks := {}
		for attack in attack_sequence.attacks:
			if attack == null or validated_attacks.has(attack.get_instance_id()):
				continue
			validated_attacks[attack.get_instance_id()] = true
			for scene_error in _get_attack_scene_errors(attack):
				errors.append("attack '%s': %s" % [attack.animation_name, scene_error])
	return _report_configuration_errors("Player", errors)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"attack") and not event.is_echo():
		_request_attack()
	elif event.is_action_pressed(&"dash") and not event.is_echo():
		_request_dash()


func _physics_process(delta: float) -> void:
	if not configuration_valid:
		return
	move_direction = _get_input_direction()
	if state == FighterState.DASH:
		var dash_frame_fraction := minf(dash_time_left / delta, 1.0)
		forced_movement_velocity = dash_direction * stats.dash_speed * dash_frame_fraction
	else:
		dash_cooldown_left = maxf(dash_cooldown_left - delta, 0.0)
	super._physics_process(delta)
	if state == FighterState.DASH:
		dash_time_left = maxf(dash_time_left - delta, 0.0)
		if dash_time_left <= 0.0:
			_change_state(_locomotion_state())


func _request_attack() -> void:
	if state == FighterState.IDLE or state == FighterState.MOVE:
		_start_next_attack()
	elif (
		state == FighterState.ATTACK
		and not attack_buffered
		and combo_step < attack_sequence.attacks.size()
		and _is_inside_combo_window()
	):
		attack_buffered = true


func _request_dash() -> void:
	if is_busy() or not is_on_floor() or dash_cooldown_left > 0.0:
		return
	var direction := _get_input_direction()
	if direction == Vector3.ZERO:
		direction = Vector3.RIGHT.rotated(Vector3.UP, rotation.y)
	dash_direction = direction
	_change_state(FighterState.DASH)


func _start_next_attack() -> void:
	if combo_step >= attack_sequence.attacks.size():
		return
	if start_attack(attack_sequence.attacks[combo_step]):
		combo_step += 1
		attack_buffered = false


func _on_attack_finished() -> void:
	if attack_buffered and combo_step < attack_sequence.attacks.size():
		_start_next_attack()
	else:
		combo_step = 0
		attack_buffered = false


func _on_attack_interrupted() -> void:
	combo_step = 0
	attack_buffered = false


func _on_state_entered(next_state: FighterState, previous_state: FighterState) -> void:
	super._on_state_entered(next_state, previous_state)
	if next_state == FighterState.DASH:
		dash_time_left = stats.dash_duration
		forced_movement_active = true
		forced_movement_velocity = dash_direction * stats.dash_speed


func _on_state_exited(previous_state: FighterState, next_state: FighterState) -> void:
	super._on_state_exited(previous_state, next_state)
	if previous_state == FighterState.DASH:
		dash_time_left = 0.0
		dash_cooldown_left = stats.dash_cooldown
		dash_direction = Vector3.ZERO
		forced_movement_active = false
		forced_movement_velocity = Vector3.ZERO
		velocity.x = 0.0
		velocity.z = 0.0


func _is_inside_combo_window() -> bool:
	if state != FighterState.ATTACK or active_attack == null:
		return false
	var animation := model_animations.get_animation(active_attack.animation_name)
	if (
		animation == null
		or animation_state_machine == null
		or animation_state_machine.get_current_node() != active_attack.animation_name
	):
		return false
	return (
		animation_state_machine.get_current_play_position()
		>= maxf(animation.length - active_attack.combo_buffer_window, 0.0)
	)


func _get_input_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return Vector3(input.x, 0.0, input.y).normalized()
