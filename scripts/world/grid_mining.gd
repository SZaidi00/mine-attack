class_name GridMining
extends RefCounted

var grid: GridWorld

func _init(g: GridWorld) -> void:
	grid = g


## Reserves a diggable cell for a miner so auto-seek spreads miners across
## tiles instead of dogpiling one. The claim lives on the Cell and dies with
## it when the tile is mined out.
func claim_cell(grid_pos: Vector2i, unit_id: int) -> void:
	var cell: GridWorld.Cell = grid._cells.get(grid_pos)
	if cell != null:
		cell.claimed_by = unit_id


## Releases a miner's reservation. Only the claim holder can release it.
func release_cell(grid_pos: Vector2i, unit_id: int) -> void:
	var cell: GridWorld.Cell = grid._cells.get(grid_pos)
	if cell != null and cell.claimed_by == unit_id:
		cell.claimed_by = 0


## True when the cell exists and is unclaimed or already claimed by this unit.
func is_cell_claimable(grid_pos: Vector2i, unit_id: int) -> bool:
	var cell: GridWorld.Cell = grid._cells.get(grid_pos)
	return cell != null and (cell.claimed_by == 0 or cell.claimed_by == unit_id)


func damage_cell(grid_pos: Vector2i, damage: int, miner_level: int) -> int:
	var cell: GridWorld.Cell = grid._cells.get(grid_pos)
	if cell == null:
		return 0
	if cell.type == GridWorld.CellType.SURFACE_GROUND:
		return 0
	# Lava and cave-in rubble are indestructible (their level-99 gate would
	# catch this anyway, but keep the rule explicit).
	if cell.type == GridWorld.CellType.LAVA or cell.type == GridWorld.CellType.SOLID_ROCK:
		return 0
	if miner_level < cell.miner_level_required:
		return 0

	if cell.is_wall:
		return _damage_wall(grid_pos, damage, miner_level)

	# Ore trickles gold on every swing: each hit extracts a share proportional
	# to the damage dealt, and destruction pays out whatever is left, so the
	# tile always yields exactly coin_value in total. Revamp Phase 4: once a
	# vein is depleted (80% yielded) the per-swing share drops to 10% — the
	# destruction payout still pays the remainder, so totals stay exact.
	var coin: int = 0
	if (cell.type == GridWorld.CellType.ORE or cell.type == GridWorld.CellType.FRESH_ORE) and cell.coin_remaining > 0:
		var share: int = max(1, roundi(float(cell.coin_value) * float(damage) / float(cell.max_hp)))
		if is_depleted(cell):
			share = max(1, roundi(float(share) * grid._Constants.ORE_DEPLETED_YIELD_MULT))
		coin = mini(cell.coin_remaining, share)
		cell.coin_remaining -= coin

	cell.hp -= damage
	if cell.hp <= 0:
		coin += cell.coin_remaining
		grid._cells.erase(grid_pos)
		grid._astar.set_point_solid(grid_pos, false)
		# Dust burst marker: the cell is gone from _cells, so the underground
		# draw pass renders this as a destroy puff at the old rect.
		grid._cell_flash[grid_pos] = 0.2
		grid.queue_redraw()
		grid.cell_destroyed.emit(grid_pos)
		return coin
	grid._cell_flash[grid_pos] = 0.2
	grid.queue_redraw()
	return coin


func _damage_wall(grid_pos: Vector2i, damage: int, miner_level: int) -> int:
	# Only the central wall uses the shared HP pool.
	if not grid._central_wall_cells.has(grid_pos):
		return 0

	# Walls take reduced damage from low-level miners.
	var applied: int = max(1, damage * miner_level)
	grid._wall_hp -= applied
	grid.wall_hp_changed.emit(grid._wall_hp, grid._wall_max_hp)

	if grid._wall_hp <= 0:
		for pos in grid._central_wall_cells:
			grid._cells.erase(pos)
			grid._astar.set_point_solid(pos, false)
			# One-time breach explosion: a long dust burst over every wall cell
			# (they are erased from _cells, so the destroy-burst draw pass picks
			# them up) while the corridor opens.
			grid._cell_flash[pos] = 0.6
		grid._central_wall_cells.clear()
		grid._wall_hp = 0
		DebugLog.log_command("GridWorld", "wall_breach", "central wall destroyed — corridor open")
		grid.queue_redraw()
		grid.cell_destroyed.emit(grid_pos)
	else:
		grid.queue_redraw()
	return 0


## Revamp Phase 4: a vein is depleted once it has yielded ORE_DEPLETION_RATIO
## of its gold — per-swing trickle drops to a tenth and the nugget draws dull,
## so miners migrate to fresher tiles.
static func is_depleted(cell: GridWorld.Cell) -> bool:
	if cell == null or cell.coin_value <= 0:
		return false
	return cell.coin_remaining <= roundi(float(cell.coin_value) * (1.0 - Constants.ORE_DEPLETION_RATIO))


func count_accessible_unmined_tiles(side: int, miner_level: int) -> int:
	var max_layer: int = grid._Constants.MINER_STATS[miner_level].max_layer
	var team_dir: int = -1 if side == GameManager.Team.PLAYER else 1
	var count: int = 0
	for pos in grid._cells.keys():
		var cell: GridWorld.Cell = grid._cells[pos]
		if not _is_diggable_type(cell.type):
			continue
		if cell.layer > max_layer:
			continue
		# Player side: x < 0; enemy side: x > 0.
		if pos.x * team_dir < 0:
			count += 1
	return count


## Diggable underground tile types (Revamp Phase 4 adds magma rock / fresh ore).
static func _is_diggable_type(t: GridWorld.CellType) -> bool:
	return t == GridWorld.CellType.DIRT or t == GridWorld.CellType.ORE \
		or t == GridWorld.CellType.MAGMA_ROCK or t == GridWorld.CellType.FRESH_ORE


## Ore Sonar: marks every buried ORE/FRESH_ORE cell within `radius_cells` of
## `center` as revealed for `team`, so that team's miners treat it as
## discovered gold. Returns the number of newly revealed cells.
func reveal_ore_in_radius(center: Vector2i, radius_cells: int, team: GameManager.Team) -> int:
	var revealed: Array = []
	for x in range(center.x - radius_cells, center.x + radius_cells + 1):
		for y in range(center.y - radius_cells, center.y + radius_cells + 1):
			var pos: Vector2i = Vector2i(x, y)
			if Vector2(pos - center).length() > radius_cells:
				continue
			var cell: GridWorld.Cell = grid._cells.get(pos)
			if cell == null or (cell.type != GridWorld.CellType.ORE and cell.type != GridWorld.CellType.FRESH_ORE):
				continue
			if cell.sonar_revealed.get(team, false):
				continue
			cell.sonar_revealed[team] = true
			revealed.append(pos)
	if not revealed.is_empty():
		grid.queue_redraw()
		grid.cells_revealed.emit(revealed)
	return revealed.size()


func is_ore_revealed(grid_pos: Vector2i, team: GameManager.Team) -> bool:
	var cell: GridWorld.Cell = grid._cells.get(grid_pos)
	if cell == null or (cell.type != GridWorld.CellType.ORE and cell.type != GridWorld.CellType.FRESH_ORE):
		return false
	return cell.sonar_revealed.get(team, false)
