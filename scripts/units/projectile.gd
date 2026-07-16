extends Node2D

const _ARROW_TEXTURE: Texture2D = preload("res://frost_mines_assets/effects/projectile_arrow.png")
const _BLAST_TEXTURE: Texture2D = preload("res://frost_mines_assets/effects/projectile_blast.png")

@export var speed: float = 400.0
@export var damage: int = 10
@export var is_fireball: bool = false
@export var team: GameManager.Team = GameManager.Team.PLAYER

var target_position: Vector2 = Vector2.ZERO
var homing_target: Node2D = null
var homing_building: Node2D = null


func _ready() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	_update_target_position()
	var dir: Vector2 = target_position - global_position
	var dist: float = dir.length()
	var step: float = speed * delta
	if dist <= step:
		_impact()
		queue_free()
		return
	global_position += dir.normalized() * step
	look_at(target_position)


func _update_target_position() -> void:
	if homing_target != null and is_instance_valid(homing_target):
		target_position = homing_target.global_position
	elif homing_building != null and is_instance_valid(homing_building):
		target_position = homing_building.global_position


func _impact() -> void:
	var radius: float = 40.0 if is_fireball else 8.0
	var pos: Vector2 = global_position
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.get("team") == team:
			continue
		if unit.global_position.distance_to(pos) <= radius:
			unit.take_damage(damage)
	if not is_fireball:
		return
	# Splash also damages buildings.
	for building in get_tree().get_nodes_in_group("buildings"):
		if building.get("team") == team:
			continue
		if building.global_position.distance_to(pos) <= radius + 40:
			building.call("take_damage", damage)


func _draw() -> void:
	if is_fireball:
		var blast_size: Vector2 = _BLAST_TEXTURE.get_size()
		draw_texture(_BLAST_TEXTURE, -blast_size / 2.0)
	else:
		var arrow_size: Vector2 = _ARROW_TEXTURE.get_size()
		draw_texture(_ARROW_TEXTURE, -arrow_size / 2.0)
