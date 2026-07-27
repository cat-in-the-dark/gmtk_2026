class_name FighterStats
extends Resource

@export_group("Movement")
@export_range(0.0, 100.0, 0.1, "or_greater") var move_speed: float = 6.0

@export_group("Procedural Steps")
@export_range(0.0, 10.0, 0.01, "or_greater") var step_distance: float = 1.26
@export_range(0.0, 10.0, 0.01, "or_greater") var step_forward: float = 0.66
@export_range(0.01, 10.0, 0.01, "or_greater") var step_duration: float = 0.12
@export_range(0.0, 10.0, 0.01, "or_greater") var step_height: float = 0.14

@export_group("Physics")
@export_range(0.0, 10.0, 0.05, "or_greater") var gravity_scale: float = 1.0
@export_range(0.0, 100.0, 0.1, "or_greater") var default_knockback_strength: float = 15.0
@export_range(0.0, 100.0, 0.1, "or_greater") var knockback_drag: float = 22.0

@export_group("Dash")
@export_range(0.01, 100.0, 0.1, "or_greater") var dash_speed: float = 16.0
@export_range(0.01, 10.0, 0.01, "or_greater") var dash_duration: float = 0.18
@export_range(0.0, 10.0, 0.01, "or_greater") var dash_cooldown: float = 0.3


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if move_speed < 0.0:
		errors.append("move_speed cannot be negative")
	if step_distance < 0.0:
		errors.append("step_distance cannot be negative")
	if step_forward < 0.0:
		errors.append("step_forward cannot be negative")
	if step_duration <= 0.0:
		errors.append("step_duration must be greater than zero")
	if step_height < 0.0:
		errors.append("step_height cannot be negative")
	if gravity_scale < 0.0:
		errors.append("gravity_scale cannot be negative")
	if default_knockback_strength < 0.0:
		errors.append("default_knockback_strength cannot be negative")
	if knockback_drag < 0.0:
		errors.append("knockback_drag cannot be negative")
	if dash_speed <= 0.0:
		errors.append("dash_speed must be greater than zero")
	if dash_duration <= 0.0:
		errors.append("dash_duration must be greater than zero")
	if dash_cooldown < 0.0:
		errors.append("dash_cooldown cannot be negative")
	return errors
