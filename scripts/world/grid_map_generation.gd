class_name GridMapGeneration
extends RefCounted

var grid: GridWorld

func _init(g: GridWorld) -> void:
	grid = g


func _generate_map() -> void:
	if Constants.DEBUG and Constants.DEBUG_SEED >= 0:
		seed(Constants.DEBUG_SEED)
	# Surface ground.
	for x in range(grid.X_MIN, grid.X_MAX + 1):
		_set_cell(Vector2i(x, 0), GridWorld.Cell.new(GridWorld.CellType.SURFACE_GROUND, 0, 99, 9999, 0))

	# Underground layers: 3 rows per layer => 7 layers total.
	for y in range(1, grid.Y_MAX + 1):
		var layer: int = (y - 1) / 3 + 1
		var ml_req: int = _layer_miner_level(layer)
		var tile_hp: int = grid._Constants.LAYER_TILE_HP[layer]

		for x in range(grid.X_MIN, grid.X_MAX + 1):
			# Central wall (3 tiles thick).
			if x in [-1, 0, 1]:
				var pos: Vector2i = Vector2i(x, y)
				_set_cell(pos, GridWorld.Cell.new(GridWorld.CellType.WALL, layer, 1, 9999, 0, true))
				grid._central_wall_cells.append(pos)
				continue

			# Ore chance rises with depth.
			var is_ore: bool = randf() < (0.10 + layer * 0.05)
			if is_ore:
				var coin_range: Vector2i = grid._Constants.LAYER_COIN_RANGES[layer]
				var coin: int = randi_range(coin_range.x, coin_range.y)
				_set_cell(Vector2i(x, y), GridWorld.Cell.new(GridWorld.CellType.ORE, layer, ml_req, tile_hp, coin))
			else:
				_set_cell(Vector2i(x, y), GridWorld.Cell.new(GridWorld.CellType.DIRT, layer, ml_req, tile_hp, 0))

	# Entry shafts (empty vertical corridors for own mine entry).
	carve_shaft(-15)
	carve_shaft(15)

	# Border walls.
	for y in range(grid.Y_MIN, grid.Y_MAX + 1):
		_set_cell(Vector2i(grid.X_MIN - 1, y), GridWorld.Cell.new(GridWorld.CellType.WALL, 0, 99, 9999, 0, true))
		_set_cell(Vector2i(grid.X_MAX + 1, y), GridWorld.Cell.new(GridWorld.CellType.WALL, 0, 99, 9999, 0, true))
	for x in range(grid.X_MIN - 1, grid.X_MAX + 2):
		_set_cell(Vector2i(x, grid.Y_MAX + 1), GridWorld.Cell.new(GridWorld.CellType.WALL, 0, 99, 9999, 0, true))


func _layer_miner_level(layer: int) -> int:
	if layer <= 2:
		return 1
	if layer <= 4:
		return 2
	return 3


func _init_astar() -> void:
	grid._astar.region = Rect2i(grid.X_MIN - 1, grid.Y_MIN, (grid.X_MAX - grid.X_MIN) + 3, grid.Y_MAX + 2)
	grid._astar.cell_size = Vector2(grid.CELL_SIZE, grid.CELL_SIZE)
	grid._astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid._astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid._astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	# get_point_path returns point * cell_size + offset; offset by half a cell
	# so path points land on cell centers, matching grid_to_world() and every
	# arrival threshold in unit movement code.
	grid._astar.offset = Vector2(grid.CELL_SIZE, grid.CELL_SIZE) * 0.5
	grid._astar.update()
	for pos in grid._cells.keys():
		grid._astar.set_point_solid(pos, _is_solid_cell(grid._cells[pos]))


func _set_cell(grid_pos: Vector2i, cell: GridWorld.Cell) -> void:
	grid._cells[grid_pos] = cell


## Public shaft carving. The default columns match the default map, but
## MineEntry can carve its own shaft wherever it actually sits.
func carve_shaft(x: int, y_from: int = 1, y_to: int = 6) -> void:
	for y in range(y_from, y_to + 1):
		var pos: Vector2i = Vector2i(x, y)
		grid._cells.erase(pos)
		if grid._astar.is_in_boundsv(pos):
			grid._astar.set_point_solid(pos, false)
	grid.queue_redraw()


func _is_solid_cell(cell: GridWorld.Cell) -> bool:
	if cell == null or cell.type == GridWorld.CellType.EMPTY:
		return false
	# Surface ground is walkable, not an obstacle.
	if cell.type == GridWorld.CellType.SURFACE_GROUND:
		return false
	return cell.hp > 0
