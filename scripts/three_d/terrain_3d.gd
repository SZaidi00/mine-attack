## Phase 1 terrain (roadmap/3d-conversion/phase-1-25d-port.md §1.2).
##
## The 2D world projected as flat colored quads: chunk MeshInstances (one
## ArrayMesh each) rebuilt from GridWorld's cells — a pure sim -> render
## projection (the grid is read, never written). Exactly like the 2D view,
## only the layer matching the current Tab view renders: the surface row
## (y=0) in surface view, rows y>=1 underground in underground view; layer
## switching marks every chunk dirty and the throttled pass rebuilds them.
##
## Colors mirror grid_drawing.gd's flat palette (ice surface, per-layer
## dirt, ore tinted by richness tier and depletion, the central wall tinted
## by its shared HP pool, lava/magma/fresh-ore). Player fog of war tints
## every quad via fog_state_at() (fog / remembered / visible), same scheme
## as the 2D overlay. Lava emissive pulsing is an effects-pass (§1.6) task.
extends Node3D

const WORLD_SCALE: float = 0.01
const REBUILD_INTERVAL: float = 0.15
const FOG_REFRESH_INTERVAL: float = 0.5
const CHUNK_COLS: int = 21
const CHUNK_ROWS: int = 8

const LAVA_COLOR := Color(0.7, 0.14, 0.02)
const MAGMA_ROCK_COLOR := Color(0.16, 0.12, 0.11)
const FRESH_ORE_COLOR := Color(0.85, 0.42, 0.18)
const SOLID_ROCK_COLOR := Color(0.22, 0.21, 0.24)
const DEPLETED_ORE_COLOR := Color(0.45, 0.38, 0.3)
const WALL_DAMAGED_COLOR := Color(0.6, 0.15, 0.1)
const BORDER_WALL_COLOR := Color(0.18, 0.2, 0.23)
const ORE_TIER_BRIGHT := Color(0.95, 0.7, 0.2)

var _grid: GridWorld
var _mat: StandardMaterial3D
var _chunks: Dictionary = {}  # Vector2i chunk coord -> MeshInstance3D
var _chunk_x_starts: Array[int] = []
var _chunk_y_starts: Array[int] = []
var _dirty: Dictionary = {}  # Vector2i chunk coord -> true
var _dirty_all := false
var _underground_view := false
var _accum := 0.0
var _fog_accum := 0.0


func setup(grid: GridWorld) -> void:
	_grid = grid
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.roughness = 1.0
	# Chunk starts cover the full cell range (incl. border walls at x=+-41
	# and the y=22 floor row); posmod keeps them aligned to CHUNK_* sizes.
	var x0: int = GridWorld.X_MIN - 1 - int(posmod(GridWorld.X_MIN - 1, CHUNK_COLS))
	while x0 <= GridWorld.X_MAX + 1:
		_chunk_x_starts.append(x0)
		x0 += CHUNK_COLS
	var y0: int = GridWorld.Y_MIN
	while y0 <= GridWorld.Y_MAX + 1:
		_chunk_y_starts.append(y0)
		y0 += CHUNK_ROWS
	for ix in range(_chunk_x_starts.size()):
		for iy in range(_chunk_y_starts.size()):
			var chunk := MeshInstance3D.new()
			add_child(chunk)
			_chunks[Vector2i(ix, iy)] = chunk
	_grid.cell_destroyed.connect(_on_cell_destroyed)
	_grid.cells_revealed.connect(_on_cells_revealed)
	_grid.wall_hp_changed.connect(_on_wall_hp_changed)
	_grid.lava_risen.connect(_on_world_changed)
	_grid.lava_receded.connect(_on_world_changed)
	_grid.cave_in_occurred.connect(_on_cave_in)
	_mark_all_dirty()


func _chunk_key_for(pos: Vector2i) -> Vector2i:
	var ix := 0
	while ix < _chunk_x_starts.size() - 1 and pos.x >= _chunk_x_starts[ix] + CHUNK_COLS:
		ix += 1
	var iy := 0
	while iy < _chunk_y_starts.size() - 1 and pos.y >= _chunk_y_starts[iy] + CHUNK_ROWS:
		iy += 1
	return Vector2i(ix, iy)


## Layer switching rebuilds the visible world, exactly like the 2D camera
## bookmark jump.
func set_underground_view(underground: bool) -> void:
	if _underground_view == underground:
		return
	_underground_view = underground
	_mark_all_dirty()


func _on_cell_destroyed(grid_pos: Vector2i) -> void:
	_dirty[_chunk_key_for(grid_pos)] = true


func _on_cells_revealed(cells: Array) -> void:
	for pos in cells:
		_dirty[_chunk_key_for(pos)] = true


func _on_cave_in(center: Vector2i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			_dirty[_chunk_key_for(center + Vector2i(dx, dy))] = true


func _on_world_changed(_arg1: Variant = null, _arg2: Variant = null) -> void:
	_mark_all_dirty()


func _on_wall_hp_changed(_current: int, _maximum: int) -> void:
	# Wall tint spans every underground chunk; full sweep is cheap.
	_mark_all_dirty()


func _mark_all_dirty() -> void:
	_dirty_all = true


func _process(delta: float) -> void:
	# Fog moves with vision every frame but emits no signals, and a few cell
	# mutations (cave-in restore, ore respawn, depletion tint) are signal-less
	# too — a slow full sweep keeps the projection convergent.
	_fog_accum += delta
	if _fog_accum >= FOG_REFRESH_INTERVAL:
		_fog_accum = 0.0
		_mark_all_dirty()
	if _dirty.is_empty() and not _dirty_all:
		return
	_accum += delta
	if _accum < REBUILD_INTERVAL:
		return
	_accum = 0.0
	if _dirty_all:
		_dirty_all = false
		_dirty.clear()
		for key in _chunks:
			_rebuild_chunk(key)
	else:
		for key in _dirty:
			_rebuild_chunk(key)
		_dirty.clear()


func _rebuild_chunk(key: Vector2i) -> void:
	var chunk: MeshInstance3D = _chunks[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x_start: int = _chunk_x_starts[key.x]
	var y_start: int = _chunk_y_starts[key.y]
	var max_ore := 0
	if _underground_view:
		max_ore = _max_ore_value(x_start, y_start)
	for dy in range(CHUNK_ROWS):
		for dx in range(CHUNK_COLS):
			var pos := Vector2i(x_start + dx, y_start + dy)
			if pos.y < GridWorld.Y_MIN or pos.y > GridWorld.Y_MAX + 1:
				continue
			if not _grid.has_cell(pos):
				continue
			if _underground_view and pos.y == 0:
				continue
			if not _underground_view and pos.y != 0:
				continue
			var cell: GridWorld.Cell = _grid.get_cell(pos)
			if cell.type == GridWorld.CellType.EMPTY:
				continue
			var color := _cell_color(cell, pos, max_ore)
			match _grid.fog_state_at(GameManager.Team.PLAYER, pos):
				0:
					color = Constants.FOG_COLOR
				1:
					color = color.lerp(Constants.FOG_COLOR, Constants.FOG_MEMORY_ALPHA)
			var center: Vector2 = _grid.grid_to_world(pos, true)
			_add_quad(st, center.x * WORLD_SCALE, center.y * WORLD_SCALE, color)
	chunk.mesh = st.commit()
	if chunk.mesh != null:
		chunk.set_material_override(_mat)


## Richest ore cell in this chunk normalizes the tier tint.
func _max_ore_value(x_start: int, y_start: int) -> int:
	var best := 0
	for dy in range(CHUNK_ROWS):
		for dx in range(CHUNK_COLS):
			var pos := Vector2i(x_start + dx, y_start + dy)
			if not _grid.has_cell(pos):
				continue
			var cell: GridWorld.Cell = _grid.get_cell(pos)
			if cell.type == GridWorld.CellType.ORE and cell.coin_value > best:
				best = cell.coin_value
	return best


func _add_quad(st: SurfaceTool, cx: float, cz: float, color: Color) -> void:
	var half: float = GridWorld.CELL_SIZE * 0.5 * WORLD_SCALE
	var x0 := cx - half
	var x1 := cx + half
	var z0 := cz - half
	var z1 := cz + half
	st.set_color(color)
	st.add_vertex(Vector3(x0, 0.0, z0))
	st.set_color(color)
	st.add_vertex(Vector3(x1, 0.0, z0))
	st.set_color(color)
	st.add_vertex(Vector3(x1, 0.0, z1))
	st.set_color(color)
	st.add_vertex(Vector3(x0, 0.0, z0))
	st.set_color(color)
	st.add_vertex(Vector3(x1, 0.0, z1))
	st.set_color(color)
	st.add_vertex(Vector3(x0, 0.0, z1))


func _cell_color(cell: GridWorld.Cell, pos: Vector2i, max_ore: int) -> Color:
	match cell.type:
		GridWorld.CellType.SURFACE_GROUND:
			return GameManager.COLOR_ICE
		GridWorld.CellType.DIRT:
			return _dirt_color(cell.layer)
		GridWorld.CellType.ORE:
			var tier := GameManager.COLOR_RUST
			if max_ore > 0:
				tier = tier.lerp(ORE_TIER_BRIGHT, clampf(float(cell.coin_value) / float(max_ore), 0.0, 1.0) * 0.7)
			if cell.coin_value > 0:
				var frac := clampf(1.0 - float(cell.coin_remaining) / float(cell.coin_value), 0.0, 1.0)
				return tier.lerp(DEPLETED_ORE_COLOR, frac)
			return tier
		GridWorld.CellType.WALL:
			if _grid.is_central_wall(pos):
				return GameManager.COLOR_STEEL.lerp(WALL_DAMAGED_COLOR, 1.0 - _grid.get_wall_hp_ratio())
			return BORDER_WALL_COLOR
		GridWorld.CellType.LAVA:
			return LAVA_COLOR
		GridWorld.CellType.MAGMA_ROCK:
			return MAGMA_ROCK_COLOR
		GridWorld.CellType.FRESH_ORE:
			return FRESH_ORE_COLOR
		GridWorld.CellType.SOLID_ROCK:
			return SOLID_ROCK_COLOR
	return GameManager.COLOR_SHADOW


func _dirt_color(layer: int) -> Color:
	if layer <= 2:
		return GameManager.COLOR_DIRT_1
	if layer <= 4:
		return GameManager.COLOR_DIRT_2
	return GameManager.COLOR_DIRT_3
