extends Node

# ResearchManager — timed tech tree (Phase: research v1).
#
# Owns per-team research state: one active research at a time per team, coin
# paid up front, timed completion, 100% refund on cancel (mirrors the
# training-queue convention). Tech definitions live in
# Constants.RESEARCH_TECHS; effects are applied by the systems that own the
# stat (unit.gd, building.gd) listening to research_completed or querying
# get_stat_bonus(). Also owns the Ore Sonar scan ability and its cooldown.
#
# Like the other autoloads, state survives scene reloads — hud.gd calls
# reset() on Play Again / Quit to Menu alongside GameManager/EconomyManager.

const _Constants = preload("res://scripts/autoload/constants.gd")

signal research_started(team: GameManager.Team, tech_id: String)
signal research_completed(team: GameManager.Team, tech_id: String)
signal research_changed(team: GameManager.Team)
signal sonar_used(team: GameManager.Team, revealed_count: int)
signal sonar_ready(team: GameManager.Team)

# Tech level per team per tech id (0 = not researched).
var _levels: Dictionary = {}
# One active research slot per team: { tech_id, level, remaining, total, cost } or {}.
var _active: Dictionary = {}
# Remaining sonar cooldown seconds per team.
var _sonar_cooldown: Dictionary = {}


func _ready() -> void:
	reset()


func reset() -> void:
	_levels = _fresh_levels()
	_active = {
		GameManager.Team.PLAYER: {},
		GameManager.Team.ENEMY: {},
	}
	_sonar_cooldown = {
		GameManager.Team.PLAYER: 0.0,
		GameManager.Team.ENEMY: 0.0,
	}
	research_changed.emit(GameManager.Team.PLAYER)
	research_changed.emit(GameManager.Team.ENEMY)


func _fresh_levels() -> Dictionary:
	var per_team: Dictionary = {}
	for tech_id in _Constants.RESEARCH_TECHS:
		per_team[tech_id] = 0
	return {
		GameManager.Team.PLAYER: per_team.duplicate(),
		GameManager.Team.ENEMY: per_team.duplicate(),
	}


func _process(delta: float) -> void:
	# Research and cooldowns freeze on pause/game-over, same as training.
	if not GameManager.game_active:
		return
	for team in [GameManager.Team.PLAYER, GameManager.Team.ENEMY]:
		var active: Dictionary = _active[team]
		if not active.is_empty():
			active.remaining -= delta
			if active.remaining <= 0.0:
				_active[team] = {}
				_levels[team][active.tech_id] = active.level
				DebugLog.log_command("ResearchManager", "research_complete", "team=%s tech=%s level=%d" % [_team_name(team), active.tech_id, active.level])
				research_completed.emit(team, active.tech_id)
				research_changed.emit(team)
		if _sonar_cooldown[team] > 0.0:
			_sonar_cooldown[team] = maxf(0.0, _sonar_cooldown[team] - delta)
			if _sonar_cooldown[team] == 0.0:
				sonar_ready.emit(team)


func _team_name(team: GameManager.Team) -> String:
	return "PLAYER" if team == GameManager.Team.PLAYER else "ENEMY"


# ─── Research API ───

func get_level(team: GameManager.Team, tech_id: String) -> int:
	return _levels[team].get(tech_id, 0)


func get_max_level(tech_id: String) -> int:
	if not _Constants.RESEARCH_TECHS.has(tech_id):
		return 0
	return _Constants.RESEARCH_TECHS[tech_id].levels.size()


## Level data for the next researchable level, or {} if unknown/maxed.
func get_next_level_data(team: GameManager.Team, tech_id: String) -> Dictionary:
	if not _Constants.RESEARCH_TECHS.has(tech_id):
		return {}
	var next_level: int = get_level(team, tech_id) + 1
	return _Constants.RESEARCH_TECHS[tech_id].levels.get(next_level, {})


func get_active(team: GameManager.Team) -> Dictionary:
	return _active[team]


func is_researching(team: GameManager.Team) -> bool:
	return not _active[team].is_empty()


func start_research(team: GameManager.Team, tech_id: String) -> bool:
	if not _Constants.RESEARCH_TECHS.has(tech_id):
		DebugLog.log_reject("ResearchManager", "start_research", "unknown tech " + tech_id)
		return false
	if is_researching(team):
		DebugLog.log_reject("ResearchManager", "start_research", "research slot busy")
		return false
	var data: Dictionary = get_next_level_data(team, tech_id)
	if data.is_empty():
		DebugLog.log_reject("ResearchManager", "start_research", tech_id + " already maxed")
		return false
	if not EconomyManager.spend_coin(team, data.cost):
		DebugLog.log_reject("ResearchManager", "start_research", "cannot afford " + tech_id)
		return false
	_active[team] = {
		"tech_id": tech_id,
		"level": get_level(team, tech_id) + 1,
		"remaining": data.time,
		"total": data.time,
		"cost": data.cost,
	}
	DebugLog.log_command("ResearchManager", "start_research", "team=%s tech=%s cost=%d time=%.1f" % [_team_name(team), tech_id, data.cost, data.time])
	research_started.emit(team, tech_id)
	research_changed.emit(team)
	return true


## Cancels the in-progress research with a 100% refund (training-queue rule).
func cancel_research(team: GameManager.Team) -> bool:
	var active: Dictionary = _active[team]
	if active.is_empty():
		return false
	EconomyManager.add_coin(team, active.cost)
	DebugLog.log_command("ResearchManager", "cancel_research", "team=%s tech=%s refund=%d" % [_team_name(team), active.tech_id, active.cost])
	_active[team] = {}
	research_changed.emit(team)
	return true


## Total bonus for an effect key across all researched tech levels.
## Level values are per-level increments and sum (e.g. bulwark 2 + 2 = 4).
func get_stat_bonus(team: GameManager.Team, key: String) -> float:
	var total: float = 0.0
	for tech_id in _Constants.RESEARCH_TECHS:
		var levels: Dictionary = _Constants.RESEARCH_TECHS[tech_id].levels
		for lvl in range(1, get_level(team, tech_id) + 1):
			total += float(levels.get(lvl, {}).get(key, 0.0))
	return total


# ─── Ore Sonar ───

func get_sonar_level(team: GameManager.Team) -> int:
	return get_level(team, "ore_sonar")


func get_scan_cooldown_remaining(team: GameManager.Team) -> float:
	return _sonar_cooldown[team]


func get_scan_cooldown_total(team: GameManager.Team) -> float:
	var lvl: int = get_sonar_level(team)
	return _Constants.SONAR_COOLDOWN.get(maxi(lvl, 1), 60.0)


func can_scan(team: GameManager.Team) -> bool:
	return GameManager.game_active and get_sonar_level(team) > 0 and _sonar_cooldown[team] <= 0.0


## Reveals buried ore around the team's mine entry so miners path straight to
## it. Returns the number of newly revealed ore cells, or -1 if rejected.
func scan(team: GameManager.Team) -> int:
	if get_sonar_level(team) <= 0:
		DebugLog.log_reject("ResearchManager", "scan", "ore_sonar not researched")
		return -1
	if _sonar_cooldown[team] > 0.0:
		DebugLog.log_reject("ResearchManager", "scan", "scan on cooldown")
		return -1
	# Null-safe lookups: headless tests and the main menu have no Main scene.
	var grid: GridWorld = get_node_or_null("/root/Main/World/GridWorld")
	if grid == null:
		DebugLog.log_reject("ResearchManager", "scan", "no GridWorld")
		return -1
	var mine_entry: Node2D = null
	for entry in get_tree().get_nodes_in_group("mine_entries"):
		if entry.get("team") == team:
			mine_entry = entry
			break
	if mine_entry == null:
		DebugLog.log_reject("ResearchManager", "scan", "no mine entry for team")
		return -1
	var radius: int = _Constants.SONAR_RADIUS[get_sonar_level(team)]
	var center: Vector2i = grid.world_to_grid(mine_entry.call("get_underground_position"))
	var revealed: int = grid.reveal_ore_in_radius(center, radius, team)
	_sonar_cooldown[team] = _Constants.SONAR_COOLDOWN[get_sonar_level(team)]
	DebugLog.log_command("ResearchManager", "scan", "team=%s revealed=%d" % [_team_name(team), revealed])
	AudioManager.play("sonar", mine_entry.call("get_underground_position"), -4.0)
	sonar_used.emit(team, revealed)
	return revealed
