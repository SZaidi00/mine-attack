extends Node

signal coin_changed(team: GameManager.Team)
signal population_changed(team: GameManager.Team)
signal miner_level_changed(team: GameManager.Team)
signal stats_changed(team: GameManager.Team)

const STARTING_COIN: int = 150

# Unit costs and train times mirror UnitData resources; these are used by UI/AI.
const UNIT_COSTS: Dictionary = {
	"miner": 50,
	"swordsman": 100,
	"archer": 150,
	"wizard": 250,
}

const MINER_UPGRADE_COSTS: Dictionary = {
	2: 500,
	3: 1500,
}

var _coin: Dictionary = {
	GameManager.Team.PLAYER: STARTING_COIN,
	GameManager.Team.ENEMY: STARTING_COIN,
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
	return _population[team] + amount <= GameManager.POPULATION_CAP


func get_miner_level(team: GameManager.Team) -> int:
	return _miner_level[team]


func upgrade_miner(team: GameManager.Team) -> bool:
	var next_level: int = _miner_level[team] + 1
	if not MINER_UPGRADE_COSTS.has(next_level):
		return false
	var cost: int = MINER_UPGRADE_COSTS[next_level]
	if not spend_coin(team, cost):
		return false
	_miner_level[team] = next_level
	miner_level_changed.emit(team)
	return true


func get_miner_upgrade_cost(team: GameManager.Team) -> int:
	var next_level: int = _miner_level[team] + 1
	if MINER_UPGRADE_COSTS.has(next_level):
		return MINER_UPGRADE_COSTS[next_level]
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
