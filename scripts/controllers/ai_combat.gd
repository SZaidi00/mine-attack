class_name AICombat
extends RefCounted

const _Constants = preload("res://scripts/autoload/constants.gd")

var ai: AIController

func _init(a: AIController) -> void:
	ai = a


func _run_attack_wave() -> void:
	_launch_wave_if_ready()


## Group attack: the army holds at home until it reaches critical mass
## (_wave_threshold), then everyone free moves out together. Launching
## stragglers the moment they spawned is what made the old AI feed one
## swordsman at a time. threshold_override replaces the computed threshold
## (used by the counter-attack window to strike with whatever is gathered).
func _launch_wave_if_ready(threshold_override: int = -1) -> void:
	var target: Node2D = _get_enemy_building()
	if target == null:
		return
	var free_fighters: Array = []
	var total: int = 0
	for unit in ai.get_tree().get_nodes_in_group(team_name()):
		if not unit.data.is_fighter or unit._state == Unit.State.DEAD:
			continue
		total += 1
		# Engaged fighters keep their duel; underground ones stay put. Only
		# free surface fighters get the wave order.
		if (unit._state == Unit.State.IDLE or unit._state == Unit.State.MOVE) and not unit.is_underground:
			free_fighters.append(unit)
	var threshold: int = threshold_override if threshold_override >= 0 else _wave_threshold(target)
	# Anti-stall escapes (smarts tier 2+, organic launches only) keep the AI
	# proactive even while outmatched: desperation (no wave has marched for
	# ENEMY_WAVE_DESPERATION_DELAY, scaled by the difficulty attack tempo) and
	# pop-cap pressure (the army cannot grow any further, so holding only lets
	# the enemy catch up). Desperation also drops the size threshold to
	# ENEMY_DESPERATE_WAVE_SIZE — an out-produced AI stuck below the defend-mode
	# threshold must still raid with whatever it has instead of never attacking.
	var desperate: bool = false
	var capped: bool = false
	if GameManager.get_ai_smarts() >= 2 and threshold_override < 0:
		var desperation_delay: float = _Constants.ENEMY_WAVE_DESPERATION_DELAY * GameManager.get_ai_wave_multiplier()
		desperate = GameManager.match_time - ai._last_wave_launched_at >= desperation_delay
		capped = EconomyManager.get_population(ai.team) >= _Constants.MAX_UNITS - 2
		if desperate:
			threshold = mini(threshold, _Constants.ENEMY_DESPERATE_WAVE_SIZE)
	if total < threshold:
		return
	# Combat-predictor veto (smarts tier 2+): don't march into a decisive
	# loss — hold and keep massing. Only organic threshold launches can be
	# vetoed (counter-attacks/timing attacks already picked their moment),
	# and the all-in against a nearly-dead enemy base always goes.
	if GameManager.get_ai_smarts() >= 2 and threshold_override < 0:
		var hp_ratio: float = float(target.get("_hp")) / maxf(1.0, float(target.get("max_hp")))
		if not desperate and not capped and hp_ratio >= 0.25 and ai._smart._simulate_combat() < _Constants.ENEMY_WAVE_VETO_SIM_RATIO:
			return
	ai._last_wave_launched_at = GameManager.match_time
	ai._last_wave_desperate = desperate
	# A launch sweeps every free fighter, raiders included — the raid squad
	# re-forms on the next harass tick after the wave is out.
	ai._raiders.clear()
	# Peel a vanguard onto remembered enemy towers/lanterns (see
	# _wave_structure_assignments); the rest march on the base.
	var assignments: Dictionary = _wave_structure_assignments(free_fighters.size())
	var structures: Array = assignments["structures"]
	var peel_count: int = assignments["peel_count"]
	for i in range(free_fighters.size()):
		var unit: Unit = free_fighters[i]
		# Wave hunting (tier 2+): engage a visible enemy field unit in range
		# instead of beelining the base — the wave fights the army it meets
		# on the way instead of marching past it.
		var hunt: Unit = _wave_hunt_target(unit)
		if hunt != null:
			unit.attack_unit(hunt)
		elif i < peel_count:
			unit.attack_building(structures[i % structures.size()])
		else:
			unit.attack_building(target)


## Wave hunting: the nearest visible enemy surface fighter within
## ENEMY_WAVE_HUNT_RANGE that this unit can damage, or null (march on the
## base). Reads live team vision, so the wave only reacts to armies it can
## actually see coming.
func _wave_hunt_target(unit: Unit) -> Unit:
	if GameManager.get_ai_smarts() < 2 or ai._grid == null:
		return null
	var best: Unit = null
	var best_d2: float = _Constants.ENEMY_WAVE_HUNT_RANGE * _Constants.ENEMY_WAVE_HUNT_RANGE
	var other_team_name: String = "player" if ai.team == GameManager.Team.ENEMY else "enemy"
	for other in ai.get_tree().get_nodes_in_group(other_team_name):
		if not other.data.is_fighter or other._state == Unit.State.DEAD or other.is_underground:
			continue
		if not unit.can_damage_unit(other):
			continue
		if not ai._grid.is_visible_to(ai.team, other.global_position):
			continue
		var d2: float = unit.combat_distance_squared_to(other)
		if d2 < best_d2:
			best_d2 = d2
			best = other
	return best


## Strategic structure targeting: enemy towers and lanterns the team
## remembers (Fog of War intel), sorted nearest-to-our-base first so the wave
## cleans up the front line before pushing deeper. Waves peel up to half
## their fighters (2 per structure) onto these; the rest march on the base.
func _wave_structure_assignments(free_count: int) -> Dictionary:
	var structures: Array = []
	var home: Node2D = _get_building()
	for group: String in ["towers", "lanterns"]:
		for s in ai.get_tree().get_nodes_in_group(group):
			if s.get("team") == ai.team or not s.is_built():
				continue
			if not ai._grid.is_remembered_by(ai.team, s.global_position):
				continue
			structures.append(s)
	if home != null:
		var home_pos: Vector2 = home.global_position
		structures.sort_custom(func(a: Node2D, b: Node2D) -> bool:
			return home_pos.distance_squared_to(a.global_position) < home_pos.distance_squared_to(b.global_position))
	var peel_count: int = mini(structures.size() * 2, free_count / 2)
	return { "structures": structures, "peel_count": peel_count }


## Minimum army size before a wave launches, by aggression level, scaled by
## the difficulty attack tempo (higher difficulties march with smaller
## armies). A nearly-dead enemy base triggers an all-in with whatever is on
## hand.
func _wave_threshold(target: Node2D) -> int:
	var hp_ratio: float = float(target.get("_hp")) / maxf(1.0, float(target.get("max_hp")))
	if hp_ratio < 0.25:
		return 3
	var base: int
	match ai._aggression_level:
		"push":
			base = 4
		"balanced":
			base = 7
		_:
			base = 12  # defend: only march with a real army
	return maxi(3, int(round(base * GameManager.get_ai_wave_multiplier())))


func _defend_building() -> void:
	var building: Node2D = _get_building()
	if building == null:
		return
	if _nearest_enemy_unit(building.global_position, 650) == null:
		return
	for unit in ai.get_tree().get_nodes_in_group(team_name()):
		if not unit.data.is_fighter:
			continue
		if unit._state == Unit.State.IDLE or unit._state == Unit.State.MOVE:
			var threat: Unit = _pick_defense_target(unit)
			if threat != null:
				unit.attack_unit(threat)


## Which intruder a defender engages. Smarts tier 0 keeps the legacy behavior
## (each defender picks its own nearest threat so the defense spreads damage).
## Tier 1+ scores by hp_fraction * 1000 + distance and takes the minimum, so
## the defense focuses fire to finish wounded enemies first, with distance as
## the tiebreak to still spread across multiple intruders.
func _pick_defense_target(defender: Unit) -> Unit:
	if GameManager.get_ai_smarts() < 1:
		return _nearest_enemy_unit(defender.global_position, 650)
	var best: Unit = null
	var best_score: float = INF
	var other_team_name: String = "player" if ai.team == GameManager.Team.ENEMY else "enemy"
	for unit in ai.get_tree().get_nodes_in_group(other_team_name):
		if unit._state == Unit.State.DEAD:
			continue
		var d: float = unit.global_position.distance_to(defender.global_position)
		if d > 650.0:
			continue
		var hp_fraction: float = float(unit.hp) / maxf(1.0, float(unit.data.max_hp))
		var score: float = hp_fraction * 1000.0 + d
		if score < best_score:
			best_score = score
			best = unit
	return best


func _attempt_wall_breach() -> void:
	if ai._grid == null:
		return
	if ai._grid.get_wall_hp() <= 0:
		return
	var coin: int = EconomyManager.get_coin(ai.team)
	if coin <= 1000:
		return
	var level: int = EconomyManager.get_miner_level(ai.team)
	var remaining: int = ai._grid.count_accessible_unmined_tiles(ai.team, level)
	if remaining > 0:
		return
	# Wall timing calculus (smarts tier 2+): only breach when the combat
	# predictor says the army can win the fight that follows — otherwise keep
	# mining and mass a bigger wave first.
	if GameManager.get_ai_smarts() >= 2 and ai._smart._simulate_combat() < 1.1:
		return

	# Send 30% of idle miners to breach the nearest wall cell.
	var idle_miners: Array = []
	for unit in ai.get_tree().get_nodes_in_group(team_name()):
		if unit.data.is_miner and not ai._mining._is_busy(unit):
			idle_miners.append(unit)
	var breach_count: int = int(idle_miners.size() * 0.3)
	var wall_cells: Array[Vector2i] = ai._grid.get_wall_cells()
	if wall_cells.is_empty():
		return

	for i in range(min(breach_count, idle_miners.size())):
		var unit: Unit = idle_miners[i]
		var nearest: Vector2i = wall_cells[0]
		var best_dist: float = unit.global_position.distance_squared_to(ai._grid.grid_to_world(nearest))
		for j in range(1, wall_cells.size()):
			var d: float = unit.global_position.distance_squared_to(ai._grid.grid_to_world(wall_cells[j]))
			if d < best_dist:
				best_dist = d
				nearest = wall_cells[j]
		unit.mine_cell(nearest)


func _nearest_enemy_unit(pos: Vector2, max_dist: float) -> Unit:
	var best: Unit = null
	var best_d: float = max_dist * max_dist
	var other_team_name: String = "player" if ai.team == GameManager.Team.ENEMY else "enemy"
	for unit in ai.get_tree().get_nodes_in_group(other_team_name):
		if unit._state == Unit.State.DEAD:
			continue
		var d: float = unit.global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = unit
	return best


## Fighter-only variant: the post-defense counterattack tracks real threats,
## so a scouting pigeon or a stray miner walking by never trips it.
func _nearest_enemy_fighter(pos: Vector2, max_dist: float) -> Unit:
	var best: Unit = null
	var best_d: float = max_dist * max_dist
	var other_team_name: String = "player" if ai.team == GameManager.Team.ENEMY else "enemy"
	for unit in ai.get_tree().get_nodes_in_group(other_team_name):
		if not unit.data.is_fighter or unit._state == Unit.State.DEAD:
			continue
		var d: float = unit.global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = unit
	return best


func _get_building() -> Node2D:
	for b in ai.get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == ai.team:
			return b
	return null


func _get_enemy_building() -> Node2D:
	for b in ai.get_tree().get_nodes_in_group("buildings"):
		if b.get("team") != ai.team:
			return b
	return null


func team_name() -> String:
	return "player" if ai.team == GameManager.Team.PLAYER else "enemy"
