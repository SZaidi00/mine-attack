class_name AIAwareness
extends RefCounted

## Revamp Phase 8: the AI's awareness behaviors — scouting the enemy's hidden
## faction, placing defensive lanterns, and reacting to weather/terrain
## warnings. Runs on the controller's 1s awareness tick; weather reactions are
## signal-driven (the AI gets the same warning time as the player — no
## cheating).

const _Constants = preload("res://scripts/autoload/constants.gd")
const _LANTERN_SCENE: PackedScene = preload("res://scenes/lantern.tscn")

var ai: AIController

# Miners currently under shelter orders (snowstorm recall / lava evacuation).
# Entries are Unit refs; dead or freed units are pruned on each upkeep pass.
var _sheltered_miners: Array = []
var _lantern_tick: float = 0.0

func _init(a: AIController) -> void:
	ai = a


## 1s tick from AIController._process.
func _run_awareness(delta: float) -> void:
	_run_scouting()
	_run_shelter_upkeep()
	_lantern_tick += delta
	if _lantern_tick >= _Constants.ENEMY_LANTERN_INTERVAL:
		_lantern_tick = 0.0
		_run_lantern_placement()


# ─── Scouting ───

## Sends one swordsman at the enemy base to identify its hidden faction
## (revamp.md 9.2): first scout at the 1:00 mark, a replacement
## ENEMY_SCOUT_RETRY_DELAY after the previous scout dies. The scout attack-
## moves (ATTACK state), so the wave/defense logic — which only sweeps IDLE
## and MOVE units — leaves it alone.
func _run_scouting() -> void:
	var their_team: GameManager.Team = GameManager.Team.PLAYER if ai.team == GameManager.Team.ENEMY else GameManager.Team.ENEMY
	if FactionManager.is_faction_identified(their_team):
		ai._scout = null  # mission accomplished; the scout rejoins the army
		return
	if ai._scout != null:
		if is_instance_valid(ai._scout) and ai._scout._state != Unit.State.DEAD:
			return  # en route
		ai._scout = null
		ai._next_scout_time = GameManager.match_time + _Constants.ENEMY_SCOUT_RETRY_DELAY
	if GameManager.match_time < ai._next_scout_time:
		return
	var target_building: Node2D = ai._combat._get_enemy_building()
	if target_building == null:
		return
	var scout: Unit = _pick_scout()
	if scout == null:
		return  # no swordsman yet — retry next tick, no delay penalty
	scout.attack_building(target_building)
	if scout._state == Unit.State.ATTACK:
		ai._scout = scout


## The scout is a swordsman (cheap, fast, expendable): prefer an idle surface
## one so defense and waves keep their engaged fighters.
func _pick_scout() -> Unit:
	var fallback: Unit = null
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if not unit.data.is_fighter or unit._state == Unit.State.DEAD:
			continue
		if unit.data.unit_name.to_lower() != "swordsman":
			continue
		if unit.is_underground:
			continue
		if unit._state == Unit.State.IDLE:
			return unit
		if fallback == null:
			fallback = unit
	return fallback


# ─── Lantern placement ───

## Places surface lanterns covering the base + mine entrance (revamp.md 9.2):
## T1 early (cheap vision), then upgrades the oldest lantern to T2 once the
## economy comfortably affords it. Uses the same reserve rule as the economy
## tick so lantern spending never stalls the miner upgrades.
func _run_lantern_placement() -> void:
	var building: Node2D = ai._combat._get_building()
	if building == null:
		return
	var lanterns: Array = _own_surface_lanterns()
	var reserve: int = 0
	var level: int = EconomyManager.get_miner_level(ai.team)
	if _Constants.MINER_UPGRADE_COSTS.has(level + 1):
		reserve = _Constants.MINER_UPGRADE_COSTS[level + 1]
	var coin: int = EconomyManager.get_coin(ai.team)
	if lanterns.size() < _Constants.LANTERN_MAX_COUNT:
		var cost: int = Lantern.cost_for(false, 1)
		if coin - reserve < cost + _Constants.ENEMY_LANTERN_BUFFER:
			return
		var cell: Vector2i = _pick_lantern_cell(building)
		if cell == Vector2i(-9999, -9999):
			return
		if not EconomyManager.spend_coin(ai.team, cost):
			return
		var lantern: Lantern = _LANTERN_SCENE.instantiate()
		lantern.team = ai.team
		lantern.is_underground_lantern = false
		lantern.total_cost = cost
		lantern.global_position = ai._grid.grid_to_world(cell)
		ai.get_node("/root/Main/Structures").add_child(lantern)
		DebugLog.log_command("AIController", "build", "lantern at %s" % str(cell))
	elif coin - reserve >= Lantern.cost_for(false, 2) + _Constants.ENEMY_LANTERN_UPGRADE_BUFFER:
		# All slots filled: upgrade the lowest-tier built lantern first (T1 → T2,
		# then T2 → T3), spreading investment across coverage rather than maxing
		# one lantern early.
		for tier in [1, 2]:
			for lantern: Lantern in lanterns:
				if lantern.tier == tier and lantern.can_upgrade():
					var upgrade_cost: int = Lantern.cost_for(false, tier + 1)
					if not EconomyManager.spend_coin(ai.team, upgrade_cost):
						return
					lantern.total_cost += upgrade_cost
					lantern.upgrade()
					DebugLog.log_command("AIController", "build", "lantern upgraded to T%d at %s" % [lantern.tier, str(ai._grid.world_to_grid(lantern.global_position))])
					return


## Best surface cell for the next lantern: minimizes the worst-case distance
## to the base and the mine entrance (coverage of both), with a small bonus
## for cells toward the map center (forward vision against incoming waves).
func _pick_lantern_cell(building: Node2D) -> Vector2i:
	var team_dir: int = 1 if ai.team == GameManager.Team.ENEMY else -1
	var base_cell: Vector2i = ai._grid.world_to_grid(building.global_position)
	var mine_cell: Vector2i = base_cell
	var entry: Node2D = _get_mine_entry()
	if entry != null:
		mine_cell = ai._grid.world_to_grid(entry.get_surface_position())
	var best: Vector2i = Vector2i(-9999, -9999)
	var best_score: float = INF
	for x in range(GridWorld.X_MIN, GridWorld.X_MAX + 1):
		var cell := Vector2i(x, 0)
		if not _lantern_cell_valid(cell, base_cell, mine_cell):
			continue
		var score: float = maxf(cell.distance_to(base_cell), cell.distance_to(mine_cell)) \
			- team_dir * cell.x * 0.1
		if score < best_score:
			best_score = score
			best = cell
	return best


## Mirrors the player-side placement rules (_lantern_placement_error in
## player_build_placement.gd), flipped to the AI's half of the map.
func _lantern_cell_valid(cell: Vector2i, base_cell: Vector2i, mine_cell: Vector2i) -> bool:
	if cell.y != 0:
		return false
	var team_dir: int = 1 if ai.team == GameManager.Team.ENEMY else -1
	if cell.x * team_dir < 2:
		return false  # own half only (center wall columns are neutral)
	# Keep clear of the building sprite and the mine entry.
	if cell.distance_to(base_cell) < 2.0 or cell.distance_to(mine_cell) < 1.5:
		return false
	for lantern: Lantern in _own_surface_lanterns():
		var other: Vector2i = ai._grid.world_to_grid(lantern.global_position)
		if other == cell or Vector2(other - cell).length() < _Constants.LANTERN_MIN_DISTANCE:
			return false
	for group in ["towers", "walls"]:
		for structure in ai.get_tree().get_nodes_in_group(group):
			if ai._grid.world_to_grid(structure.global_position) == cell:
				return false
	return true


func _own_surface_lanterns() -> Array:
	var result: Array = []
	for lantern in ai.get_tree().get_nodes_in_group("lanterns"):
		if lantern.team == ai.team and not lantern.is_underground_lantern:
			result.append(lantern)
	return result


func _get_mine_entry() -> Node2D:
	for entry in ai.get_tree().get_nodes_in_group("mine_entries"):
		if entry.get("team") == ai.team:
			return entry
	return null


# ─── Weather & terrain response ───

## Snowstorm warning (Phase 5/8): recall all surface miners into a friendly
## lantern's shelter radius — the AI gets the same warning time as the
## player. Underground miners are unaffected by the storm and keep digging.
func _on_snowstorm_warning(_seconds: float) -> void:
	if not GameManager.game_active:
		return
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if not unit.data.is_miner or unit._state == Unit.State.DEAD or unit.is_underground:
			continue
		_shelter_miner(unit)


func _on_snowstorm_ended() -> void:
	_release_sheltered_miners()


## Lava warning (Phase 4/8): evacuate the underground layers that the next
## rise might flood. Because the flood now follows a cosine wave, use the
## highest the lava can reach (lowest y) across all columns so no miner is left
## in a peak. Miners climb out and hold at the mine entrance until the lava
## recedes.
func _on_lava_warning(_seconds: float, layers: int = 2) -> void:
	if not GameManager.game_active:
		return
	var flood_top: int = ai._grid.get_lava_warning_top_min()
	if flood_top > GridWorld.Y_MAX:
		# No wave profile yet (direct test hook or pre-rise call): fall back to
		# the flat layer count passed with the signal.
		flood_top = GridWorld.Y_MAX - layers * _Constants.ROWS_PER_LAYER + 1
	if flood_top > GridWorld.Y_MAX:
		return
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if not unit.data.is_miner or unit._state == Unit.State.DEAD or not unit.is_underground:
			continue
		if ai._grid.world_to_grid(unit.global_position).y >= flood_top:
			_shelter_miner(unit)


func _on_lava_receded() -> void:
	_release_sheltered_miners()


## Volcano warning: recall all surface units (miners and fighters) into shelter
## the same way snowstorms do. Underground units are already safe from meteors.
func _on_volcano_warning(_seconds: float) -> void:
	if not GameManager.game_active:
		return
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if unit._state == Unit.State.DEAD or unit.is_underground:
			continue
		_shelter_miner(unit)


func _on_volcano_ended() -> void:
	_release_sheltered_miners()


func _shelter_miner(unit: Unit) -> void:
	if unit.shelter_in_place:
		return
	unit.shelter_in_place = true
	_sheltered_miners.append(unit)
	# Order immediately when the miner is between tasks; busy miners are
	# picked up by the upkeep pass the moment they fall idle.
	if unit.is_underground:
		if unit._state == Unit.State.IDLE:
			unit.climb_up_ladder()
	elif unit._state == Unit.State.IDLE or unit._state == Unit.State.MOVE:
		unit.move_to(_shelter_target(unit))


## Releases all shelter orders; idle miners are picked up by the next mining
## tick (ai_mining skips them only while shelter_in_place is set).
func _release_sheltered_miners() -> void:
	for unit: Unit in _sheltered_miners:
		if is_instance_valid(unit):
			unit.shelter_in_place = false
	_sheltered_miners.clear()


## Keeps shelter orders in force: a miner that reached its spot goes IDLE and
## would otherwise be re-tasked by its own idle handler. Re-issues the order
## until the matching end signal releases the unit.
func _run_shelter_upkeep() -> void:
	if _sheltered_miners.is_empty():
		return
	for unit: Unit in _sheltered_miners.duplicate():
		if not is_instance_valid(unit) or unit._state == Unit.State.DEAD:
			_sheltered_miners.erase(unit)
			continue
		if unit._state != Unit.State.IDLE:
			continue  # still following the last order
		if unit.is_underground:
			# Lava evacuee still below ground: climb out.
			unit.climb_up_ladder()
		else:
			unit.move_to(_shelter_target(unit))


## Where a sheltered miner holds: inside the nearest built friendly lantern's
## radius (storm shelter); the mine entrance or base as a fallback when no
## lantern stands yet.
func _shelter_target(unit: Unit) -> Vector2:
	var best: Node2D = null
	var best_dist: float = INF
	for lantern in ai.get_tree().get_nodes_in_group("lanterns"):
		if lantern.team != ai.team or lantern.is_underground_lantern or not lantern.is_built():
			continue
		var dist: float = lantern.global_position.distance_squared_to(unit.global_position)
		if dist < best_dist:
			best_dist = dist
			best = lantern
	if best != null:
		return best.global_position
	var entry: Node2D = _get_mine_entry()
	if entry != null:
		return entry.get_surface_position()
	var building: Node2D = ai._combat._get_building()
	return building.global_position if building != null else unit.global_position
