extends Node2D

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
		draw_circle(Vector2.ZERO, 5, Color.ORANGE_RED)
		draw_circle(Vector2.ZERO, 3, Color.YELLOW)
	else:
		draw_rect(Rect2(-6, -1, 12, 2), GameManager.COLOR_RUST, true)
		draw_polygon([Vector2(6, -3), Vector2(12, 0), Vector2(6, 3)], [GameManager.COLOR_RUST])
