class_name AIController
extends Node

const _Constants = preload("res://scripts/autoload/constants.gd")

@export var team: GameManager.Team = GameManager.Team.ENEMY

var _economy_tick: float = 0.0
var _economy_interval: float = _Constants.ENEMY_DECISION_INTERVAL
var _mining_tick: float = 0.0
var _mining_interval: float = 1.0
var _attack_tick: float = 0.0
var _attack_interval: float = _Constants.ENEMY_ATTACK_WAVE_INTERVAL
var _aggression_tick: float = 0.0
var _aggression_interval: float = _Constants.ENEMY_AGGRESSION_INTERVAL

var _aggression_level: String = "balanced"  # "defend", "balanced", "push"

@onready var _grid: GridWorld = get_node("/root/Main/World/GridWorld")


func _process(delta: float) -> void:
	if not GameManager.game_active:
		return

	_economy_tick += delta
	if _economy_tick >= _economy_interval:
		_economy_tick = 0.0
		_run_economy()

	_mining_tick += delta
	if _mining_tick >= _mining_interval:
		_mining_tick = 0.0
		_run_mining()

	_attack_tick += delta
	if _attack_tick >= _attack_interval:
		_attack_tick = 0.0
		_run_attack_wave()

	_aggression_tick += delta
	if _aggression_tick >= _aggression_interval:
		_aggression_tick = 0.0
		_update_aggression_level()

	_defend_building()
	_apply_aggression_behavior()


func _run_economy() -> void:
	var building: Node2D = _get_building()
	if building == null:
		return

	var miners: int = _count_miners()
	var fighters: int = _count_fighters()
	var coin: int = EconomyManager.get_coin(team)
	var level: int = EconomyManager.get_miner_level(team)
	var population: int = EconomyManager.get_population(team)

	# Queue decisions (respecting queue size and population cap).
	var queue_size: int = building.call("get_queue").size()
	if queue_size < 3 and population < _Constants.MAX_UNITS:
		if miners < 5 and coin >= _Constants.COSTS["miner"]:
			building.call("queue_unit", "miner")
		elif fighters < 3 and coin >= _Constants.COSTS["swordsman"]:
			building.call("queue_unit", "swordsman")
		elif coin >= _Constants.COSTS["wizard"]:
			building.call("queue_unit", "wizard")
		elif coin >= _Constants.COSTS["archer"]:
			building.call("queue_unit", "archer")
		elif coin >= _Constants.COSTS["swordsman"]:
			building.call("queue_unit", "swordsman")

	# Upgrade miners.
	if level == 1 and coin >= _Constants.MINER_UPGRADE_COSTS[2]:
		EconomyManager.upgrade_miner(team)
	elif level == 2 and coin >= _Constants.MINER_UPGRADE_COSTS[3]:
		EconomyManager.upgrade_miner(team)


func _run_mining() -> void:
	for unit in get_tree().get_nodes_in_group(team_name()):
		if not unit.data.is_miner:
			continue
		if _is_busy(unit):
			continue
		if unit.carried_coin >= unit.data.carry_capacity:
			unit.deposit_coin()
		else:
			var ore: Vector2i = _find_best_ore(unit)
			if ore != Vector2i(-9999, -9999):
				unit.mine_cell(ore)
			elif unit.carried_coin > 0:
				unit.deposit_coin()


func _run_attack_wave() -> void:
	var target: Node2D = _get_enemy_building()
	if target == null:
		return
	var sent: int = 0
	for unit in get_tree().get_nodes_in_group(team_name()):
		if not unit.data.is_fighter:
			continue
		if unit._state == Unit.State.IDLE or unit._state == Unit.State.MOVE:
			unit.attack_building(target)
			sent += 1
			if sent >= 12:
				break


func _defend_building() -> void:
	var building: Node2D = _get_building()
	if building == null:
		return
	var threat: Unit = _nearest_enemy_unit(building.global_position, 350)
	if threat == null:
		return
	for unit in get_tree().get_nodes_in_group(team_name()):
		if not unit.data.is_fighter:
			continue
		if unit._state == Unit.State.IDLE or unit._state == Unit.State.MOVE:
			unit.attack_unit(threat)


func _update_aggression_level() -> void:
	var player_fighters: int = 0
	var enemy_fighters: int = 0
	for unit in get_tree().get_nodes_in_group("units"):
		if not unit.data.is_fighter or unit._state == Unit.State.DEAD:
			continue
		if unit.team == GameManager.Team.PLAYER:
			player_fighters += 1
		else:
			enemy_fighters += 1

	var my_fighters: int = enemy_fighters if team == GameManager.Team.ENEMY else player_fighters
	var their_fighters: int = player_fighters if team == GameManager.Team.ENEMY else enemy_fighters

	if my_fighters > their_fighters * 1.5:
		_aggression_level = "push"
	elif my_fighters < their_fighters * 0.5:
		_aggression_level = "defend"
	else:
		_aggression_level = "balanced"


func _apply_aggression_behavior() -> void:
	match _aggression_level:
		"push":
			# Continuously send idle fighters to attack.
			var target: Node2D = _get_enemy_building()
			if target == null:
				return
			for unit in get_tree().get_nodes_in_group(team_name()):
				if not unit.data.is_fighter:
					continue
				if unit._state == Unit.State.IDLE:
					unit.attack_building(target)
			# Also attempt wall breach if miners have run out of accessible tiles.
			_attempt_wall_breach()
		"defend":
			# Garrison ~30% of idle fighters underground.
			var idle_fighters: Array = []
			for unit in get_tree().get_nodes_in_group(team_name()):
				if unit.data.is_fighter and unit._state == Unit.State.IDLE and not unit.is_underground:
					idle_fighters.append(unit)
			var garrison_count: int = int(idle_fighters.size() * 0.3)
			for i in range(min(garrison_count, idle_fighters.size())):
				idle_fighters[i].enter_mine()


func _attempt_wall_breach() -> void:
	if _grid == null:
		return
	if _grid.get_wall_hp() <= 0:
		return
	var coin: int = EconomyManager.get_coin(team)
	if coin <= 1000:
		return
	var level: int = EconomyManager.get_miner_level(team)
	var remaining: int = _grid.count_accessible_unmined_tiles(team, level)
	if remaining > 0:
		return

	# Send 30% of idle miners to breach the nearest wall cell.
	var idle_miners: Array = []
	for unit in get_tree().get_nodes_in_group(team_name()):
		if unit.data.is_miner and not _is_busy(unit):
			idle_miners.append(unit)
	var breach_count: int = int(idle_miners.size() * 0.3)
	var wall_cells: Array[Vector2i] = _grid.get_wall_cells()
	if wall_cells.is_empty():
		return

	for i in range(min(breach_count, idle_miners.size())):
		var unit: Unit = idle_miners[i]
		var nearest: Vector2i = wall_cells[0]
		var best_dist: float = unit.global_position.distance_squared_to(_grid.grid_to_world(nearest))
		for j in range(1, wall_cells.size()):
			var d: float = unit.global_position.distance_squared_to(_grid.grid_to_world(wall_cells[j]))
			if d < best_dist:
				best_dist = d
				nearest = wall_cells[j]
		unit.mine_cell(nearest)


func _find_best_ore(unit: Unit) -> Vector2i:
	var center: Vector2i = _grid.world_to_grid(unit.global_position)
	var best: Vector2i = Vector2i(-9999, -9999)
	var best_score: float = -999999.0
	var team_dir: int = -1 if team == GameManager.Team.PLAYER else 1
	for x in range(-12, 13):
		for y in range(0, 15):
			var pos: Vector2i = center + Vector2i(x, y)
			var cell: GridWorld.Cell = _grid.get_cell(pos)
			if cell == null or cell.type != GridWorld.CellType.ORE:
				continue
			if unit.data.miner_level < cell.miner_level_required:
				continue
			# If wall is still up, stick to own side.
			if _grid.get_wall_hp() > 0 and pos.x * team_dir < -2:
				continue
			# Respect miner reservations and this miner's no-path blacklist so
			# the AI doesn't re-order tiles the miner already failed to reach.
			if not _grid.is_cell_claimable(pos, unit.get_instance_id()):
				continue
			if unit.is_cell_blacklisted(pos):
				continue
			var dist: float = center.distance_to(pos)
			var score: float = cell.coin_value - dist * 0.5
			if score > best_score:
				best_score = score
				best = pos
	return best


func _nearest_enemy_unit(pos: Vector2, max_dist: float) -> Unit:
	var best: Unit = null
	var best_d: float = max_dist * max_dist
	var other_team_name: String = "player" if team == GameManager.Team.ENEMY else "enemy"
	for unit in get_tree().get_nodes_in_group(other_team_name):
		if unit._state == Unit.State.DEAD:
			continue
		var d: float = unit.global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = unit
	return best


func _count_miners() -> int:
	var n: int = 0
	for unit in get_tree().get_nodes_in_group(team_name()):
		if unit.data.is_miner and unit._state != Unit.State.DEAD:
			n += 1
	return n


func _count_fighters() -> int:
	var n: int = 0
	for unit in get_tree().get_nodes_in_group(team_name()):
		if unit.data.is_fighter and unit._state != Unit.State.DEAD:
			n += 1
	return n


func _get_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == team:
			return b
	return null


func _get_enemy_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") != team:
			return b
	return null


func team_name() -> String:
	return "player" if team == GameManager.Team.PLAYER else "enemy"


## True while a unit is in a transition state that the AI tick should not override.
func _is_busy(unit: Unit) -> bool:
	match unit._state:
		Unit.State.IDLE, Unit.State.MOVE:
			return false
		_:
			return true
