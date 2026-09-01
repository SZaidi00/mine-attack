extends Node

const _Constants = preload("res://scripts/autoload/constants.gd")

signal coin_changed(team: GameManager.Team)
signal population_changed(team: GameManager.Team)
signal miner_level_changed(team: GameManager.Team)
signal fighter_level_changed(team: GameManager.Team, unit_id: String)
signal stats_changed(team: GameManager.Team)

var _coin: Dictionary = {
	GameManager.Team.PLAYER: _Constants.STARTING_COIN,
	GameManager.Team.ENEMY: _Constants.STARTING_COIN,
}

var _population: Dictionary = {
	GameManager.Team.PLAYER: 0,
	GameManager.Team.ENEMY: 0,
}

var _miner_level: Dictionary = {
	GameManager.Team.PLAYER: 1,
	GameManager.Team.ENEMY: 1,
}

var _fighter_levels: Dictionary = _fresh_fighter_levels()


func _fresh_fighter_levels() -> Dictionary:
	var per_team: Dictionary = {}
	for unit_id in _Constants.FIGHTER_UPGRADES:
		per_team[unit_id] = 1
	return {
		GameManager.Team.PLAYER: per_team.duplicate(),
		GameManager.Team.ENEMY: per_team.duplicate(),
	}

var _units_trained: Dictionary = {
	GameManager.Team.PLAYER: 0,
	GameManager.Team.ENEMY: 0,
}

var _coin_mined: Dictionary = {
	GameManager.Team.PLAYER: 0,
	GameManager.Team.ENEMY: 0,
}

# Welfare trickle accumulator (game-time seconds since the last payout).
var _welfare_elapsed: float = 0.0


func _process(delta: float) -> void:
	if not GameManager.game_active:
		return
	# Only during a live match — the main menu has no units, so both teams
	# would look like wiped economies there.
	if get_tree().root.get_node_or_null("Main") == null:
		return
	_welfare_elapsed += delta
	if _welfare_elapsed < _Constants.WELFARE_INTERVAL:
		return
	_welfare_elapsed = 0.0
	for team: GameManager.Team in [GameManager.Team.PLAYER, GameManager.Team.ENEMY]:
		if _count_live_miners(team) > 0:
			continue
		if get_coin(team) >= FactionManager.get_unit_cost(team, "miner"):
			continue
		var amount: int = _Constants.WELFARE_COIN
		if team == GameManager.Team.ENEMY:
			# Rates, never rules: same difficulty scaling as deposit income.
			amount = roundi(amount * GameManager.get_ai_coin_multiplier())
		DebugLog.log_command("EconomyManager", "welfare", "team=%s amount=%d" % ["PLAYER" if team == GameManager.Team.PLAYER else "ENEMY", amount])
		add_coin(team, amount)


func _count_live_miners(team: GameManager.Team) -> int:
	var group: String = "player" if team == GameManager.Team.PLAYER else "enemy"
	var n: int = 0
	for unit in get_tree().get_nodes_in_group(group):
		var data = unit.get("data")
		if data != null and data.is_miner and unit.get("_state") != Unit.State.DEAD:
			n += 1
	return n


func _ready() -> void:
	pass


func reset() -> void:
	# Faction starting bonuses (Revamp Phase 2); neutral when no faction is set.
	_coin = {
		GameManager.Team.PLAYER: FactionManager.get_starting_coin(GameManager.Team.PLAYER),
		GameManager.Team.ENEMY: FactionManager.get_starting_coin(GameManager.Team.ENEMY),
	}
	_population = {
		GameManager.Team.PLAYER: 0,
		GameManager.Team.ENEMY: 0,
	}
	_miner_level = {
		GameManager.Team.PLAYER: 1,
		GameManager.Team.ENEMY: 1,
	}
	_fighter_levels = _fresh_fighter_levels()
	_units_trained = {
		GameManager.Team.PLAYER: 0,
		GameManager.Team.ENEMY: 0,
	}
	_coin_mined = {
		GameManager.Team.PLAYER: 0,
		GameManager.Team.ENEMY: 0,
	}
	_welfare_elapsed = 0.0
	coin_changed.emit(GameManager.Team.PLAYER)
	coin_changed.emit(GameManager.Team.ENEMY)
	population_changed.emit(GameManager.Team.PLAYER)
	population_changed.emit(GameManager.Team.ENEMY)
	miner_level_changed.emit(GameManager.Team.PLAYER)
	miner_level_changed.emit(GameManager.Team.ENEMY)
	stats_changed.emit(GameManager.Team.PLAYER)
	stats_changed.emit(GameManager.Team.ENEMY)


func add_coin(team: GameManager.Team, amount: int) -> void:
	_coin[team] += amount
	coin_changed.emit(team)


func spend_coin(team: GameManager.Team, amount: int) -> bool:
	if _coin[team] < amount:
		return false
	_coin[team] -= amount
	coin_changed.emit(team)
	return true


func get_coin(team: GameManager.Team) -> int:
	return _coin[team]


func can_afford(team: GameManager.Team, amount: int) -> bool:
	return _coin[team] >= amount


func add_population(team: GameManager.Team, amount: int) -> void:
	_population[team] += amount
	population_changed.emit(team)


func remove_population(team: GameManager.Team, amount: int) -> void:
	_population[team] = max(0, _population[team] - amount)
	population_changed.emit(team)


func get_population(team: GameManager.Team) -> int:
	return _population[team]


func can_add_population(team: GameManager.Team, amount: int) -> bool:
	return _population[team] + amount <= _Constants.MAX_UNITS


func get_miner_level(team: GameManager.Team) -> int:
	return _miner_level[team]


func upgrade_miner(team: GameManager.Team) -> bool:
	var next_level: int = _miner_level[team] + 1
	if not _Constants.MINER_UPGRADE_COSTS.has(next_level):
		return false
	var cost: int = _Constants.MINER_UPGRADE_COSTS[next_level]
	if not spend_coin(team, cost):
		return false
	_miner_level[team] = next_level
	DebugLog.log_command("EconomyManager", "upgrade_miner", "team=%s level=%d cost=%d" % ["PLAYER" if team == GameManager.Team.PLAYER else "ENEMY", next_level, cost])
	miner_level_changed.emit(team)
	return true


func get_miner_upgrade_cost(team: GameManager.Team) -> int:
	var next_level: int = _miner_level[team] + 1
	if _Constants.MINER_UPGRADE_COSTS.has(next_level):
		return _Constants.MINER_UPGRADE_COSTS[next_level]
	return -1


func get_fighter_level(team: GameManager.Team, unit_id: String) -> int:
	return _fighter_levels[team].get(unit_id, 1)


func upgrade_fighter(team: GameManager.Team, unit_id: String) -> bool:
	var cost: int = get_fighter_upgrade_cost(team, unit_id)
	if cost < 0:
		return false
	if not spend_coin(team, cost):
		return false
	_fighter_levels[team][unit_id] += 1
	DebugLog.log_command("EconomyManager", "upgrade_fighter", "team=%s %s level=%d cost=%d" % ["PLAYER" if team == GameManager.Team.PLAYER else "ENEMY", unit_id, _fighter_levels[team][unit_id], cost])
	fighter_level_changed.emit(team, unit_id)
	return true


func get_fighter_upgrade_cost(team: GameManager.Team, unit_id: String) -> int:
	if not _Constants.FIGHTER_UPGRADE_COSTS.has(unit_id):
		return -1
	var next_level: int = get_fighter_level(team, unit_id) + 1
	if _Constants.FIGHTER_UPGRADE_COSTS[unit_id].has(next_level):
		return _Constants.FIGHTER_UPGRADE_COSTS[unit_id][next_level]
	return -1


func train_unit(team: GameManager.Team) -> void:
	_units_trained[team] += 1
	stats_changed.emit(team)


func get_units_trained(team: GameManager.Team) -> int:
	return _units_trained[team]


func mine_coin(team: GameManager.Team, amount: int) -> void:
	_coin_mined[team] += amount
	stats_changed.emit(team)


func get_coin_mined(team: GameManager.Team) -> int:
	return _coin_mined[team]
