class_name FighterHurtbox
extends Area3D

var fighter: Fighter


func _ready() -> void:
	fighter = get_parent() as Fighter
	if fighter == null:
		push_error("FighterHurtbox must be a direct child of Fighter")
