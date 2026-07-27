extends Label3D

@export var game_session_path: NodePath

var game_session: GameSession


func _ready() -> void:
	game_session = get_node_or_null(game_session_path) as GameSession
	if game_session == null:
		push_error("EnemyCounter requires a GameSession")
		return
	game_session.remaining_enemies_changed.connect(_on_remaining_enemies_changed)
	_on_remaining_enemies_changed(game_session.remaining_enemy_count)


func _on_remaining_enemies_changed(remaining_count: int) -> void:
	text = str(remaining_count)
