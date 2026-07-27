class_name EnemySpawner
extends Node

signal all_enemies_eliminated
signal remaining_enemy_count_changed(remaining_count: int)

@export var config: WaveConfig
@export var platform_path: NodePath

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
	if not _validate_configuration():
		return
	var collision_shape := platform.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or not collision_shape.shape is BoxShape3D:
		push_error("EnemySpawner platform requires a BoxShape3D collision")
		return
	platform_box = collision_shape.shape as BoxShape3D
	remaining_enemy_count_changed.emit(get_remaining_enemy_count())
	random.randomize()
	call_deferred(&"_spawn_next_wave")


func _validate_configuration() -> bool:
	var errors := PackedStringArray()
	if config == null:
		errors.append("config cannot be null")
	else:
		for config_error in config.get_validation_errors():
			errors.append("config: %s" % config_error)
		if config.enemy_scene != null:
			var scene_root := config.enemy_scene.instantiate()
			if not scene_root is Enemy:
				errors.append("config.enemy_scene root must extend Enemy")
			scene_root.free()
	if platform == null:
		errors.append("platform_path must point to a StaticBody3D")
	if errors.is_empty():
		return true
	set_process(false)
	for configuration_error in errors:
		push_error("EnemySpawner configuration: %s" % configuration_error)
	return false


func _spawn_next_wave() -> void:
	if (
		game_finished
		or current_wave_alive_count > 0
		or spawned_enemy_count >= config.total_enemy_count
	):
		return
	var remaining := config.total_enemy_count - spawned_enemy_count
	var wave_size := config.get_wave_size(wave_index, remaining)
	var wave_can_dash := config.can_dash_in_wave(wave_index)
	wave_index += 1
	for _enemy_index in wave_size:
		_spawn_enemy(wave_can_dash)
	if current_wave_alive_count == 0:
		game_finished = true
		push_error("EnemySpawner could not create any enemy for wave %d" % wave_index)


func _spawn_enemy(wave_can_dash: bool) -> void:
	var scene_root := config.enemy_scene.instantiate()
	var enemy := scene_root as Enemy
	if enemy == null:
		scene_root.free()
		push_error("EnemySpawner enemy_scene root must extend Enemy")
		return
	if not enemy.configure(config.enemy_config, wave_can_dash):
		enemy.free()
		push_error("EnemySpawner could not configure spawned Enemy")
		return
	enemy.eliminated.connect(_on_spawned_enemy_eliminated)
	get_parent().add_child(enemy, true)
	enemy.global_position = _get_spawn_position()
	spawned_enemy_count += 1
	current_wave_alive_count += 1


func _on_spawned_enemy_eliminated() -> void:
	eliminated_enemy_count += 1
	current_wave_alive_count = maxi(current_wave_alive_count - 1, 0)
	remaining_enemy_count_changed.emit(get_remaining_enemy_count())
	if eliminated_enemy_count >= config.total_enemy_count:
		if game_finished:
			return
		game_finished = true
		all_enemies_eliminated.emit()
		return
	if current_wave_alive_count == 0:
		call_deferred(&"_spawn_next_wave")


func get_remaining_enemy_count() -> int:
	if config == null:
		return 0
	return maxi(config.total_enemy_count - eliminated_enemy_count, 0)


func _get_spawn_position() -> Vector3:
	var half_size := platform_box.size * 0.5
	var margin_x := minf(config.spawn_margin, half_size.x)
	var margin_z := minf(config.spawn_margin, half_size.z)
	var local_position := Vector3(
		random.randf_range(-half_size.x + margin_x, half_size.x - margin_x),
		half_size.y + config.spawn_height,
		random.randf_range(-half_size.z + margin_z, half_size.z - margin_z)
	)
	return platform.to_global(local_position)
