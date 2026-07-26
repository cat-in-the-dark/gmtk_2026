extends Node3D

const MAIN_SCENE_PATH := "res://main.tscn"

@export var orbit_speed_degrees := 18.0
@export var camera_look_height := 0.25

var camera_orbit_offset := Vector3.ZERO

@onready var frog: Node3D = $frog
@onready var frog_animations: AnimationPlayer = $frog/AnimationPlayer
@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	var stunned_animation := frog_animations.get_animation(&"stunned")
	if stunned_animation == null:
		push_error("Gameover frog requires a stunned animation")
	else:
		frog_animations.play(&"stunned")
		frog_animations.seek(0.0, true)
		frog_animations.pause()
	camera_orbit_offset = camera.global_position - _get_camera_target()
	_update_camera()


func _process(delta: float) -> void:
	var orbit_angle := deg_to_rad(orbit_speed_degrees) * delta
	camera_orbit_offset = camera_orbit_offset.rotated(Vector3.UP, orbit_angle)
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _get_camera_target() -> Vector3:
	return frog.global_position + Vector3.UP * camera_look_height


func _update_camera() -> void:
	var camera_target := _get_camera_target()
	camera.global_position = camera_target + camera_orbit_offset
	camera.look_at(camera_target)
