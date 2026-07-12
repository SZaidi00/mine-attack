class_name AIController
extends Node

@export var team: GameManager.Team = GameManager.Team.ENEMY

var _economy_tick: float = 0.0
var _economy_interval: float = 2.0
var _mining_tick: float = 0.0
var _mining_interval: float = 1.0
var _attack_tick: float = 0.0
var _attack_interval: float = 18.0

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

	_defend_building()


func _run_economy() -> void:
	var building: Node2D = _get_building()
	if building == null:
		return

	var miners: int = _count_miners()
	var fighters: int = _count_fighters()

	if miners < 5:
		building.call("queue_unit", "miner")
	elif EconomyManager.get_miner_level(team) < 2 and EconomyManager.get_coin(team) >= 300:
		EconomyManager.upgrade_miner(team)
	elif EconomyManager.get_coin(team) >= 300 and fighters < 30:
		building.call("queue_unit", "wizard")
	elif EconomyManager.get_coin(team) >= 150 and fighters < 40:
		building.call("queue_unit", "archer")
	elif EconomyManager.get_coin(team) >= 100:
		building.call("queue_unit", "swordsman")


func _run_mining() -> void:
	for unit in get_tree().get_nodes_in_group(team_name()):
		if not unit.data.is_miner:
			continue
		if unit._state != Unit.State.IDLE and unit._state != Unit.State.MOVE:
			continue
		if unit.carried_coin >= unit.data.carry_capacity:
			unit.deposit_coin()
		else:
			var ore: Vector2i = _find_best_ore(unit)
			if ore != Vector2i(-9999, -9999):
				unit.mine_cell(ore)
			else:
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
			# Prefer ore on own side; skip enemy territory.
			if pos.x * team_dir < -2:
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
