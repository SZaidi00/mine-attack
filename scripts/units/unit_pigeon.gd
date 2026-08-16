class_name UnitPigeon
extends RefCounted

## Autonomous patrol behavior for the Pigeon scout. The pigeon flies directly
## above terrain and walls, lingering on the enemy side before returning home.

enum State { FLY_TO_ENEMY, LINGER_ENEMY, FLY_HOME, LINGER_HOME }

const _Constants = preload("res://scripts/autoload/constants.gd")

var unit: Unit

var _state: State = State.FLY_TO_ENEMY
var _timer: float = 0.0
var _enemy_target: Vector2 = Vector2.ZERO
var _home_target: Vector2 = Vector2.ZERO


func _init(u: Unit) -> void:
	unit = u


func _process(delta: float) -> void:
	if not GameManager.game_active:
		return

	_timer -= delta
	match _state:
		State.FLY_TO_ENEMY:
			if _enemy_target == Vector2.ZERO:
				_enemy_target = _pick_enemy_target()
			if unit.global_position.distance_to(_enemy_target) <= 8.0:
				_state = State.LINGER_ENEMY
				_timer = _Constants.PIGEON_LINGER_ENEMY_TIME
			else:
				_move_toward(_enemy_target, delta)
		State.LINGER_ENEMY:
			if _timer <= 0.0:
				_state = State.FLY_HOME
				_home_target = Vector2.ZERO
		State.FLY_HOME:
			if _home_target == Vector2.ZERO:
				_home_target = _pick_home_target()
			if unit.global_position.distance_to(_home_target) <= 8.0:
				_state = State.LINGER_HOME
				_timer = _Constants.PIGEON_LINGER_HOME_TIME
			else:
				_move_toward(_home_target, delta)
		State.LINGER_HOME:
			if _timer <= 0.0:
				_state = State.FLY_TO_ENEMY
				_enemy_target = Vector2.ZERO


func _move_toward(target: Vector2, delta: float) -> void:
	var dir: Vector2 = target - unit.global_position
	var step: float = unit.data.speed * delta
	if dir.length() <= step:
		unit.global_position = target
	else:
		unit.global_position += dir.normalized() * step


func _pick_enemy_target() -> Vector2:
	var team_dir: float = -1.0 if unit.team == GameManager.Team.PLAYER else 1.0
	var base_x: float = team_dir * (GridWorld.X_MAX - 5) * GridWorld.CELL_SIZE
	var enemy_building: Node2D = unit._get_enemy_building()
	if enemy_building != null:
		# Stop in front of the enemy building (on this team's side of it),
		# not behind it on the enemy's half.
		base_x = enemy_building.global_position.x + team_dir * 80.0
	var x: float = base_x + randf_range(-40.0, 40.0)
	var y: float = randf_range(-24.0, 24.0)
	x = clampf(x, (GridWorld.X_MIN + 2) * GridWorld.CELL_SIZE, (GridWorld.X_MAX - 2) * GridWorld.CELL_SIZE)
	return Vector2(x, y)


func _pick_home_target() -> Vector2:
	var tower: Node2D = _nearest_friendly_tower()
	if tower != null:
		return tower.global_position + Vector2(randf_range(-30.0, 30.0), randf_range(-10.0, 10.0))
	var building: Node2D = unit._friendly_building()
	if building != null:
		var dir: float = -1.0 if unit.team == GameManager.Team.PLAYER else 1.0
		return building.global_position + Vector2(dir * 80.0, 0.0)
	return unit.global_position


func _nearest_friendly_tower() -> Node2D:
	var best: Node2D = null
	var best_dist: float = 999999.0
	for tower in unit.get_tree().get_nodes_in_group("towers"):
		if tower.team == unit.team:
			var d: float = unit.global_position.distance_squared_to(tower.global_position)
			if d < best_dist:
				best_dist = d
				best = tower
	return best
