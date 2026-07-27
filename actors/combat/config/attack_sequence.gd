class_name AttackSequence
extends Resource

@export var attacks: Array[AttackDefinition] = []


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if attacks.is_empty():
		errors.append("attacks cannot be empty")
		return errors
	for attack_index in attacks.size():
		var attack := attacks[attack_index]
		if attack == null:
			errors.append("attacks[%d] cannot be null" % attack_index)
			continue
		for attack_error in attack.get_validation_errors():
			errors.append("attacks[%d]: %s" % [attack_index, attack_error])
		if attack_index >= attacks.size() - 1:
			continue
		var next_attack := attacks[attack_index + 1]
		if next_attack == null:
			continue
		if not attack.allowed_next_attacks.has(next_attack.animation_name):
			errors.append(
				(
					"attacks[%d] '%s' does not allow next attack '%s'"
					% [attack_index, attack.animation_name, next_attack.animation_name]
				)
			)
	return errors
