extends Node

@export var enemy_scene: PackedScene
@export var platform_path: NodePath
@export var spawn_height := 6.0
@export var spawn_margin := 1.0
@export_range(1, 100, 1) var total_enemy_count := 10
@export var opening_wave_sizes: Array[int] = [1, 2, 3, 4]
@export_range(1, 20, 1) var repeating_wave_size := 6

var platform: StaticBody3D
var platform_box: BoxShape3D
var random := RandomNumberGenerator.new()
var spawned_enemy_count := 0
var eliminated_enemy_count := 0
var current_wave_alive_count := 0
var wave_index := 0
var game_finished := false


func _ready() -> void:
	platform = get_node_or_null(platform_path) as StaticBody3D
	if platform == null or enemy_scene == null:
		push_error("EnemySpawner requires an enemy scene and a platform")
		return
	var collision_shape := platform.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or not collision_shape.shape is BoxShape3D:
		push_error("EnemySpawner platform requires a BoxShape3D collision")
		return
	platform_box = collision_shape.shape as BoxShape3D
	random.randomize()
	call_deferred(&"_spawn_next_wave")


func _spawn_next_wave() -> void:
	if (
		game_finished
		or current_wave_alive_count > 0
		or spawned_enemy_count >= total_enemy_count
	):
		return
	var remaining := total_enemy_count - spawned_enemy_count
	var desired_wave_size := repeating_wave_size
	if wave_index < opening_wave_sizes.size():
		desired_wave_size = opening_wave_sizes[wave_index]
	var wave_size := mini(maxi(desired_wave_size, 1), remaining)
	wave_index += 1
	current_wave_alive_count = wave_size
	for _enemy_index in wave_size:
		var enemy := enemy_scene.instantiate() as Fighter
		enemy.eliminated.connect(_on_spawned_enemy_eliminated)
		get_parent().add_child(enemy, true)
		enemy.global_position = _get_spawn_position()
		spawned_enemy_count += 1


func _on_spawned_enemy_eliminated() -> void:
	eliminated_enemy_count += 1
	current_wave_alive_count = maxi(current_wave_alive_count - 1, 0)
	if eliminated_enemy_count >= total_enemy_count:
		if game_finished:
			return
		game_finished = true
		get_tree().call_deferred(&"reload_current_scene")
		return
	if current_wave_alive_count == 0:
		call_deferred(&"_spawn_next_wave")


func _get_spawn_position() -> Vector3:
	var half_size := platform_box.size * 0.5
	var margin_x := minf(spawn_margin, half_size.x)
	var margin_z := minf(spawn_margin, half_size.z)
	var local_position := Vector3(
		random.randf_range(-half_size.x + margin_x, half_size.x - margin_x),
		half_size.y + spawn_height,
		random.randf_range(-half_size.z + margin_z, half_size.z - margin_z)
	)
	return platform.to_global(local_position)
