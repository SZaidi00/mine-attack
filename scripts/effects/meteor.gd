class_name Meteor
extends Node2D

## A falling meteor spawned during a volcano eruption. Drops from the sky to a
## random surface cell, deals impact damage in a radius, and leaves a burning
## patch unless a snowstorm is currently active.

const _Constants = preload("res://scripts/autoload/constants.gd")
const _BURNING_GROUND_SCENE: PackedScene = preload("res://scenes/effects/burning_ground.tscn")

const FALL_DURATION: float = 0.4
const FALL_HEIGHT: float = 420.0

var impact_damage: int = _Constants.VOLCANO_METEOR_IMPACT_DAMAGE_BASE
var impact_radius: float = _Constants.VOLCANO_METEOR_RADIUS_CELLS * GridWorld.CELL_SIZE
var burn_dps: float = _Constants.VOLCANO_BURN_DPS_BASE
var burn_duration: float = _Constants.VOLCANO_BURN_DURATION_BASE
var burn_radius: float = _Constants.VOLCANO_BURN_RADIUS_CELLS * GridWorld.CELL_SIZE
var leave_burn_patch: bool = true

var _target_pos: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0
var _impacted: bool = false
var _flicker: float = 0.0


func _ready() -> void:
	_flicker = randf() * TAU
	global_position = _target_pos + Vector2(0.0, -FALL_HEIGHT)
	queue_redraw()


func setup(target_position: Vector2, damage_multiplier: float = 1.0, duration_multiplier: float = 1.0, meteor_rate_multiplier: float = 1.0) -> void:
	_target_pos = target_position
	impact_damage = maxi(1, roundi(_Constants.VOLCANO_METEOR_IMPACT_DAMAGE_BASE * damage_multiplier))
	burn_dps = _Constants.VOLCANO_BURN_DPS_BASE * damage_multiplier
	burn_duration = _Constants.VOLCANO_BURN_DURATION_BASE * duration_multiplier


func _process(delta: float) -> void:
	if not GameManager.game_active:
		return
	_elapsed += delta
	_flicker += delta * 15.0
	var t: float = clampf(_elapsed / FALL_DURATION, 0.0, 1.0)
	# Ease-in for a accelerating fall.
	var eased: float = t * t
	global_position = _target_pos + Vector2(0.0, -FALL_HEIGHT * (1.0 - eased))
	queue_redraw()
	if t >= 1.0 and not _impacted:
		_impacted = true
		_trigger_impact()


func _trigger_impact() -> void:
	AudioManager.play("meteor_impact", global_position, -4.0)
	_apply_impact_damage()
	if leave_burn_patch and not WeatherManager.is_snowstorm_active():
		_spawn_burn_patch()
	# Leave the impact flash visible for one more frame, then free.
	queue_free()


func _apply_impact_damage() -> void:
	for unit in get_tree().get_nodes_in_group("units"):
		if unit._state == Unit.State.DEAD or unit.is_underground:
			continue
		if unit.global_position.distance_to(global_position) <= impact_radius:
			unit.take_damage(impact_damage, null, true)
	for group in ["towers", "lanterns", "walls"]:
		for node in get_tree().get_nodes_in_group(group):
			if _is_protected_structure(node):
				continue
			if node.global_position.distance_to(global_position) <= impact_radius:
				node.take_damage(impact_damage)
	for building in get_tree().get_nodes_in_group("buildings"):
		if _is_protected_structure(building):
			continue
		if building.global_position.distance_to(global_position) <= impact_radius:
			building.take_damage(impact_damage)
	# HQ volcano damage is disabled by design. Uncomment the block below (and
	# the matching block in BurningGround) to enable it on NIGHTMARE/GODLY:
	# if WeatherManager._should_damage_hq():
	# 	for building in get_tree().get_nodes_in_group("buildings"):
	# 		if building.name != "PlayerBuilding" and building.name != "EnemyBuilding":
	# 			continue
	# 		if building.global_position.distance_to(global_position) <= impact_radius:
	# 			building.take_damage(impact_damage)


func _spawn_burn_patch() -> void:
	var patch: BurningGround = _BURNING_GROUND_SCENE.instantiate()
	patch.global_position = global_position
	patch.damage_all_teams = true
	patch.is_volcano_fire = true
	patch.dps = burn_dps
	patch.duration = burn_duration
	patch.radius = burn_radius
	get_tree().current_scene.add_child(patch)


func _is_protected_structure(node: Node) -> bool:
	if node.is_in_group("mine_entries"):
		return true
	if node.name == "PlayerBuilding" or node.name == "EnemyBuilding":
		return true
	return false


func _draw() -> void:
	var t: float = clampf(_elapsed / FALL_DURATION, 0.0, 1.0)
	var head_pos: Vector2 = Vector2.ZERO
	var tail_pos: Vector2 = Vector2(0.0, -FALL_HEIGHT * (1.0 - t) * 0.6)
	# Flickering core.
	var pulse: float = 0.8 + 0.2 * sin(_flicker)
	draw_circle(head_pos, 12.0 * pulse, Color(1.0, 0.9, 0.4, 1.0))
	draw_circle(head_pos, 20.0 * pulse, Color(1.0, 0.5, 0.1, 0.55))
	draw_circle(head_pos, 28.0 * pulse, Color(1.0, 0.25, 0.05, 0.25))
	# Fiery trail.
	var trail_color: Color = Color(1.0, 0.25, 0.05, 0.5 * (1.0 - t))
	draw_line(tail_pos, head_pos, trail_color, 10.0 * pulse, true)
	draw_line(tail_pos + Vector2(-3.0, 0.0), head_pos, Color(1.0, 0.6, 0.1, 0.25 * (1.0 - t)), 16.0 * pulse, true)
