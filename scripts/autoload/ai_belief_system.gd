extends Node

## AI belief system (Revamp Phase 8): tracks what each team *thinks* the map
## looks like, as opposed to what is true. Cells and enemy units are only
## recorded while actually visible to that team (fog of war); intel that is
## not re-seen decays in confidence until it stops counting. The maps are
## infrastructure for belief-driven decisions — current consumers are AI
## scouting (stop once the enemy faction is known) and faction inference from
## observed army composition.

## Seconds between full vision sweeps (per team).
const UPDATE_INTERVAL: float = 0.5
## Confidence lost per second while a unit stays out of sight (~10s to zero).
const CONFIDENCE_DECAY_PER_SEC: float = 0.1
## Beliefs below this confidence no longer count as enemy army strength.
const ARMY_CONFIDENCE_FLOOR: float = 0.3
## fog_state_at value for "currently visible" (grid_fog_of_war.gd has no enum).
const _FOG_VISIBLE: int = 2

## What the AI remembers about one enemy unit.
class UnitBelief:
	var unit_id: String = ""
	var last_seen_position: Vector2 = Vector2.ZERO
	var last_seen_time: float = 0.0
	var estimated_hp: int = 0
	var confidence: float = 1.0

var _believed_cells: Dictionary = {}  # team -> {Vector2i -> CellType int}
var _believed_units: Dictionary = {}  # team -> {unit instance_id -> UnitBelief}
var _believed_faction: Dictionary = {}  # team -> String ("unknown" until scouted)
var _tick: float = 0.0


func _ready() -> void:
	reset()


## Per-match state: beliefs reference unit instance ids and a grid that only
## live for one scene, so everything clears between matches.
func reset() -> void:
	_believed_cells = { GameManager.Team.PLAYER: {}, GameManager.Team.ENEMY: {} }
	_believed_units = { GameManager.Team.PLAYER: {}, GameManager.Team.ENEMY: {} }
	_believed_faction = {
		GameManager.Team.PLAYER: "unknown",
		GameManager.Team.ENEMY: "unknown",
	}
	_tick = 0.0


func _process(delta: float) -> void:
	if not GameManager.game_active:
		return
	# Stale intel fades even between sweeps.
	for team in _believed_units:
		for id in _believed_units[team]:
			var belief: UnitBelief = _believed_units[team][id]
			belief.confidence = maxf(0.0, belief.confidence - CONFIDENCE_DECAY_PER_SEC * delta)
	_tick += delta
	if _tick >= UPDATE_INTERVAL:
		_tick = 0.0
		update_belief_from_vision(GameManager.Team.ENEMY)


## Refresh one team's beliefs from its live vision: visible cells are copied
## verbatim (carved-out cells are forgotten), visible enemy units create or
## refresh a UnitBelief at full confidence. Cells and units out of sight keep
## their stale belief unchanged.
func update_belief_from_vision(team: GameManager.Team) -> void:
	var grid: GridWorld = get_node_or_null("/root/Main/World/GridWorld")
	if grid == null:
		return
	var cells: Dictionary = _believed_cells[team]
	for y in range(GridWorld.Y_MIN, GridWorld.Y_MAX + 1):
		for x in range(GridWorld.X_MIN, GridWorld.X_MAX + 1):
			var pos := Vector2i(x, y)
			if grid.fog_state_at(team, pos) != _FOG_VISIBLE:
				continue
			var cell: GridWorld.Cell = grid.get_cell(pos)
			if cell == null:
				cells.erase(pos)  # dug out since we last looked
			else:
				cells[pos] = cell.type
	var units: Dictionary = _believed_units[team]
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == team or unit._state == Unit.State.DEAD:
			continue
		if not grid.is_visible_to(team, unit.global_position):
			continue
		var belief: UnitBelief = units.get(unit.get_instance_id())
		if belief == null:
			belief = UnitBelief.new()
			units[unit.get_instance_id()] = belief
		belief.unit_id = unit.data.unit_name.to_lower()
		belief.last_seen_position = unit.global_position
		belief.last_seen_time = GameManager.match_time
		belief.estimated_hp = unit.hp
		belief.confidence = 1.0


## Estimated count of each enemy unit type (miners included), based on last
## seen positions — beliefs under the confidence floor no longer count.
func get_believed_enemy_army(team: GameManager.Team) -> Dictionary:
	var counts: Dictionary = {}
	for id in _believed_units[team]:
		var belief: UnitBelief = _believed_units[team][id]
		if belief.confidence < ARMY_CONFIDENCE_FLOOR:
			continue
		counts[belief.unit_id] = int(counts.get(belief.unit_id, 0)) + 1
	return counts


## Believed type of a grid cell, or -1 when the team has never seen it.
func get_believed_cell(team: GameManager.Team, grid_pos: Vector2i) -> int:
	return int(_believed_cells[team].get(grid_pos, -1))


## The team's current best guess at the enemy faction ("unknown" until
## scouted or inferred with confidence).
func get_believed_faction(team: GameManager.Team) -> String:
	return _believed_faction[team]


## Infer the enemy faction from observed unit composition (revamp.md 9.1):
## wizard-heavy → arcane, miner swarms → industrial, swordsman mass → brute.
## Hard intel beats inference: once a scout identifies the faction for real,
## the truth is returned. Needs 3+ fresh sightings for any guess.
func infer_enemy_faction(team: GameManager.Team) -> String:
	var their_team: GameManager.Team = GameManager.Team.PLAYER if team == GameManager.Team.ENEMY else GameManager.Team.ENEMY
	if FactionManager.is_faction_identified(their_team):
		var faction: FactionData = FactionManager.get_faction(their_team)
		if faction != null:
			_believed_faction[team] = faction.faction_id
			return faction.faction_id
	var counts: Dictionary = get_believed_enemy_army(team)
	var total: int = 0
	for unit_id in counts:
		total += counts[unit_id]
	if total < 3:
		return "unknown"
	var result: String = "unknown"
	if float(int(counts.get("wizard", 0))) / total >= 0.34:
		result = "arcane"
	elif int(counts.get("miner", 0)) >= 6 or float(int(counts.get("miner", 0))) / total >= 0.6:
		result = "industrial"
	elif float(int(counts.get("swordsman", 0))) / total >= 0.5:
		result = "brute"
	if result != "unknown":
		_believed_faction[team] = result
	return result
