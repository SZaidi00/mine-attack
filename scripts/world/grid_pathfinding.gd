class_name GridPathfinding
extends RefCounted

var grid: GridWorld

func _init(g: GridWorld) -> void:
	grid = g


## True when the cell is inside the pathfinding region and not solid.
func is_walkable(grid_pos: Vector2i) -> bool:
	return grid._astar.is_in_boundsv(grid_pos) and not grid._astar.is_point_solid(grid_pos)


## Returns the walkable cell closest to to_cell, searching outward in
## Chebyshev rings up to max_radius. Returns to_cell unchanged when it is
## already walkable or when nothing walkable is found (check with is_walkable).
func nearest_walkable_cell(to_cell: Vector2i, max_radius: int = 4) -> Vector2i:
	if is_walkable(to_cell):
		return to_cell
	var best: Vector2i = to_cell
	var best_dist: float = INF
	for r in range(1, max_radius + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue  # Only the outer ring of each radius.
				var candidate: Vector2i = to_cell + Vector2i(dx, dy)
				if not is_walkable(candidate):
					continue
				var d: float = Vector2(candidate).distance_squared_to(Vector2(to_cell))
				if d < best_dist:
					best_dist = d
					best = candidate
			if best_dist < INF:
				break  # The first ring with any hit is the nearest one.
	return best


## Returns the walkable cells forming the ring just outside rect (grid coords).
## Used as interaction cells for reaching multi-cell structures.
func cells_adjacent_to_rect(rect: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(rect.position.x - 1, rect.end.x + 1):
		for y in [rect.position.y - 1, rect.end.y]:
			_add_if_walkable(cells, Vector2i(x, y))
	for y in range(rect.position.y, rect.end.y):
		for x in [rect.position.x - 1, rect.end.x]:
			_add_if_walkable(cells, Vector2i(x, y))
	return cells


func _add_if_walkable(cells: Array[Vector2i], grid_pos: Vector2i) -> void:
	if is_walkable(grid_pos) and not cells.has(grid_pos):
		cells.append(grid_pos)


func find_path(from_world: Vector2, to_world: Vector2, team: int = -1) -> PackedVector2Array:
	# Units and targets can drift slightly above the surface row (spawn jitter,
	# separation nudges, per-unit target offsets). Grid y = -1 is outside the
	# A* region, so snap back to the surface row instead of failing the path.
	from_world.y = maxf(from_world.y, 0.0)
	to_world.y = maxf(to_world.y, 0.0)
	var start: Vector2i = grid.world_to_grid(from_world)
	var end: Vector2i = grid.world_to_grid(to_world)
	if not grid._astar.is_in_boundsv(start) or not grid._astar.is_in_boundsv(end):
		return PackedVector2Array()
	# Revamp Phase 3: a placeable wall never blocks its owning team. A*
	# solidity is global, so the owner's seals are lifted for the duration of
	# the query and restored afterwards.
	var lifted: Array = []
	if team >= 0:
		for pos in grid._wall_sealed_cells:
			if grid._wall_sealed_cells[pos] == team:
				grid._astar.set_point_solid(pos, false)
				lifted.append(pos)
	var world_path: PackedVector2Array = _compute_path(start, end)
	for pos in lifted:
		grid._astar.set_point_solid(pos, true)
	return world_path


func _compute_path(start: Vector2i, end: Vector2i) -> PackedVector2Array:
	# Units and targets can sit on solid cells (a target cell that is an undug
	# tile, a unit pushed onto a blocked cell). Redirect to the nearest walkable
	# cell instead of failing the whole command.
	if not is_walkable(start):
		start = nearest_walkable_cell(start, 3)
	if not is_walkable(end):
		end = nearest_walkable_cell(end, 6)
	if not is_walkable(start) or not is_walkable(end):
		return PackedVector2Array()
	var grid_path: PackedVector2Array = grid._astar.get_point_path(start, end)
	# Convert from cell-center positions to world positions.
	var world_path: PackedVector2Array = PackedVector2Array()
	for p in grid_path:
		world_path.append(p)
	return world_path


## Revamp Phase 3: cells sealed by placeable walls (the column beneath each
## segment), mapped to the owning team. A* stays solid for everyone; find_path
## lifts the seals for the owning team so a wall never blocks its builder.
func seal_wall_cell(pos: Vector2i, team: GameManager.Team) -> void:
	if not grid._astar.is_in_boundsv(pos):
		return
	grid._wall_sealed_cells[pos] = team
	grid._astar.set_point_solid(pos, true)


func unseal_wall_cell(pos: Vector2i) -> void:
	if not grid._wall_sealed_cells.has(pos):
		return
	grid._wall_sealed_cells.erase(pos)
	if grid._astar.is_in_boundsv(pos):
		grid._astar.set_point_solid(pos, false)
