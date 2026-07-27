extends Node3D


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart") and not event.is_echo():
		get_viewport().set_input_as_handled()
		get_tree().call_deferred(&"reload_current_scene")
