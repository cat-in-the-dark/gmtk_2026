extends CharacterBody3D


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

var next_left := true

@onready var skin: Node3D = $skin3/blockbench_export
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
	_update_leg(left_leg)
	_update_leg(right_leg)


func _physics_process(delta: float) -> void:
	var move_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := Vector3(move_input.x, 0.0, move_input.y).normalized()
	velocity = direction * move_speed
	move_and_slide()

	if direction != Vector3.ZERO:
		_try_start_step(direction)

	_update_leg_step(left_leg, delta)
	_update_leg_step(right_leg, delta)
	_update_leg(left_leg)
	_update_leg(right_leg)


func _try_start_step(direction: Vector3) -> void:
	if left_leg.progress < 1.0 or right_leg.progress < 1.0:
		return
	var left_rest := left_leg.root.global_position + left_leg.home_offset + direction * step_forward
	var right_rest := right_leg.root.global_position + right_leg.home_offset + direction * step_forward
	var should_move_left := _flat_distance(left_leg.target, left_rest) > step_distance
	var should_move_right := _flat_distance(right_leg.target, right_rest) > step_distance
	if should_move_left and (next_left or not should_move_right):
		_start_step(left_leg, left_rest)
		next_left = false
	elif should_move_right:
		_start_step(right_leg, right_rest)
		next_left = true


func _start_step(leg: Leg, destination: Vector3) -> void:
	leg.from = leg.target
	leg.to = destination
	leg.progress = 0.0


func _update_leg_step(leg: Leg, delta: float) -> void:
	if leg.progress < 1.0:
		leg.progress = minf(leg.progress + delta / step_duration, 1.0)
		leg.target = leg.from.lerp(leg.to, leg.progress)
		leg.target.y += sin(leg.progress * PI) * step_height
	leg.boot.global_position = leg.target - leg.boot_to_plant


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
