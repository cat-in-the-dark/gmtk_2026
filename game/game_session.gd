class_name GameSession
extends Node

signal match_finished(result: MatchResult)
signal remaining_enemies_changed(remaining_count: int)

enum MatchResult {
	VICTORY,
	DEFEAT,
}

@export var player_path: NodePath
@export var enemy_spawner_path: NodePath
@export_file("*.tscn") var victory_scene_path := (
	"res://ui/result_screen/gamewin/gamewin.tscn"
)
@export_file("*.tscn") var defeat_scene_path := (
	"res://ui/result_screen/gameover/gameover.tscn"
)

var remaining_enemy_count := 0
var player: Fighter
var enemy_spawner: EnemySpawner
var _player_eliminated := false
var _all_enemies_eliminated := false
var _resolution_scheduled := false
var _match_finished := false


func _ready() -> void:
	player = get_node_or_null(player_path) as Fighter
	enemy_spawner = get_node_or_null(enemy_spawner_path) as EnemySpawner
	if player == null or enemy_spawner == null:
		push_error("GameSession requires a player and an enemy spawner")
		return
	player.eliminated.connect(_on_player_eliminated)
	enemy_spawner.all_enemies_eliminated.connect(_on_all_enemies_eliminated)
	enemy_spawner.remaining_enemy_count_changed.connect(_set_remaining_enemy_count)
	_set_remaining_enemy_count(enemy_spawner.get_remaining_enemy_count())


func _on_player_eliminated() -> void:
	_player_eliminated = true
	_schedule_resolution()


func _on_all_enemies_eliminated() -> void:
	_all_enemies_eliminated = true
	_schedule_resolution()


func _schedule_resolution() -> void:
	if _match_finished or _resolution_scheduled:
		return
	_resolution_scheduled = true
	call_deferred(&"_resolve_match")


func _resolve_match() -> void:
	_resolution_scheduled = false
	if _match_finished:
		return
	if _player_eliminated:
		_finish_match(MatchResult.DEFEAT, defeat_scene_path)
	elif _all_enemies_eliminated:
		_finish_match(MatchResult.VICTORY, victory_scene_path)


func _finish_match(result: MatchResult, scene_path: String) -> void:
	if scene_path.is_empty():
		push_error("GameSession result scene path is empty")
		return
	_match_finished = true
	match_finished.emit(result)
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		_match_finished = false
		push_error("GameSession failed to change scene: %s" % error_string(error))


func _set_remaining_enemy_count(remaining_count: int) -> void:
	if remaining_enemy_count == remaining_count:
		return
	remaining_enemy_count = remaining_count
	remaining_enemies_changed.emit(remaining_enemy_count)
