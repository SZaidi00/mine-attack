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
	# Instance id of the miner that reserved this cell (0 = unclaimed).
	var claimed_by: int = 0

	func _init(t: CellType, l: int = 0, ml: int = 1, hp_val: int = 0, coin: int = 0, wall: bool = false):
		type = t
		layer = l
		miner_level_required = ml
		hp = hp_val
		max_hp = hp_val
		coin_value = coin
		is_wall = wall

const _Constants = preload("res://scripts/autoload/constants.gd")

const _SKY_TEXTURE: Texture2D = preload("res://frost_mines_assets/backgrounds/surface_sky.png")
const _SURFACE_GROUND_TEXTURE: Texture2D = preload("res://frost_mines_assets/backgrounds/surface_ground.png")
const _UNDERGROUND_TEXTURE: Texture2D = preload("res://frost_mines_assets/backgrounds/underground_base.png")
const _WALL_TEXTURE: Texture2D = preload("res://frost_mines_assets/props/wall_segment.png")
const _LAYER_TILES: Array[Texture2D] = [
	preload("res://frost_mines_assets/tiles/layer_1_tile.png"),
	preload("res://frost_mines_assets/tiles/layer_2_tile.png"),
	preload("res://frost_mines_assets/tiles/layer_3_tile.png"),
	preload("res://frost_mines_assets/tiles/layer_4_tile.png"),
	preload("res://frost_mines_assets/tiles/layer_5_tile.png"),
	preload("res://frost_mines_assets/tiles/layer_6_tile.png"),
	preload("res://frost_mines_assets/tiles/layer_7_tile.png")
]

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

var _view_mode: PlayerController.ViewMode = PlayerController.ViewMode.SURFACE
var _cell_flash: Dictionary = {}  # Vector2i -> remaining flash time


func _ready() -> void:
	_generate_map()
	_init_astar()
	_connect_view_mode()
	queue_redraw()


func _process(delta: float) -> void:
	var expired: Array[Vector2i] = []
	for pos in _cell_flash.keys():
		_cell_flash[pos] -= delta
		if _cell_flash[pos] <= 0:
			expired.append(pos)
	if not expired.is_empty():
		for pos in expired:
			_cell_flash.erase(pos)
		queue_redraw()


func _connect_view_mode() -> void:
	var pc: PlayerController = get_node_or_null("/root/Main/PlayerController")
	if pc:
		if not pc.view_mode_changed.is_connected(_on_view_mode_changed):
			pc.view_mode_changed.connect(_on_view_mode_changed)
		_on_view_mode_changed(pc.get_current_view_mode())


func _on_view_mode_changed(mode: PlayerController.ViewMode) -> void:
	_view_mode = mode
	queue_redraw()


func _generate_map() -> void:
	if Constants.DEBUG and Constants.DEBUG_SEED >= 0:
		seed(Constants.DEBUG_SEED)
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


## True when the cell is inside the pathfinding region and not solid.
func is_walkable(grid_pos: Vector2i) -> bool:
	return _astar.is_in_boundsv(grid_pos) and not _astar.is_point_solid(grid_pos)


## Reserves a diggable cell for a miner so auto-seek spreads miners across
## tiles instead of dogpiling one. The claim lives on the Cell and dies with
## it when the tile is mined out.
func claim_cell(grid_pos: Vector2i, unit_id: int) -> void:
	var cell: Cell = _cells.get(grid_pos)
	if cell != null:
		cell.claimed_by = unit_id


## Releases a miner's reservation. Only the claim holder can release it.
func release_cell(grid_pos: Vector2i, unit_id: int) -> void:
	var cell: Cell = _cells.get(grid_pos)
	if cell != null and cell.claimed_by == unit_id:
		cell.claimed_by = 0


## True when the cell exists and is unclaimed or already claimed by this unit.
func is_cell_claimable(grid_pos: Vector2i, unit_id: int) -> bool:
	var cell: Cell = _cells.get(grid_pos)
	return cell != null and (cell.claimed_by == 0 or cell.claimed_by == unit_id)


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
	# Units and targets can sit on solid cells (a target cell that is an undug
	# tile, a unit pushed onto a blocked cell). Redirect to the nearest walkable
	# cell instead of failing the whole command.
	if not is_walkable(start):
		start = nearest_walkable_cell(start, 3)
	if not is_walkable(end):
		end = nearest_walkable_cell(end, 6)
	if not is_walkable(start) or not is_walkable(end):
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
		# Dust burst marker: the cell is gone from _cells, so the underground
		# draw pass renders this as a destroy puff at the old rect.
		_cell_flash[grid_pos] = 0.2
		queue_redraw()
		cell_destroyed.emit(grid_pos)
		return coin
	_cell_flash[grid_pos] = 0.2
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
	# Both layers are always drawn so the player can see surface activity and the
	# underground mine at the same time.
	_draw_surface()
	_draw_underground()


func _draw_surface() -> void:
	var world_left: float = (X_MIN - 1) * CELL_SIZE
	var world_right: float = (X_MAX + 2) * CELL_SIZE
	var world_width: float = world_right - world_left

	# Sky background.
	var sky_height: float = _SKY_TEXTURE.get_height()
	draw_texture_rect(_SKY_TEXTURE, Rect2(world_left, -sky_height, world_width, sky_height), true)

	# Surface ground background.
	var ground_height: float = _SURFACE_GROUND_TEXTURE.get_height()
	draw_texture_rect(_SURFACE_GROUND_TEXTURE, Rect2(world_left, 0, world_width, ground_height), true)

	# Surface row only.
	for pos in _cells.keys():
		if pos.y != 0:
			continue
		var cell: Cell = _cells[pos]
		var rect: Rect2 = Rect2(pos.x * CELL_SIZE, pos.y * CELL_SIZE, CELL_SIZE, CELL_SIZE)
		if cell.type == CellType.SURFACE_GROUND:
			draw_rect(rect, GameManager.COLOR_ICE, true)
			draw_rect(rect, GameManager.COLOR_STEEL, false, 1.0)


func _draw_underground() -> void:
	var world_left: float = (X_MIN - 1) * CELL_SIZE
	var world_right: float = (X_MAX + 2) * CELL_SIZE
	var world_width: float = world_right - world_left

	# Surface ceiling.
	var ground_height: float = _SURFACE_GROUND_TEXTURE.get_height()
	draw_texture_rect(_SURFACE_GROUND_TEXTURE, Rect2(world_left, 0, world_width, ground_height), true)

	# Underground background.
	var underground_y: float = CELL_SIZE
	var underground_height: float = Y_MAX * CELL_SIZE
	draw_texture_rect(_UNDERGROUND_TEXTURE, Rect2(world_left, underground_y, world_width, underground_height), true)

	for pos in _cells.keys():
		if pos.y < 1:
			continue
		var cell: Cell = _cells[pos]
		var rect: Rect2 = Rect2(pos.x * CELL_SIZE, pos.y * CELL_SIZE, CELL_SIZE, CELL_SIZE)
		match cell.type:
			CellType.SURFACE_GROUND:
				draw_rect(rect, GameManager.COLOR_ICE, true)
				draw_rect(rect, GameManager.COLOR_STEEL, false, 1.0)
			CellType.DIRT:
				var dirt_texture: Texture2D = _layer_tile(cell.layer)
				if dirt_texture != null:
					draw_texture_rect(dirt_texture, rect, false)
				else:
					draw_rect(rect, _dirt_color(cell.layer), true)
			CellType.ORE:
				var ore_texture: Texture2D = _layer_tile(cell.layer)
				if ore_texture != null:
					draw_texture_rect(ore_texture, rect, false)
				else:
					draw_rect(rect, _dirt_color(cell.layer), true)
				# Ore nugget.
				var inner: Rect2 = rect.grow(-8)
				draw_rect(inner, GameManager.COLOR_RUST, true)
			CellType.WALL:
				draw_texture_rect(_WALL_TEXTURE, rect, true)
				draw_rect(rect, GameManager.COLOR_SHADOW, false, 2.0)

		# Mining feedback: flash, dust puffs, and a small HP bar for partially
		# damaged cells so active mining is readable at a glance.
		if pos in _cell_flash:
			var flash_alpha: float = clampf(_cell_flash[pos] / 0.2, 0.0, 1.0)
			draw_rect(rect, Color(1.0, 1.0, 1.0, flash_alpha * 0.35), true)
			_draw_dust_puffs(rect, flash_alpha)
		if cell.hp > 0 and cell.hp < cell.max_hp:
			_draw_cell_hp_bar(rect, float(cell.hp) / float(cell.max_hp))

	# Dust burst for cells destroyed since the last redraw (already erased
	# from _cells, so the main loop above skips them).
	for pos in _cell_flash.keys():
		if pos.y < 1 or _cells.has(pos):
			continue
		var burst_rect: Rect2 = Rect2(pos.x * CELL_SIZE, pos.y * CELL_SIZE, CELL_SIZE, CELL_SIZE)
		var burst_alpha: float = clampf(_cell_flash[pos] / 0.2, 0.0, 1.0)
		_draw_dust_puffs(burst_rect, burst_alpha)

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


func _draw_dust_puffs(rect: Rect2, alpha: float) -> void:
	var center: Vector2 = rect.get_center()
	var dust_color: Color = Color(0.75, 0.7, 0.6, alpha * 0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(center)
	for i in range(5):
		var angle: float = rng.randf() * TAU
		var dist: float = 4.0 + rng.randf() * 8.0
		var radius: float = 2.0 + rng.randf() * 3.0
		draw_circle(center + Vector2(cos(angle), sin(angle)) * dist, radius, dust_color)


func _draw_cell_hp_bar(rect: Rect2, ratio: float) -> void:
	var bar_w: float = rect.size.x - 6
	var bar_h: float = 4
	var bar_pos: Vector2 = Vector2(rect.position.x + 3, rect.position.y + 3)
	draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0, 0, 0, 0.7), true)
	if ratio > 0:
		var fill_color: Color = Color.GREEN if ratio >= 0.5 else Color.ORANGE
		draw_rect(Rect2(bar_pos, Vector2(bar_w * ratio, bar_h)), fill_color, true)


func _dirt_color(layer: int) -> Color:
	if layer <= 2:
		return GameManager.COLOR_DIRT_1
	if layer <= 4:
		return GameManager.COLOR_DIRT_2
	return GameManager.COLOR_DIRT_3


func _layer_tile(layer: int) -> Texture2D:
	var idx: int = clampi(layer - 1, 0, _LAYER_TILES.size() - 1)
	return _LAYER_TILES[idx]
