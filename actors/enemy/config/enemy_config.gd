class_name EnemyConfig
extends Resource

@export var fighter_stats: FighterStats
@export var attack: AttackDefinition

@export_group("Combat")
@export_range(0.01, 20.0, 0.01, "or_greater") var attack_range: float = 1.7
@export_range(0.0, 10.0, 0.01, "or_greater") var attack_charge_duration: float = 0.5
@export_range(1.0, 10.0, 0.05, "or_greater") var domino_area_scale: float = 1.5
@export_range(0.0, 10.0, 0.05, "or_greater") var stun_duration: float = 1.5

@export_group("Dash")
@export var can_dash_by_default := false
@export_range(0.0, 1.0, 0.05) var dash_chance: float = 0.3
@export_range(0.0, 10.0, 0.05, "or_greater") var dash_cooldown_jitter: float = 0.75


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if fighter_stats == null:
		errors.append("fighter_stats cannot be null")
	else:
		for stats_error in fighter_stats.get_validation_errors():
			errors.append("fighter_stats: %s" % stats_error)
	if attack == null:
		errors.append("attack cannot be null")
	else:
		for attack_error in attack.get_validation_errors():
			errors.append("attack: %s" % attack_error)
	if attack_range <= 0.0:
		errors.append("attack_range must be greater than zero")
	if attack_charge_duration < 0.0:
		errors.append("attack_charge_duration cannot be negative")
	if domino_area_scale < 1.0:
		errors.append("domino_area_scale cannot be less than one")
	if stun_duration < 0.0:
		errors.append("stun_duration cannot be negative")
	if dash_chance < 0.0 or dash_chance > 1.0:
		errors.append("dash_chance must be between zero and one")
	if dash_cooldown_jitter < 0.0:
		errors.append("dash_cooldown_jitter cannot be negative")
	return errors
