class_name WaveConfig
extends Resource

@export var enemy_scene: PackedScene
@export var enemy_config: EnemyConfig

@export_group("Spawn Area")
@export_range(0.0, 100.0, 0.1, "or_greater") var spawn_height: float = 6.0
@export_range(0.0, 100.0, 0.1, "or_greater") var spawn_margin: float = 1.0

@export_group("Waves")
@export_range(1, 100, 1, "or_greater") var total_enemy_count := 21
@export var opening_wave_sizes: Array[int] = [1, 2, 3, 4]
@export_range(1, 100, 1, "or_greater") var repeating_wave_size := 6
@export_range(1, 100, 1, "or_greater") var dash_enabled_from_wave := 3


func get_wave_size(wave_index: int, remaining_enemy_count: int) -> int:
	if remaining_enemy_count <= 0:
		return 0
	var desired_wave_size := repeating_wave_size
	if wave_index >= 0 and wave_index < opening_wave_sizes.size():
		desired_wave_size = opening_wave_sizes[wave_index]
	return mini(desired_wave_size, remaining_enemy_count)


func can_dash_in_wave(wave_index: int) -> bool:
	return wave_index + 1 >= dash_enabled_from_wave


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if enemy_scene == null:
		errors.append("enemy_scene cannot be null")
	if enemy_config == null:
		errors.append("enemy_config cannot be null")
	else:
		for enemy_error in enemy_config.get_validation_errors():
			errors.append("enemy_config: %s" % enemy_error)
	if spawn_height < 0.0:
		errors.append("spawn_height cannot be negative")
	if spawn_margin < 0.0:
		errors.append("spawn_margin cannot be negative")
	if total_enemy_count <= 0:
		errors.append("total_enemy_count must be greater than zero")
	for wave_index in opening_wave_sizes.size():
		if opening_wave_sizes[wave_index] <= 0:
			errors.append("opening_wave_sizes[%d] must be greater than zero" % wave_index)
	if repeating_wave_size <= 0:
		errors.append("repeating_wave_size must be greater than zero")
	if dash_enabled_from_wave <= 0:
		errors.append("dash_enabled_from_wave must be greater than zero")
	return errors
