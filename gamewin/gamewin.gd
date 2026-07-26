extends Node3D

const MAIN_SCENE_PATH := "res://main.tscn"
const EXPECTED_DUCK_COUNT := 3

@export var orbit_speed_degrees := 18.0
@export var camera_look_height := 0.25
@export var fallback_camera_target := Vector3(0.0, 5.05, -4.0)

var ducks: Array[Node3D] = []
var duck_animations: Array[AnimationPlayer] = []
var camera_orbit_offset := Vector3.ZERO

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_find_ducks(self)
	if ducks.size() != EXPECTED_DUCK_COUNT:
		push_warning(
			"Gamewin expected %d ducks with a stunned animation, found %d"
			% [EXPECTED_DUCK_COUNT, ducks.size()]
		)
	for animations in duck_animations:
		animations.play(&"stunned")
		animations.seek(0.0, true)
		animations.pause()
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


func _find_ducks(node: Node) -> void:
	for child in node.get_children():
		var animations := child as AnimationPlayer
		if animations != null and animations.has_animation(&"stunned"):
			var duck := animations.get_parent() as Node3D
			if duck != null and not ducks.has(duck):
				ducks.append(duck)
				duck_animations.append(animations)
		else:
			_find_ducks(child)


func _get_camera_target() -> Vector3:
	if ducks.is_empty():
		return fallback_camera_target
	var duck_center := Vector3.ZERO
	for duck in ducks:
		duck_center += duck.global_position
	duck_center /= ducks.size()
	return duck_center + Vector3.UP * camera_look_height


func _update_camera() -> void:
	var camera_target := _get_camera_target()
	camera.global_position = camera_target + camera_orbit_offset
	camera.look_at(camera_target)
