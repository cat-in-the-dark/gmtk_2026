class_name Fighter
extends CharacterBody3D

signal attack_finished
signal attack_landed(target: Node3D)
signal eliminated
signal state_changed(previous_state: int, current_state: int)

enum Faction {
	NEUTRAL,
	PLAYER,
	ENEMY,
}

enum FighterState {
	IDLE,
	MOVE,
	ATTACK,
	HIT,
	DASH,
	CHARGE,
	STUNNED,
	KNOCKBACK,
	ELIMINATED,
}

const ALLOWED_STATE_TRANSITIONS: Dictionary = {
	FighterState.IDLE: [
		FighterState.MOVE,
		FighterState.ATTACK,
		FighterState.HIT,
		FighterState.DASH,
		FighterState.CHARGE,
		FighterState.STUNNED,
		FighterState.KNOCKBACK,
		FighterState.ELIMINATED,
	],
	FighterState.MOVE: [
		FighterState.IDLE,
		FighterState.ATTACK,
		FighterState.HIT,
		FighterState.DASH,
		FighterState.CHARGE,
		FighterState.STUNNED,
		FighterState.KNOCKBACK,
		FighterState.ELIMINATED,
	],
	FighterState.ATTACK: [
		FighterState.IDLE,
		FighterState.MOVE,
		FighterState.HIT,
		FighterState.ELIMINATED,
	],
	FighterState.HIT: [
		FighterState.IDLE,
		FighterState.MOVE,
		FighterState.STUNNED,
		FighterState.KNOCKBACK,
		FighterState.ELIMINATED,
	],
	FighterState.DASH: [
		FighterState.IDLE,
		FighterState.MOVE,
		FighterState.HIT,
		FighterState.STUNNED,
		FighterState.ELIMINATED,
	],
	FighterState.CHARGE: [
		FighterState.IDLE,
		FighterState.MOVE,
		FighterState.ATTACK,
		FighterState.HIT,
		FighterState.ELIMINATED,
	],
	FighterState.STUNNED: [
		FighterState.IDLE,
		FighterState.MOVE,
		FighterState.HIT,
		FighterState.KNOCKBACK,
		FighterState.ELIMINATED,
	],
	FighterState.KNOCKBACK: [
		FighterState.IDLE,
		FighterState.MOVE,
		FighterState.HIT,
		FighterState.STUNNED,
		FighterState.ELIMINATED,
	],
	FighterState.ELIMINATED: [],
}

class Leg:
	var root: Node3D
	var mesh: MeshInstance3D
	var boot: Node3D
	var plant: Node3D
	var mesh_y_bounds: Vector2
	var home_offset: Vector3
	var boot_to_plant: Vector3
	var target: Vector3
	var from: Vector3
	var to: Vector3
	var progress := 1.0

	func _init(
		root_node: Node3D,
		mesh_node: MeshInstance3D,
		boot_node: Node3D,
		plant_node: Node3D
	) -> void:
		root = root_node
		mesh = mesh_node
		boot = boot_node
		plant = plant_node
		mesh_y_bounds = _get_mesh_y_bounds(mesh)
		home_offset = plant.global_position - root.global_position
		boot_to_plant = plant.global_position - boot.global_position
		target = plant.global_position
		from = target
		to = target


	static func _get_mesh_y_bounds(mesh_node: MeshInstance3D) -> Vector2:
		var aabb := mesh_node.get_aabb()
		return Vector2(aabb.position.y, aabb.end.y)


@export var stats: FighterStats
@export var faction: Faction = Faction.NEUTRAL

var move_direction := Vector3.ZERO
var configuration_valid := true
var state: FighterState:
	get:
		return _state
var is_attacking: bool:
	get:
		return _state == FighterState.ATTACK
var is_hit: bool:
	get:
		return _state == FighterState.HIT
var is_eliminated: bool:
	get:
		return _state == FighterState.ELIMINATED
var active_attack: AttackDefinition
var knockback_velocity := Vector3.ZERO
var forced_movement_active := false
var forced_movement_velocity := Vector3.ZERO
var bounce_time_left := 0.0
var bounce_duration := 0.0
var skin_rest_position := Vector3.ZERO
var next_left := true
var turning_leg: Leg
var turn_start_yaw := 0.0
var turn_target_yaw := 0.0
var hit_bodies: Dictionary = {}
var animation_state_machine: AnimationNodeStateMachinePlayback
var _state := FighterState.IDLE

@onready var skin: Node3D = $skin3/blockbench_export
@onready var model_animations: AnimationPlayer = skin.get_node("AnimationPlayer")
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var attack_window_player: AnimationPlayer = $AttackWindowPlayer
@onready var hand_hitboxes: Array[AttackHitbox] = [
	skin.get_node("root/arm_left/hand_left/hand_left_mesh/LeftHandHitbox"),
	skin.get_node("root/arm_right/hand_right/hand_right_mesh/RightHandHitbox")
]
@onready var left_leg := Leg.new(
	skin.get_node("root/left_leg"),
	skin.get_node("root/left_leg/left_leg_mesh"),
	skin.get_node("root/left_leg/left_boot"),
	skin.get_node("root/left_leg/left_boot/ik_locator_left_boot2")
)
@onready var right_leg := Leg.new(
	skin.get_node("root/right_leg"),
	skin.get_node("root/right_leg/right_leg_mesh"),
	skin.get_node("root/right_leg/right_boot"),
	skin.get_node("root/right_leg/right_boot/ik_locator_right_boot2")
)

func _ready() -> void:
	if not _validate_fighter_configuration():
		return
	skin_rest_position = skin.position
	animation_tree.callback_mode_process = (
		AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	)
	animation_tree.active = true
	animation_state_machine = (
		animation_tree.get(&"parameters/playback") as AnimationNodeStateMachinePlayback
	)
	if animation_state_machine == null:
		push_error("Fighter AnimationTree must use AnimationNodeStateMachine")
	else:
		animation_tree.animation_finished.connect(_on_presentation_animation_finished)
	for hitbox in hand_hitboxes:
		hitbox.configure(self)
	_close_attack_hitboxes()
	_update_leg(left_leg)
	_update_leg(right_leg)
	_play_presentation_state(_presentation_state_for(_state), true)


func _validate_fighter_configuration() -> bool:
	var errors := PackedStringArray()
	if stats == null:
		errors.append("stats cannot be null")
	else:
		for stats_error in stats.get_validation_errors():
			errors.append("stats: %s" % stats_error)
	return _report_configuration_errors("Fighter", errors)


func _get_attack_scene_errors(attack: AttackDefinition) -> PackedStringArray:
	var errors := attack.get_validation_errors()
	if not model_animations.has_animation(attack.animation_name):
		errors.append("model animation '%s' does not exist" % attack.animation_name)
	if not attack_window_player.has_animation(attack.hitbox_profile):
		errors.append("hitbox profile '%s' does not exist" % attack.hitbox_profile)
	var state_machine := animation_tree.tree_root as AnimationNodeStateMachine
	if state_machine == null or not state_machine.has_node(attack.animation_name):
		errors.append("AnimationTree state '%s' does not exist" % attack.animation_name)
	return errors


func _report_configuration_errors(
	configuration_name: String, errors: PackedStringArray
) -> bool:
	if errors.is_empty():
		return true
	configuration_valid = false
	set_physics_process(false)
	set_process_unhandled_input(false)
	for configuration_error in errors:
		push_error("%s configuration: %s" % [configuration_name, configuration_error])
	return false


func _physics_process(delta: float) -> void:
	if not configuration_valid or is_eliminated:
		return
	_update_locomotion_state()
	var was_on_floor := is_on_floor()
	var is_moving := move_direction != Vector3.ZERO
	if is_attacking and is_moving:
		turning_leg = null
		face_direction(move_direction)
	var was_knocked_back := _is_knocked_back()
	var vertical_velocity := velocity.y
	if was_on_floor:
		vertical_velocity = 0.0
	else:
		vertical_velocity += get_gravity().y * stats.gravity_scale * delta
	var controlled_velocity := Vector3.ZERO
	if forced_movement_active:
		controlled_velocity = forced_movement_velocity
	elif not is_busy():
		if was_on_floor:
			controlled_velocity = move_direction * stats.move_speed
		else:
			controlled_velocity = Vector3(velocity.x, 0.0, velocity.z)
	velocity = controlled_velocity + knockback_velocity
	velocity.y = vertical_velocity
	move_and_slide()
	if _check_elimination_collision():
		return
	knockback_velocity = knockback_velocity.move_toward(
		Vector3.ZERO, stats.knockback_drag * delta
	)
	_update_knockback_bounce(delta)
	if _state == FighterState.KNOCKBACK and not _is_knocked_back():
		_change_state(_locomotion_state())
	if (
		was_knocked_back
		or _is_knocked_back()
		or forced_movement_active
		or not was_on_floor
		or not is_on_floor()
	):
		_sync_feet_to_body()
	if is_moving and not is_busy() and not forced_movement_active and is_on_floor():
		_try_start_step(move_direction)
	_update_leg_step(left_leg, delta)
	_update_leg_step(right_leg, delta)
	_update_leg(left_leg)
	_update_leg(right_leg)


func is_busy() -> bool:
	return _state != FighterState.IDLE and _state != FighterState.MOVE


func _check_elimination_collision() -> bool:
	for collision_index in get_slide_collision_count():
		var collider := get_slide_collision(collision_index).get_collider() as Node
		if collider != null and collider.is_in_group(&"kill_floor"):
			if _change_state(FighterState.ELIMINATED):
				eliminated.emit()
				_on_reached_kill_floor()
				return true
	return false


func _on_reached_kill_floor() -> void:
	queue_free()


func start_attack(attack: AttackDefinition) -> bool:
	if not _can_transition_to(FighterState.ATTACK) or not is_on_floor():
		return false
	if attack == null:
		push_error("Cannot start a null attack definition")
		return false
	var attack_errors := _get_attack_scene_errors(attack)
	if not attack_errors.is_empty():
		_report_configuration_errors("AttackDefinition '%s'" % attack.resource_path, attack_errors)
		return false
	active_attack = attack
	hit_bodies.clear()
	_close_attack_hitboxes()
	if not _change_state(FighterState.ATTACK):
		active_attack = null
		return false
	attack_window_player.play(attack.hitbox_profile)
	return true


func receive_hit(attacker_position: Vector3, attack: AttackDefinition = null) -> void:
	var knockback_strength := stats.default_knockback_strength
	if attack != null:
		knockback_strength = attack.knockback_strength
	_start_hit(attacker_position, knockback_strength > 0.0, false, false, knockback_strength)


func _start_hit(
	attacker_position: Vector3,
	should_knockback: bool,
	allow_restart := false,
	should_bounce := false,
	knockback_strength := -1.0
) -> void:
	if is_eliminated:
		return
	if (is_hit or _is_knocked_back()) and not allow_restart:
		return
	if is_attacking:
		_on_attack_interrupted()
	if should_knockback:
		var away := global_position - attacker_position
		away.y = 0.0
		if away.length_squared() < 0.001:
			away = Vector3.RIGHT.rotated(Vector3.UP, rotation.y)
		var resolved_strength := knockback_strength
		if resolved_strength < 0.0:
			resolved_strength = stats.default_knockback_strength
		knockback_velocity = away.normalized() * resolved_strength
	if should_bounce:
		bounce_duration = 0.5
		bounce_time_left = bounce_duration
	_change_state(FighterState.HIT, is_hit)


func face_direction(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return
	rotation.y = atan2(-direction.z, direction.x)


func _on_attack_interrupted() -> void:
	pass


func _on_presentation_animation_finished(animation_name: StringName) -> void:
	if is_attacking and active_attack != null and animation_name == active_attack.animation_name:
		_change_state(_locomotion_state())
		attack_finished.emit()
	elif is_hit and animation_name == &"hit":
		_change_state(_state_after_hit())


func _state_after_hit() -> FighterState:
	if _is_knocked_back():
		return FighterState.KNOCKBACK
	return _locomotion_state()


func _change_state(next_state: FighterState, allow_reenter := false) -> bool:
	if next_state == _state and not allow_reenter:
		return false
	if next_state != _state and not _can_transition_to(next_state):
		return false
	var previous_state := _state
	var previous_presentation := _presentation_state_for(previous_state)
	_exit_state(previous_state, next_state)
	_state = next_state
	_enter_state(next_state, previous_state)
	var next_presentation := _presentation_state_for(next_state)
	if allow_reenter or next_presentation != previous_presentation:
		_play_presentation_state(next_presentation, true)
	state_changed.emit(previous_state, next_state)
	return true


func _can_transition_to(next_state: FighterState) -> bool:
	if next_state == _state:
		return false
	var allowed_states: Array = ALLOWED_STATE_TRANSITIONS.get(_state, [])
	return allowed_states.has(next_state)


func _exit_state(previous_state: FighterState, next_state: FighterState) -> void:
	if previous_state == FighterState.ATTACK:
		_stop_attack_window()
		active_attack = null
	_on_state_exited(previous_state, next_state)


func _enter_state(next_state: FighterState, previous_state: FighterState) -> void:
	if next_state == FighterState.ELIMINATED:
		_stop_attack_window()
	_on_state_entered(next_state, previous_state)


func _on_state_exited(_previous_state: FighterState, _next_state: FighterState) -> void:
	pass


func _on_state_entered(_next_state: FighterState, _previous_state: FighterState) -> void:
	pass


func _update_locomotion_state() -> void:
	if _state == FighterState.IDLE or _state == FighterState.MOVE:
		_change_state(_locomotion_state())


func _locomotion_state() -> FighterState:
	if move_direction == Vector3.ZERO:
		return FighterState.IDLE
	return FighterState.MOVE


func _presentation_state_for(fighter_state: FighterState) -> StringName:
	var presentation_state := &"idle"
	match fighter_state:
		FighterState.IDLE:
			presentation_state = &"idle"
		FighterState.MOVE:
			presentation_state = &"move"
		FighterState.ATTACK:
			if active_attack != null:
				presentation_state = active_attack.animation_name
		FighterState.HIT, FighterState.KNOCKBACK:
			presentation_state = &"hit"
		FighterState.DASH, FighterState.STUNNED:
			presentation_state = &"stunned"
		FighterState.CHARGE:
			presentation_state = &"attack_charge"
	return presentation_state


func _play_presentation_state(presentation_state: StringName, restart: bool) -> void:
	if animation_state_machine == null or presentation_state.is_empty():
		return
	var state_machine := animation_tree.tree_root as AnimationNodeStateMachine
	if state_machine == null or not state_machine.has_node(presentation_state):
		push_error("Missing AnimationTree state: %s" % presentation_state)
		return
	if animation_state_machine.get_current_node() == presentation_state and not restart:
		return
	animation_state_machine.start(presentation_state, restart)


func try_attack_hurtbox(hurtbox: FighterHurtbox) -> void:
	if not is_attacking or hurtbox.fighter == null:
		return
	var target := hurtbox.fighter
	if (
		target == self
		or target.is_eliminated
		or faction == Faction.NEUTRAL
		or target.faction == faction
		or not _register_attack_target(target)
	):
		return
	target.receive_hit(global_position, active_attack)
	attack_landed.emit(target)


func try_attack_receiver(receiver: AttackReceiver3D) -> void:
	if not is_attacking or not _register_attack_target(receiver):
		return
	receiver.receive_attack(global_position, active_attack)
	attack_landed.emit(receiver)


func _register_attack_target(target: Node3D) -> bool:
	var target_id := target.get_instance_id()
	if hit_bodies.has(target_id):
		return false
	hit_bodies[target_id] = true
	return true


func _stop_attack_window() -> void:
	attack_window_player.stop()
	_close_attack_hitboxes()


func _close_attack_hitboxes() -> void:
	for hitbox in hand_hitboxes:
		hitbox.deactivate()


func _try_start_step(direction: Vector3) -> void:
	if left_leg.progress < 1.0 or right_leg.progress < 1.0:
		return
	var left_rest := (
		left_leg.root.global_position + left_leg.home_offset + direction * stats.step_forward
	)
	var right_rest := (
		right_leg.root.global_position + right_leg.home_offset + direction * stats.step_forward
	)
	var should_move_left := _flat_distance(left_leg.target, left_rest) > stats.step_distance
	var should_move_right := _flat_distance(right_leg.target, right_rest) > stats.step_distance
	if should_move_left and (next_left or not should_move_right):
		_start_step(left_leg, left_rest, direction)
		next_left = false
	elif should_move_right:
		_start_step(right_leg, right_rest, direction)
		next_left = true


func _start_step(leg: Leg, destination: Vector3, direction: Vector3) -> void:
	leg.from = leg.target
	leg.to = destination
	leg.progress = 0.0
	turning_leg = leg
	turn_start_yaw = rotation.y
	turn_target_yaw = atan2(-direction.z, direction.x)


func _update_leg_step(leg: Leg, delta: float) -> void:
	if leg.progress < 1.0:
		leg.progress = minf(leg.progress + delta / stats.step_duration, 1.0)
		leg.target = leg.from.lerp(leg.to, leg.progress)
		leg.target.y += sin(leg.progress * PI) * stats.step_height
		_update_turn(leg)
	leg.boot.global_position = leg.target - leg.boot_to_plant


func _update_turn(leg: Leg) -> void:
	if leg != turning_leg:
		return
	var turn_progress := 1.0 - (1.0 - leg.progress) * (1.0 - leg.progress)
	rotation.y = lerp_angle(turn_start_yaw, turn_target_yaw, turn_progress)
	if leg.progress >= 1.0:
		turning_leg = null


func _update_leg(leg: Leg) -> void:
	var hip_position := leg.root.global_position
	var hip_to_foot := leg.target - hip_position
	var length := maxf(hip_to_foot.length(), 0.001)
	var mesh_height := maxf(leg.mesh_y_bounds.y - leg.mesh_y_bounds.x, 0.001)
	var scale_y := length / mesh_height
	var mesh_up := -hip_to_foot / length
	var leg_basis := Basis(Quaternion(Vector3.UP, mesh_up)).scaled(Vector3(1.0, scale_y, 1.0))
	var mesh_origin := hip_position - mesh_up * leg.mesh_y_bounds.y * scale_y
	var global_mesh_transform := Transform3D(leg_basis, mesh_origin)
	leg.mesh.transform = leg.root.global_transform.affine_inverse() * global_mesh_transform


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _is_knocked_back() -> bool:
	return knockback_velocity.length_squared() > 0.001 or bounce_time_left > 0.0


func _sync_feet_to_body() -> void:
	for leg in [left_leg, right_leg]:
		leg.target = leg.boot.global_position + leg.boot_to_plant
		leg.from = leg.target
		leg.to = leg.target
		leg.progress = 1.0


func _update_knockback_bounce(delta: float) -> void:
	if bounce_time_left <= 0.0:
		return
	bounce_time_left = maxf(bounce_time_left - delta, 0.0)
	var progress := 1.0 - bounce_time_left / bounce_duration
	var height := absf(sin(progress * TAU)) * lerpf(0.28, 0.08, progress)
	skin.position = skin_rest_position + Vector3.UP * height
	if bounce_time_left <= 0.0:
		skin.position = skin_rest_position
