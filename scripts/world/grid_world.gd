class_name GridWorld
extends Node2D

signal cell_destroyed(grid_pos: Vector2i)

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

const CELL_SIZE: int = 32

# Map bounds in grid coordinates.
const X_MIN: int = -40
const X_MAX: int = 40
const Y_MIN: int = 0
const Y_MAX: int = 14

var _cells: Dictionary = {}  # Vector2i -> Cell
var _astar: AStarGrid2D = AStarGrid2D.new()


func _ready() -> void:
	_generate_map()
	_init_astar()
	queue_redraw()


func _generate_map() -> void:
	# Surface ground.
	for x in range(X_MIN, X_MAX + 1):
		_set_cell(Vector2i(x, 0), Cell.new(CellType.SURFACE_GROUND, 0, 99, 9999, 0))

	# Underground layers.
	for y in range(1, Y_MAX + 1):
		var layer: int = (y - 1) / 2 + 1
		var ml_req: int = 1
		if layer >= 3 and layer <= 4:
			ml_req = 2
		elif layer >= 5:
			ml_req = 3
		var base_hp: int = 30 + layer * 10
		var base_coin: int = 5 + layer * 3

		for x in range(X_MIN, X_MAX + 1):
			# Central wall (3 tiles thick).
			if x in [-1, 0, 1]:
				_set_cell(Vector2i(x, y), Cell.new(CellType.WALL, layer, 1, 400, 0, true))
				continue

			# Ore chance rises with depth.
			var is_ore: bool = randf() < (0.08 + layer * 0.02)
			if is_ore:
				var coin: int = base_coin + randi_range(0, layer * 2)
				_set_cell(Vector2i(x, y), Cell.new(CellType.ORE, layer, ml_req, base_hp, coin))
			else:
				_set_cell(Vector2i(x, y), Cell.new(CellType.DIRT, layer, ml_req, base_hp, 0))

	# Entry shafts (empty vertical corridors for own mine entry).
	_carve_shaft(-15)
	_carve_shaft(15)

	# Border walls.
	for y in range(Y_MIN, Y_MAX + 1):
		_set_cell(Vector2i(X_MIN - 1, y), Cell.new(CellType.WALL, 0, 99, 9999, 0, true))
		_set_cell(Vector2i(X_MAX + 1, y), Cell.new(CellType.WALL, 0, 99, 9999, 0, true))
	for x in range(X_MIN - 1, X_MAX + 2):
		_set_cell(Vector2i(x, Y_MAX + 1), Cell.new(CellType.WALL, 0, 99, 9999, 0, true))


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
	for y in range(1, 5):
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
		# Walls take reduced damage from low-level miners.
		damage = max(1, damage * miner_level)

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


func is_wall(grid_pos: Vector2i) -> bool:
	var cell: Cell = _cells.get(grid_pos)
	return cell != null and cell.is_wall


func get_layer_at(grid_pos: Vector2i) -> int:
	var cell: Cell = _cells.get(grid_pos)
	if cell == null:
		return 0
	return cell.layer


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


func _dirt_color(layer: int) -> Color:
	if layer <= 2:
		return GameManager.COLOR_DIRT_1
	if layer <= 4:
		return GameManager.COLOR_DIRT_2
	return GameManager.COLOR_DIRT_3
