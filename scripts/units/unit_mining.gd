class_name UnitMining
extends RefCounted

# How long a cell stays on this miner's no-path blacklist before a retry.
const _UNREACHABLE_FORGET_MS: int = 10000
# Idle wait near the surface entry before re-scanning an exhausted mine.
const _EXHAUSTED_RETRY_SEC: float = 5.0

var unit: Unit

func _init(u: Unit) -> void:
	unit = u


func _process_mine(delta: float) -> void:
	var cell: GridWorld.Cell = unit._grid.get_cell(unit._target_cell)
	if cell == null or cell.type == GridWorld.CellType.EMPTY:
		# Already mined; idle or find next ore.
		unit._set_state(Unit.State.IDLE, "cell mined")
		return
	if unit.carried_coin >= unit.data.carry_capacity:
		unit._commands.deposit_coin()
		return
	if unit.get_effective_miner_level() < cell.miner_level_required:
		unit._release_claim()
		unit._set_state(Unit.State.IDLE, "miner level too low")
		return

	var cell_world: Vector2 = unit._grid.grid_to_world(unit._target_cell)
	if unit.global_position.distance_to(cell_world) > GridWorld.CELL_SIZE * 1.5:
		# Repath only when there is no path in flight (see _process_climb_up).
		if unit._path.is_empty():
			var adj: Vector2 = unit._navigation._nearest_adjacent_world(unit._target_cell)
			unit._navigation._repath(adj)
			if not unit._navigation._path_reaches(adj):
				_mark_cell_unreachable(unit._target_cell)
				unit._set_state(Unit.State.IDLE, "mine target unreachable")
				return
		unit._navigation._follow_path(delta)
		return

	unit._path.clear()
	unit._mine_target_angle = (cell_world - unit.global_position).angle()
	unit._mine_timer -= delta
	unit._mine_hit_flash -= delta
	unit.queue_redraw()
	if unit._mine_timer <= 0:
		unit._mine_timer = 1.0 / max(0.1, unit.data.mining_swings_per_sec)
		unit._mine_hit_flash = 0.08
		var dmg: int = max(1, unit.data.mining_damage)
		var coin: int = unit._grid.damage_cell(unit._target_cell, dmg, unit.get_effective_miner_level())
		AudioManager.play("pickaxe", unit.global_position, -10.0)
		if coin > 0:
			# Efficiency (Industrial): ore yields bonus gold per swing.
			coin = unit._abilities.apply_miner_ore_yield(coin)
			unit.carried_coin = min(unit.data.carry_capacity, unit.carried_coin + coin)
			unit.queue_redraw()


func _handle_idle_miner() -> void:
	# Full miners (and miners flagged with nothing left to dig) deposit at the
	# building. Otherwise surface miners climb down the ladder — digging only
	# happens inside the mine — and underground miners resume a pending mine
	# command or look for the next cell to dig.
	if unit.carried_coin >= unit.data.carry_capacity or (unit._deposit_requested and unit.carried_coin > 0):
		unit._commands.deposit_coin()
	elif not unit.is_underground:
		unit._commands.climb_down_ladder()
	elif unit._pending_mine_cell != Vector2i(-9999, -9999):
		unit._commands.mine_cell(unit._pending_mine_cell)
	elif unit._mine_exhausted:
		_idle_near_mine_entry()
	else:
		_find_and_mine()


func _find_and_mine() -> void:
	# If the bag is nearly full, cash in before starting a big ore tile that
	# would waste most of its value.
	if unit.carried_coin > 0 and (unit.data.carry_capacity - unit.carried_coin) < 5:
		unit._commands.deposit_coin()
		return

	var center: Vector2i = unit._grid.world_to_grid(unit.global_position)
	var team_dir: int = unit._vision._team_dir()
	var id: int = unit.get_instance_id()
	var now_ms: int = Time.get_ticks_msec()

	# Scan the whole own side (both sides once the wall is down) so no corner
	# of the mine is starved. Fog of War blind dig (Revamp Phase 1): miners
	# cannot see buried ore on their own — ore only counts as *discovered*
	# once it already yielded gold (hp < max_hp) or an Ore Sonar scan /
	# underground lantern revealed it (sonar_revealed). Discovered ore is
	# preferred at any distance; everything else is a blind pick, taken at
	# random from the nearest few diggable faces.
	var wall_intact: bool = unit._grid.get_wall_hp() > 0
	var x_lo: int = GridWorld.X_MIN if team_dir == -1 or not wall_intact else 2
	var x_hi: int = GridWorld.X_MAX if team_dir == 1 or not wall_intact else -2

	var best_gold: Vector2i = Vector2i(-9999, -9999)
	var best_gold_dist: float = INF
	var blind_candidates: Array = []  # [ [dist, pos], ... ] nearest-first later

	for x in range(x_lo, x_hi + 1):
		for y in range(1, GridWorld.Y_MAX + 1):
			var pos: Vector2i = Vector2i(x, y)
			var c: GridWorld.Cell = unit._grid.get_cell(pos)
			if c == null:
				continue
			if not GridMining._is_diggable_type(c.type):
				continue
			# Level gate enforced at seek time so miners never path to tiles
			# they can never dig.
			if unit.get_effective_miner_level() < c.miner_level_required:
				continue
			# Skip tiles another miner reserved.
			if not unit._grid.is_cell_claimable(pos, id):
				continue
			# Skip tiles this miner recently failed to reach.
			if unit._unreachable_cells.has(pos):
				if now_ms - unit._unreachable_cells[pos] < _UNREACHABLE_FORGET_MS:
					continue
				unit._unreachable_cells.erase(pos)
			# Fully surrounded tiles can't be stood next to yet.
			if not _has_empty_neighbor(pos):
				continue
			var d: float = center.distance_to(pos)
			var is_gold: bool = c.type == GridWorld.CellType.ORE or c.type == GridWorld.CellType.FRESH_ORE
			if is_gold and (c.hp < c.max_hp or c.sonar_revealed.get(unit.team, false)) and not GridMining.is_depleted(c):
				# Discovered gold: this tile already yielded coin, an Ore
				# Sonar scan revealed it, or an underground lantern lit it —
				# so the miner knows it is worth coming back to. Depleted
				# veins (Revamp Phase 4) fall back to blind picks.
				if d < best_gold_dist:
					best_gold_dist = d
					best_gold = pos
			else:
				blind_candidates.append([d, pos])

	if best_gold != Vector2i(-9999, -9999):
		unit._commands.mine_cell(best_gold)
		return
	if not blind_candidates.is_empty():
		# Blind dig: no discovered ore anywhere, so pick randomly among the
		# nearest few diggable faces instead of beelining to the closest one.
		blind_candidates.sort_custom(func(a, b): return a[0] < b[0])
		var pick_from: Array = blind_candidates.slice(0, mini(6, blind_candidates.size()))
		unit._commands.mine_cell(pick_from[randi() % pick_from.size()][1])
		return

	# Nothing diggable remains in range: cash in any cargo, then wait near the
	# shaft instead of thrashing up and down. AI miners re-scan on a tighter
	# interval (perfect worker allocation — the AI never idles long).
	unit._mine_exhausted = true
	unit._exhausted_retry_timer = Constants.ENEMY_MINER_RESCAN_INTERVAL if unit.team == GameManager.Team.ENEMY else _EXHAUSTED_RETRY_SEC
	if unit.carried_coin > 0:
		unit._commands.deposit_coin()
	else:
		_idle_near_mine_entry()


## A tile was destroyed (by anyone). It may have opened a new route or ore
## pocket, so drop the exhausted flag and forget any blacklist for that cell.
func _on_cell_destroyed(grid_pos: Vector2i) -> void:
	unit._mine_exhausted = false
	unit._unreachable_cells.erase(grid_pos)


## Exhausted-mine idle: only surface to cash in cargo. Empty-handed miners wait
## near the shaft bottom so the retry timer can re-open the seek without a
## pointless climb up and down.
func _idle_near_mine_entry() -> void:
	var entry: Node2D = unit._nearest_friendly_mine_entry()
	if entry == null:
		return
	if unit.is_underground:
		if unit.carried_coin > 0:
			unit._commands.climb_up_ladder()
		else:
			var bottom: Vector2 = entry.call("get_ladder_bottom")
			if unit.global_position.distance_to(bottom) > GridWorld.CELL_SIZE * 1.5:
				unit._commands.move_to(bottom)
		return
	if unit.global_position.distance_to(entry.global_position) > GridWorld.CELL_SIZE * 2.0:
		unit._commands.move_to(entry.global_position)


func _mark_cell_unreachable(grid_pos: Vector2i) -> void:
	DebugLog.log_reject("Unit %d" % unit.get_instance_id(), "mine_cell", "no path to " + str(grid_pos))
	unit._unreachable_cells[grid_pos] = Time.get_ticks_msec()
	unit._release_claim()


## True while the cell is on this miner's no-path blacklist (the AI consults
## this so it doesn't re-order cells the miner already failed to reach).
func is_cell_blacklisted(grid_pos: Vector2i) -> bool:
	if not unit._unreachable_cells.has(grid_pos):
		return false
	if Time.get_ticks_msec() - unit._unreachable_cells[grid_pos] >= _UNREACHABLE_FORGET_MS:
		unit._unreachable_cells.erase(grid_pos)
		return false
	return true


func _has_empty_neighbor(grid_pos: Vector2i) -> bool:
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not unit._grid.is_solid(grid_pos + off):
			return true
	return false
