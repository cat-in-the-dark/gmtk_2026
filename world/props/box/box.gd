extends StaticBody3D

@export var shake_duration := 0.18
@export var shake_distance := 0.1

var rest_position: Vector3
var shake_time_left := 0.0


func _ready() -> void:
	rest_position = position


func hit() -> void:
	shake_time_left = shake_duration


func _process(delta: float) -> void:
	if shake_time_left <= 0.0:
		position = rest_position
		return
	shake_time_left = maxf(shake_time_left - delta, 0.0)
	var shake := sin(shake_time_left * 120.0) * shake_distance
	position = rest_position + Vector3(shake, 0.0, -shake)
