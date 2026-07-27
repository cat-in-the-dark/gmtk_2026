class_name AttackDefinition
extends Resource

@export var animation_name: StringName
@export var hitbox_profile: StringName
@export_range(0.0, 100.0, 0.1, "or_greater") var strength: float = 1.0
@export_range(0.0, 100.0, 0.1, "or_greater") var knockback_strength: float = 0.0
@export_range(0.0, 2.0, 0.01, "or_greater") var combo_buffer_window: float = 0.0
@export var allowed_next_attacks: Array[StringName] = []
@export var is_domino_attack := false


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if animation_name.is_empty():
		errors.append("animation_name cannot be empty")
	if hitbox_profile.is_empty():
		errors.append("hitbox_profile cannot be empty")
	if strength < 0.0:
		errors.append("strength cannot be negative")
	if knockback_strength < 0.0:
		errors.append("knockback_strength cannot be negative")
	if combo_buffer_window < 0.0:
		errors.append("combo_buffer_window cannot be negative")
	var known_next_attacks := {}
	for next_attack in allowed_next_attacks:
		if next_attack.is_empty():
			errors.append("allowed_next_attacks cannot contain an empty name")
		elif known_next_attacks.has(next_attack):
			errors.append("allowed_next_attacks contains duplicate '%s'" % next_attack)
		else:
			known_next_attacks[next_attack] = true
	return errors
