extends Fighter

const ATTACK_COMBO: Array[StringName] = [&"attack1", &"attack2", &"attack2", &"attack3"]

@export var combo_window := 0.2

var combo_step := 0
var attack_buffered := false


func _ready() -> void:
	super._ready()
	attack_finished.connect(_on_attack_finished)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"attack") and not event.is_echo():
		_request_attack()


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	move_direction = Vector3(input.x, 0.0, input.y).normalized()
	super._physics_process(delta)


func _request_attack() -> void:
	if not is_attacking:
		_start_next_attack()
	elif not attack_buffered and combo_step < ATTACK_COMBO.size() and _is_inside_combo_window():
		attack_buffered = true


func _start_next_attack() -> void:
	if start_attack(ATTACK_COMBO[combo_step]):
		combo_step += 1
		attack_buffered = false


func _on_attack_finished() -> void:
	if attack_buffered and combo_step < ATTACK_COMBO.size():
		_start_next_attack()
	else:
		combo_step = 0
		attack_buffered = false


func _on_attack_interrupted() -> void:
	combo_step = 0
	attack_buffered = false


func _is_inside_combo_window() -> bool:
	var animation := model_animations.get_animation(active_attack)
	if animation == null:
		return false
	return model_animations.current_animation_position >= maxf(animation.length - combo_window, 0.0)
