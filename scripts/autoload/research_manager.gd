extends Node

# ResearchManager — timed tech tree (Revamp Phase 6: branch tree).
#
# Owns per-team research state: one active research at a time per team, coin
# paid up front, timed completion, 100% refund on cancel (mirrors the
# training-queue convention). Completing a branch tech permanently locks its
# "locks" alternative for the team; a one-time respec (BRANCH_RESPEC_COST)
# resets the team's researched branches and locks. Tech definitions live in
# Constants.RESEARCH_TECHS; effects are applied by the systems that own the
# stat (unit.gd, building.gd) listening to research_completed/research_changed
# or querying get_stat_bonus()/has_branch(). Also owns the Ore Sonar scan
# ability and its cooldown.
#
# Like the other autoloads, state survives scene reloads — hud.gd calls
# reset() on Play Again / Quit to Menu alongside GameManager/EconomyManager.

const _Constants = preload("res://scripts/autoload/constants.gd")

signal research_started(team: GameManager.Team, tech_id: String)
signal research_completed(team: GameManager.Team, tech_id: String)
signal research_changed(team: GameManager.Team)
signal branch_locked(team: GameManager.Team, tech_id: String)
signal sonar_used(team: GameManager.Team, revealed_count: int)
signal sonar_ready(team: GameManager.Team)

# Tech level per team per tech id (0 = not researched).
var _levels: Dictionary = {}
# One active research slot per team: { tech_id, level, remaining, total, cost } or {}.
var _active: Dictionary = {}
# Branch tech ids locked per team (the unchosen alternative of a completed branch).
var _locked: Dictionary = {}
# One-time branch respec per team per match.
var _respec_used: Dictionary = {}
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
	_locked = {
		GameManager.Team.PLAYER: [],
		GameManager.Team.ENEMY: [],
	}
	_respec_used = {
		GameManager.Team.PLAYER: false,
		GameManager.Team.ENEMY: false,
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
				# Completing a branch locks its alternative for good.
				var locks: String = _Constants.RESEARCH_TECHS[active.tech_id].get("locks", "")
				if locks != "" and not _locked[team].has(locks):
					_locked[team].append(locks)
					DebugLog.log_command("ResearchManager", "branch_locked", "team=%s tech=%s" % [_team_name(team), locks])
					branch_locked.emit(team, locks)
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


## True once the team has researched the branch (level ≥ 1).
func has_branch(team: GameManager.Team, branch_id: String) -> bool:
	return get_level(team, branch_id) > 0


## True when the tech is the locked-out alternative of a completed branch.
func is_locked(team: GameManager.Team, tech_id: String) -> bool:
	return _locked[team].has(tech_id)


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


## Prerequisite techs must be researched first — this is what gives the tree
## its tiers. "requires" (id → level) is AND: all listed techs must reach the
## level. "requires_any" (Array of ids) is OR: at least one at level ≥ 1.
func are_prerequisites_met(team: GameManager.Team, tech_id: String) -> bool:
	if not _Constants.RESEARCH_TECHS.has(tech_id):
		return false
	for prereq_id in _Constants.RESEARCH_TECHS[tech_id].get("requires", {}):
		var needed: int = _Constants.RESEARCH_TECHS[tech_id].requires[prereq_id]
		if get_level(team, prereq_id) < needed:
			return false
	var any_of: Array = _Constants.RESEARCH_TECHS[tech_id].get("requires_any", [])
	if not any_of.is_empty():
		for prereq_id in any_of:
			if get_level(team, prereq_id) >= 1:
				return true
		return false
	return true


func start_research(team: GameManager.Team, tech_id: String) -> bool:
	if not _Constants.RESEARCH_TECHS.has(tech_id):
		DebugLog.log_reject("ResearchManager", "start_research", "unknown tech " + tech_id)
		return false
	if is_researching(team):
		DebugLog.log_reject("ResearchManager", "start_research", "research slot busy")
		return false
	if is_locked(team, tech_id):
		DebugLog.log_reject("ResearchManager", "start_research", tech_id + " is locked by the chosen branch")
		return false
	var data: Dictionary = get_next_level_data(team, tech_id)
	if data.is_empty():
		DebugLog.log_reject("ResearchManager", "start_research", tech_id + " already maxed")
		return false
	if not are_prerequisites_met(team, tech_id):
		DebugLog.log_reject("ResearchManager", "start_research", "prerequisites not met for " + tech_id)
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


## One-time branch respec: allowed once per match, only after the team has
## researched something, and only if it can afford BRANCH_RESPEC_COST.
func can_respec(team: GameManager.Team) -> bool:
	if _respec_used[team]:
		return false
	var has_any: bool = false
	for tech_id in _levels[team]:
		if _levels[team][tech_id] > 0:
			has_any = true
			break
	if not has_any:
		return false
	return EconomyManager.can_afford(team, _Constants.BRANCH_RESPEC_COST)


## Resets the team's researched branches and locks for BRANCH_RESPEC_COST.
## In-progress research is unaffected (the slot is a separate purchase);
## effects revert via the research_changed listeners recomputing from base.
func respec(team: GameManager.Team) -> bool:
	if not can_respec(team):
		DebugLog.log_reject("ResearchManager", "respec", "not available for team")
		return false
	EconomyManager.spend_coin(team, _Constants.BRANCH_RESPEC_COST)
	for tech_id in _levels[team]:
		_levels[team][tech_id] = 0
	_locked[team] = []
	_respec_used[team] = true
	DebugLog.log_command("ResearchManager", "respec", "team=%s cost=%d" % [_team_name(team), _Constants.BRANCH_RESPEC_COST])
	research_changed.emit(team)
	return true


## Total bonus for an effect key across all researched tech levels.
## Level values are per-level increments and sum (e.g. two levels of the same
## tech each granting archer_range would add up).
func get_stat_bonus(team: GameManager.Team, key: String) -> float:
	var total: float = 0.0
	for tech_id in _Constants.RESEARCH_TECHS:
		var levels: Dictionary = _Constants.RESEARCH_TECHS[tech_id].levels
		for lvl in range(1, get_level(team, tech_id) + 1):
			total += float(levels.get(lvl, {}).get(key, 0.0))
	return total


# ─── Ore Sonar ───

## Effective sonar level: the ore_sonar research level (1 = unlocked).
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
