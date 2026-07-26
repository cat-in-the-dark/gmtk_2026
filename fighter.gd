class_name Fighter
extends CharacterBody3D

signal attack_finished


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


@export var move_speed := 6
@export var step_distance := 1.26
@export var step_forward := 0.66
@export var step_duration := 0.12
@export var step_height := 0.14
@export var gravity_scale := 1.0
@export var knockback_speed := 15.0
@export var knockback_drag := 22.0

var move_direction := Vector3.ZERO
var is_attacking := false
var is_hit := false
var active_attack := &"" as StringName
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

@onready var skin: Node3D = $skin3/blockbench_export
@onready var model_animations: AnimationPlayer = skin.get_node("AnimationPlayer")
@onready var hand_hit_areas: Array[Area3D] = [
	skin.get_node("root/arm_left/hand_left/hand_left_mesh/Area3D"),
	skin.get_node("root/arm_right/hand_right/hand_right_mesh/Area3D")
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
	skin_rest_position = skin.position
	model_animations.animation_finished.connect(_on_model_animation_finished)
	_update_leg(left_leg)
	_update_leg(right_leg)
	_play_idle_if_needed()


func _physics_process(delta: float) -> void:
	var was_on_floor := is_on_floor()
	var is_moving := move_direction != Vector3.ZERO
	if is_moving and not is_busy() and model_animations.current_animation == &"idle":
		model_animations.stop()
		model_animations.seek(0.0, true)
	var was_knocked_back := _is_knocked_back()
	var vertical_velocity := velocity.y
	if was_on_floor:
		vertical_velocity = 0.0
	else:
		vertical_velocity += get_gravity().y * gravity_scale * delta
	var controlled_velocity := Vector3.ZERO
	if forced_movement_active:
		controlled_velocity = forced_movement_velocity
	elif not is_busy():
		if was_on_floor:
			controlled_velocity = move_direction * move_speed
		else:
			controlled_velocity = Vector3(velocity.x, 0.0, velocity.z)
	velocity = controlled_velocity + knockback_velocity
	velocity.y = vertical_velocity
	move_and_slide()
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, knockback_drag * delta)
	_update_knockback_bounce(delta)
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
	_check_attack_hits()
	if not is_busy():
		_play_idle_if_needed()


func is_busy() -> bool:
	return is_attacking or is_hit or _is_knocked_back()


func start_attack(animation_name: StringName) -> bool:
	if is_busy() or not is_on_floor():
		return false
	is_attacking = true
	active_attack = animation_name
	hit_bodies.clear()
	model_animations.play(animation_name)
	return true


func receive_hit(attacker_position: Vector3, _attack_name: StringName = &"") -> void:
	_start_hit(attacker_position, true)


func _start_hit(
	attacker_position: Vector3,
	should_knockback: bool,
	allow_restart := false,
	should_bounce := false
) -> void:
	if (is_hit or _is_knocked_back()) and not allow_restart:
		return
	if is_attacking:
		_on_attack_interrupted()
	is_attacking = false
	is_hit = true
	active_attack = &""
	if should_knockback:
		var away := global_position - attacker_position
		away.y = 0.0
		if away.length_squared() < 0.001:
			away = Vector3.RIGHT.rotated(Vector3.UP, rotation.y)
		knockback_velocity = away.normalized() * knockback_speed
	if should_bounce:
		bounce_duration = 0.5
		bounce_time_left = bounce_duration
	model_animations.play(&"hit")


func face_direction(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return
	rotation.y = atan2(-direction.z, direction.x)


func _on_attack_interrupted() -> void:
	pass


func _on_model_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"idle":
		_play_idle_if_needed()
	elif animation_name == &"hit":
		is_hit = false
		_play_idle_if_needed()
	elif is_attacking and animation_name == active_attack:
		is_attacking = false
		active_attack = &""
		attack_finished.emit()
		_play_idle_if_needed()


func _play_idle_if_needed() -> void:
	if move_direction == Vector3.ZERO and not is_busy() and (
		model_animations.current_animation != &"idle" or not model_animations.is_playing()
	):
		model_animations.play(&"idle")


func _check_attack_hits() -> void:
	if not is_attacking:
		return
	var space_state := get_world_3d().direct_space_state
	for hit_area in hand_hit_areas:
		hit_area.force_update_transform()
		var shape_node := hit_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape_node == null or shape_node.disabled or shape_node.shape == null:
			continue
		shape_node.force_update_transform()
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape_node.shape
		query.transform = shape_node.global_transform
		query.collision_mask = hit_area.collision_mask
		query.exclude = [get_rid()]
		for hit in space_state.intersect_shape(query, 16):
			var body := hit.get("collider") as Node
			if body == null or not _can_attack_body(body):
				continue
			var body_id := body.get_instance_id()
			if hit_bodies.has(body_id):
				continue
			hit_bodies[body_id] = true
			if body.has_method("receive_hit"):
				body.receive_hit(global_position, active_attack)
			elif body.has_method("hit"):
				body.hit()


func _can_attack_body(_body: Node) -> bool:
	return true


func _try_start_step(direction: Vector3) -> void:
	if left_leg.progress < 1.0 or right_leg.progress < 1.0:
		return
	var left_rest := left_leg.root.global_position + left_leg.home_offset + direction * step_forward
	var right_rest := right_leg.root.global_position + right_leg.home_offset + direction * step_forward
	var should_move_left := _flat_distance(left_leg.target, left_rest) > step_distance
	var should_move_right := _flat_distance(right_leg.target, right_rest) > step_distance
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
		leg.progress = minf(leg.progress + delta / step_duration, 1.0)
		leg.target = leg.from.lerp(leg.to, leg.progress)
		leg.target.y += sin(leg.progress * PI) * step_height
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
