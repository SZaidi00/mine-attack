class_name GridWorld
extends Node2D

signal cell_destroyed(grid_pos: Vector2i)
signal wall_hp_changed(current: int, maximum: int)

enum CellType { EMPTY, SURFACE_GROUND, DIRT, ORE, WALL }

class Cell:
	var type: CellType = CellType.EMPTY
	var hp: int = 0
	var max_hp: int = 0
	var layer: int = 0
	var miner_level_required: int = 1
	var coin_value: int = 0
	var is_wall: bool = false

	func _init(t: CellType, l: int = 0, ml: int = 1, hp_val: int = 0, coin: int = 0, wall: bool = false):
		type = t
		layer = l
		miner_level_required = ml
		hp = hp_val
		max_hp = hp_val
		coin_value = coin
		is_wall = wall

const _Constants = preload("res://scripts/autoload/constants.gd")

const CELL_SIZE: int = _Constants.TILE_SIZE

# Map bounds in grid coordinates.
const X_MIN: int = _Constants.GRID_X_MIN
const X_MAX: int = _Constants.GRID_X_MAX
const Y_MIN: int = _Constants.GRID_Y_MIN
const Y_MAX: int = _Constants.GRID_Y_MAX

# Central wall is a single objective with shared HP (GDD: 2000 HP).
const WALL_HP_TOTAL: int = _Constants.WALL_HP

var _cells: Dictionary = {}  # Vector2i -> Cell
var _astar: AStarGrid2D = AStarGrid2D.new()

var _wall_hp: int = WALL_HP_TOTAL
var _wall_max_hp: int = WALL_HP_TOTAL
var _central_wall_cells: Array[Vector2i] = []


func _ready() -> void:
	_generate_map()
	_init_astar()
	queue_redraw()


func _generate_map() -> void:
	# Surface ground.
	for x in range(X_MIN, X_MAX + 1):
		_set_cell(Vector2i(x, 0), Cell.new(CellType.SURFACE_GROUND, 0, 99, 9999, 0))

	# Underground layers: 3 rows per layer => 7 layers total.
	for y in range(1, Y_MAX + 1):
		var layer: int = (y - 1) / 3 + 1
		var ml_req: int = _layer_miner_level(layer)
		var tile_hp: int = _Constants.LAYER_TILE_HP[layer]

		for x in range(X_MIN, X_MAX + 1):
			# Central wall (3 tiles thick).
			if x in [-1, 0, 1]:
				var pos: Vector2i = Vector2i(x, y)
				_set_cell(pos, Cell.new(CellType.WALL, layer, 1, 9999, 0, true))
				_central_wall_cells.append(pos)
				continue

			# Ore chance rises with depth.
			var is_ore: bool = randf() < (0.05 + layer * 0.03)
			if is_ore:
				var coin_range: Vector2i = _Constants.LAYER_COIN_RANGES[layer]
				var coin: int = randi_range(coin_range.x, coin_range.y)
				_set_cell(Vector2i(x, y), Cell.new(CellType.ORE, layer, ml_req, tile_hp, coin))
			else:
				_set_cell(Vector2i(x, y), Cell.new(CellType.DIRT, layer, ml_req, tile_hp, 0))

	# Entry shafts (empty vertical corridors for own mine entry).
	_carve_shaft(-15)
	_carve_shaft(15)

	# Border walls.
	for y in range(Y_MIN, Y_MAX + 1):
		_set_cell(Vector2i(X_MIN - 1, y), Cell.new(CellType.WALL, 0, 99, 9999, 0, true))
		_set_cell(Vector2i(X_MAX + 1, y), Cell.new(CellType.WALL, 0, 99, 9999, 0, true))
	for x in range(X_MIN - 1, X_MAX + 2):
		_set_cell(Vector2i(x, Y_MAX + 1), Cell.new(CellType.WALL, 0, 99, 9999, 0, true))


func _layer_miner_level(layer: int) -> int:
	if layer <= 2:
		return 1
	if layer <= 4:
		return 2
	return 3





func _init_astar() -> void:
	_astar.region = Rect2i(X_MIN - 1, Y_MIN, (X_MAX - X_MIN) + 3, Y_MAX + 2)
	_astar.cell_size = Vector2(CELL_SIZE, CELL_SIZE)
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for pos in _cells.keys():
		_astar.set_point_solid(pos, _is_solid_cell(_cells[pos]))


func _set_cell(grid_pos: Vector2i, cell: Cell) -> void:
	_cells[grid_pos] = cell


func _carve_shaft(x: int) -> void:
	for y in range(1, 7):
		var pos: Vector2i = Vector2i(x, y)
		_cells.erase(pos)


func _is_solid_cell(cell: Cell) -> bool:
	if cell == null or cell.type == CellType.EMPTY:
		return false
	# Surface ground is walkable, not an obstacle.
	if cell.type == CellType.SURFACE_GROUND:
		return false
	return cell.hp > 0


func get_cell(grid_pos: Vector2i) -> Cell:
	return _cells.get(grid_pos)


func is_solid(grid_pos: Vector2i) -> bool:
	var cell: Cell = _cells.get(grid_pos)
	return _is_solid_cell(cell)


func has_cell(grid_pos: Vector2i) -> bool:
	return _cells.has(grid_pos)


func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / CELL_SIZE), floor(world_pos.y / CELL_SIZE))


func grid_to_world(grid_pos: Vector2i, centered: bool = true) -> Vector2:
	if centered:
		return Vector2(grid_pos.x * CELL_SIZE + CELL_SIZE / 2.0, grid_pos.y * CELL_SIZE + CELL_SIZE / 2.0)
	return Vector2(grid_pos.x * CELL_SIZE, grid_pos.y * CELL_SIZE)


func find_path(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	var start: Vector2i = world_to_grid(from_world)
	var end: Vector2i = world_to_grid(to_world)
	if not _astar.is_in_boundsv(start) or not _astar.is_in_boundsv(end):
		return PackedVector2Array()
	var grid_path: PackedVector2Array = _astar.get_point_path(start, end)
	# Convert from cell-center positions to world positions.
	var world_path: PackedVector2Array = PackedVector2Array()
	for p in grid_path:
		world_path.append(p)
	return world_path


func damage_cell(grid_pos: Vector2i, damage: int, miner_level: int) -> int:
	var cell: Cell = _cells.get(grid_pos)
	if cell == null:
		return 0
	if cell.type == CellType.SURFACE_GROUND:
		return 0
	if miner_level < cell.miner_level_required:
		return 0

	if cell.is_wall:
		return _damage_wall(grid_pos, damage, miner_level)

	cell.hp -= damage
	if cell.hp <= 0:
		var coin: int = cell.coin_value
		_cells.erase(grid_pos)
		_astar.set_point_solid(grid_pos, false)
		queue_redraw()
		cell_destroyed.emit(grid_pos)
		return coin
	queue_redraw()
	return 0


func _damage_wall(grid_pos: Vector2i, damage: int, miner_level: int) -> int:
	# Only the central wall uses the shared HP pool.
	if not _central_wall_cells.has(grid_pos):
		return 0

	# Walls take reduced damage from low-level miners.
	var applied: int = max(1, damage * miner_level)
	_wall_hp -= applied
	wall_hp_changed.emit(_wall_hp, _wall_max_hp)

	if _wall_hp <= 0:
		for pos in _central_wall_cells:
			_cells.erase(pos)
			_astar.set_point_solid(pos, false)
		_central_wall_cells.clear()
		_wall_hp = 0
		queue_redraw()
		cell_destroyed.emit(grid_pos)
	else:
		queue_redraw()
	return 0


func is_wall(grid_pos: Vector2i) -> bool:
	var cell: Cell = _cells.get(grid_pos)
	return cell != null and cell.is_wall


func is_central_wall(grid_pos: Vector2i) -> bool:
	return _central_wall_cells.has(grid_pos)


func get_wall_cells() -> Array[Vector2i]:
	return _central_wall_cells.duplicate()


func get_wall_hp() -> int:
	return _wall_hp


func get_wall_max_hp() -> int:
	return _wall_max_hp


func get_wall_hp_ratio() -> float:
	if _wall_max_hp <= 0:
		return 0.0
	return float(_wall_hp) / float(_wall_max_hp)


func get_layer_at(grid_pos: Vector2i) -> int:
	var cell: Cell = _cells.get(grid_pos)
	if cell == null:
		return 0
	return cell.layer


func count_accessible_unmined_tiles(side: int, miner_level: int) -> int:
	var max_layer: int = _Constants.MINER_STATS[miner_level].max_layer
	var team_dir: int = -1 if side == GameManager.Team.PLAYER else 1
	var count: int = 0
	for pos in _cells.keys():
		var cell: Cell = _cells[pos]
		if cell.type != CellType.DIRT and cell.type != CellType.ORE:
			continue
		if cell.layer > max_layer:
			continue
		# Player side: x < 0; enemy side: x > 0.
		if pos.x * team_dir < 0:
			count += 1
	return count


func _draw() -> void:
	# Background fill for underground.
	draw_rect(Rect2((X_MIN - 1) * CELL_SIZE, CELL_SIZE, (X_MAX - X_MIN + 3) * CELL_SIZE, Y_MAX * CELL_SIZE), GameManager.COLOR_SHADOW, true)

	for pos in _cells.keys():
		var cell: Cell = _cells[pos]
		var rect: Rect2 = Rect2(pos.x * CELL_SIZE, pos.y * CELL_SIZE, CELL_SIZE, CELL_SIZE)
		match cell.type:
			CellType.SURFACE_GROUND:
				draw_rect(rect, GameManager.COLOR_ICE, true)
				# Surface outline.
				draw_rect(rect, GameManager.COLOR_STEEL, false, 1.0)
			CellType.DIRT:
				draw_rect(rect, _dirt_color(cell.layer), true)
			CellType.ORE:
				draw_rect(rect, _dirt_color(cell.layer), true)
				# Ore nugget.
				var inner: Rect2 = rect.grow(-8)
				draw_rect(inner, GameManager.COLOR_RUST, true)
			CellType.WALL:
				draw_rect(rect, GameManager.COLOR_STEEL, true)
				draw_rect(rect, GameManager.COLOR_SHADOW, false, 2.0)


	# Central wall HP bar.
	if _wall_hp > 0:
		var bar_w: float = 200
		var bar_h: float = 12
		var bar_x: float = -bar_w / 2.0
		var bar_y: float = 16
		draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color.BLACK, true)
		var wall_pct: float = get_wall_hp_ratio()
		draw_rect(Rect2(bar_x, bar_y, bar_w * wall_pct, bar_h), Color.ORANGE_RED, true)
		draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color.WHITE, false, 1.0)


func _dirt_color(layer: int) -> Color:
	if layer <= 2:
		return GameManager.COLOR_DIRT_1
	if layer <= 4:
		return GameManager.COLOR_DIRT_2
	return GameManager.COLOR_DIRT_3
