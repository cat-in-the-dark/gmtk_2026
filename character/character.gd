extends CharacterBody3D


const ATTACK_COMBO: Array[StringName] = [&"attack1", &"attack2", &"attack2", &"attack3"]


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


@export var move_speed := 5.5
@export var step_distance := 0.9
@export var step_forward := 0.65
@export var step_duration := 0.12
@export var step_height := 0.14
@export var combo_window := 0.2

var next_left := true
var combo_step := 0
var attack_buffered := false
var is_attacking := false
var is_moving := false
var turning_leg: Leg
var turn_start_yaw := 0.0
var turn_target_yaw := 0.0

@onready var skin: Node3D = $skin3/blockbench_export
@onready var model_animations: AnimationPlayer = skin.get_node("AnimationPlayer")
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
	model_animations.animation_finished.connect(_on_model_animation_finished)
	_update_leg(left_leg)
	_update_leg(right_leg)
	_play_idle_if_needed()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"attack") and not event.is_echo():
		_request_attack()


func _physics_process(delta: float) -> void:
	var move_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := Vector3(move_input.x, 0.0, move_input.y).normalized()
	is_moving = direction != Vector3.ZERO
	if is_moving and not is_attacking and model_animations.current_animation == &"idle":
		model_animations.stop()
		model_animations.seek(0.0, true)
	velocity = direction * move_speed
	move_and_slide()

	if direction != Vector3.ZERO:
		_try_start_step(direction)

	_update_leg_step(left_leg, delta)
	_update_leg_step(right_leg, delta)
	_update_leg(left_leg)
	_update_leg(right_leg)
	if not is_attacking:
		_play_idle_if_needed()


func _request_attack() -> void:
	if not is_attacking:
		_start_next_attack()
		return
	if not attack_buffered and combo_step < ATTACK_COMBO.size() and _is_inside_combo_window():
		attack_buffered = true


func _start_next_attack() -> void:
	is_attacking = true
	attack_buffered = false
	model_animations.play(ATTACK_COMBO[combo_step])
	combo_step += 1


func _on_model_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"idle":
		_play_idle_if_needed()
		return
	if not ATTACK_COMBO.has(animation_name):
		return
	if attack_buffered and combo_step < ATTACK_COMBO.size():
		_start_next_attack()
		return
	is_attacking = false
	combo_step = 0
	_play_idle_if_needed()


func _play_idle_if_needed() -> void:
	if not is_moving and not is_attacking and (
		model_animations.current_animation != &"idle" or not model_animations.is_playing()
	):
		model_animations.play(&"idle")


func _is_inside_combo_window() -> bool:
	var animation := model_animations.get_animation(model_animations.current_animation)
	if animation == null:
		return false
	var window_start := maxf(animation.length - combo_window, 0.0)
	return model_animations.current_animation_position >= window_start


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
	# The model's face points along its local +X axis.
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
	var bas := Basis(Quaternion(Vector3.UP, mesh_up)).scaled(Vector3(1.0, scale_y, 1.0))
	var mesh_origin := hip_position - mesh_up * leg.mesh_y_bounds.y * scale_y
	var global_mesh_transform := Transform3D(bas, mesh_origin)
	leg.mesh.transform = leg.root.global_transform.affine_inverse() * global_mesh_transform


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
