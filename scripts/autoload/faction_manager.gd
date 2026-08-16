extends Node

## Faction system (Revamp Phase 2). Holds each team's FactionData pick, the
## per-team hidden-faction identification state, and the single source of
## truth for faction-modified unit costs. Both picks persist across
## GameManager.reset() like the difficulty choice; the main menu overwrites
## the player pick and re-rolls the enemy pick on Play. A team with no
## faction (empty id, e.g. tests booting main.tscn directly) is fully
## neutral: base costs, base stats, no abilities.

signal faction_identified(team: GameManager.Team)

const FACTIONS: Dictionary = {
	"arcane": preload("res://scripts/resources/factions/arcane.tres"),
	"brute": preload("res://scripts/resources/factions/brute.tres"),
	"industrial": preload("res://scripts/resources/factions/industrial.tres"),
}

## Cells around the enemy building a scout must reach to identify its faction.
const IDENTIFY_RANGE_CELLS: float = 8.0

var player_faction_id: String = ""
var enemy_faction_id: String = ""

var _identified: Dictionary = {
	GameManager.Team.PLAYER: false,
	GameManager.Team.ENEMY: false,
}


func set_player_faction(faction_id: String) -> void:
	player_faction_id = faction_id


## The AI's faction is a hidden random pick each match.
func pick_random_enemy_faction() -> void:
	enemy_faction_id = FACTIONS.keys()[randi() % FACTIONS.size()]


func get_faction(team: GameManager.Team) -> FactionData:
	var faction_id: String = player_faction_id if team == GameManager.Team.PLAYER else enemy_faction_id
	return FACTIONS.get(faction_id)


## Faction-modified purchase cost; base costs live in Constants.COSTS.
func get_unit_cost(team: GameManager.Team, unit_id: String) -> int:
	var faction := get_faction(team)
	if faction == null:
		return Constants.COSTS[unit_id]
	return faction.get_unit_cost(unit_id, Constants.COSTS[unit_id])


func get_starting_coin(team: GameManager.Team) -> int:
	var faction := get_faction(team)
	return Constants.STARTING_COIN + (faction.starting_gold_bonus if faction else 0)


func get_starting_miners(team: GameManager.Team) -> int:
	var faction := get_faction(team)
	return Constants.STARTING_MINERS + (faction.starting_miner_bonus if faction else 0)


## Revamp Phase 3: faction-modified structure prices/limits.
func get_tower_cost(team: GameManager.Team) -> int:
	var faction := get_faction(team)
	return faction.tower_cost if faction else Constants.TOWER_COST


func get_wall_cost(team: GameManager.Team) -> int:
	var faction := get_faction(team)
	return faction.wall_cost if faction else Constants.PLACED_WALL_COST


func get_wall_max_count(team: GameManager.Team) -> int:
	var faction := get_faction(team)
	return faction.wall_max_count if faction else Constants.PLACED_WALL_MAX_COUNT


## Hidden information: the opponent's faction is only revealed by scouting
## (a unit getting within IDENTIFY_RANGE_CELLS of the enemy building).
func is_faction_identified(team: GameManager.Team) -> bool:
	return _identified[team]


func identify_faction(team: GameManager.Team) -> void:
	if _identified[team]:
		return
	_identified[team] = true
	faction_identified.emit(team)


## Per-match state. Faction picks survive (same pattern as GameManager
## difficulty); only the scouting knowledge resets.
func reset() -> void:
	_identified[GameManager.Team.PLAYER] = false
	_identified[GameManager.Team.ENEMY] = false
