extends Node

const _Constants = preload("res://scripts/autoload/constants.gd")

signal coin_changed(team: GameManager.Team)
signal population_changed(team: GameManager.Team)
signal miner_level_changed(team: GameManager.Team)
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

var _units_trained: Dictionary = {
	GameManager.Team.PLAYER: 0,
	GameManager.Team.ENEMY: 0,
}

var _coin_mined: Dictionary = {
	GameManager.Team.PLAYER: 0,
	GameManager.Team.ENEMY: 0,
}


func _ready() -> void:
	pass


func reset() -> void:
	_coin = {
		GameManager.Team.PLAYER: _Constants.STARTING_COIN,
		GameManager.Team.ENEMY: _Constants.STARTING_COIN,
	}
	_population = {
		GameManager.Team.PLAYER: 0,
		GameManager.Team.ENEMY: 0,
	}
	_miner_level = {
		GameManager.Team.PLAYER: 1,
		GameManager.Team.ENEMY: 1,
	}
	_units_trained = {
		GameManager.Team.PLAYER: 0,
		GameManager.Team.ENEMY: 0,
	}
	_coin_mined = {
		GameManager.Team.PLAYER: 0,
		GameManager.Team.ENEMY: 0,
	}
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
	miner_level_changed.emit(team)
	return true


func get_miner_upgrade_cost(team: GameManager.Team) -> int:
	var next_level: int = _miner_level[team] + 1
	if _Constants.MINER_UPGRADE_COSTS.has(next_level):
		return _Constants.MINER_UPGRADE_COSTS[next_level]
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
