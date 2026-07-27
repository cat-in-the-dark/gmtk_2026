class_name AttackHitbox
extends Area3D

@export var active := false:
	set(value):
		if active == value:
			return
		active = value
		if active and is_node_ready():
			call_deferred(&"_hit_current_overlaps")

var fighter: Fighter


func _ready() -> void:
	monitoring = true
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func configure(source_fighter: Fighter) -> void:
	fighter = source_fighter
	if active:
		call_deferred(&"_hit_current_overlaps")


func deactivate() -> void:
	active = false


func _hit_current_overlaps() -> void:
	if not active:
		return
	for area in get_overlapping_areas():
		_on_area_entered(area)
	for body in get_overlapping_bodies():
		_on_body_entered(body)


func _on_area_entered(area: Area3D) -> void:
	if not active or fighter == null or not area is FighterHurtbox:
		return
	fighter.try_attack_hurtbox(area as FighterHurtbox)


func _on_body_entered(body: Node3D) -> void:
	if not active or fighter == null or not body is AttackReceiver3D:
		return
	fighter.try_attack_receiver(body as AttackReceiver3D)
