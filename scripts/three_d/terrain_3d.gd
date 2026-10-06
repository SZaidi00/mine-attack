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
## by its shared HP pool, lava/magma/fresh-ore), plus the Phase 2 art pass
## (§2.3/§2.7): surface cells are sculpted with deterministic per-cell
## heights from ArtStyle3D.cell_hash, snow cover lerps the surface toward
## the snow palette as storms accumulate and melts after, and visible lava
## (plus magma rock touching it) renders as a second emissive "glow" mesh
## per chunk whose shared material pulses. Player fog of war tints every
## quad via fog_state_at() (fog / remembered / visible), same scheme as the
## 2D overlay; per-chunk decorations (ore crystals, snow drifts, embers)
## live in the TerrainDetail3D child.
extends Node3D

const WORLD_SCALE: float = 0.01
const REBUILD_INTERVAL: float = 0.15
const FOG_REFRESH_INTERVAL: float = 0.5
const CHUNK_COLS: int = 21
const CHUNK_ROWS: int = 8
const SNOW_RATE: float = 0.1  # snow cover accumulation/melt per second
const GLOW_LIFT: float = 0.004  # glow quads hover above the albedo pass

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
var _glow_mat: StandardMaterial3D
var _chunks: Dictionary = {}  # Vector2i chunk coord -> MeshInstance3D
var _glow_chunks: Dictionary = {}  # Vector2i chunk coord -> MeshInstance3D (lava emissive pass)
var _chunk_x_starts: Array[int] = []
var _chunk_y_starts: Array[int] = []
var _dirty: Dictionary = {}  # Vector2i chunk coord -> true
var _dirty_all := false
var _underground_view := false
var _accum := 0.0
var _fog_accum := 0.0
var _snow_level := 0.0  # 0..1 surface snow accumulation (presentation only)
var _snow_target := 0.0
var _pulse_time := 0.0

## Per-chunk decorative geometry (ore crystals, snow drifts, ember spikes).
var detail: TerrainDetail3D


func setup(grid: GridWorld) -> void:
	_grid = grid
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.roughness = 1.0
	# One shared emissive material for every glow chunk; _process pulses its
	# emission_energy_multiplier (ArtStyle3D's cache makes it shared state).
	_glow_mat = ArtStyle3D.get_material(ArtStyle3D.PALETTE.lava, ArtStyle3D.PALETTE.lava, 1.0)
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
			var glow := MeshInstance3D.new()
			glow.set_material_override(_glow_mat)
			add_child(glow)
			_glow_chunks[Vector2i(ix, iy)] = glow
	detail = TerrainDetail3D.new()
	detail.name = "TerrainDetail"
	add_child(detail)
	detail.setup(grid)
	# Snow cover follows the storm state: init from the live flag (a storm
	# may already be raging when the shell sets up) and track the signals.
	if is_instance_valid(WeatherManager):
		_snow_target = 1.0 if WeatherManager.is_snowstorm_active() else 0.0
		_snow_level = _snow_target
		WeatherManager.snowstorm_started.connect(_on_snowstorm_started)
		WeatherManager.snowstorm_ended.connect(_on_snowstorm_ended)
	_grid.cell_destroyed.connect(_on_cell_destroyed)
	_grid.cells_revealed.connect(_on_cells_revealed)
	_grid.wall_hp_changed.connect(_on_wall_hp_changed)
	_grid.lava_risen.connect(_on_world_changed)
	_grid.lava_receded.connect(_on_world_changed)
	_grid.cave_in_occurred.connect(_on_cave_in)
	_mark_all_dirty()


func get_snow_level() -> float:
	return _snow_level


func _on_snowstorm_started() -> void:
	_snow_target = 1.0


func _on_snowstorm_ended() -> void:
	_snow_target = 0.0


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
	# Snow cover tweens toward the storm target even when no chunk is dirty;
	# while the cover is visibly changing, every rebuild pass re-lerps the
	# surface palette (the chunk throttle below absorbs the churn).
	if _snow_level != _snow_target:
		_snow_level = move_toward(_snow_level, _snow_target, SNOW_RATE * delta)
		if absf(_snow_level - _snow_target) > 0.01:
			_mark_all_dirty()
	# Slow emissive heartbeat on the shared lava material (~0.6s period).
	_pulse_time += delta
	_glow_mat.emission_energy_multiplier = lerpf(0.7, 1.6, 0.5 + 0.5 * sin(_pulse_time * TAU / 0.6))
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
	var glow_chunk: MeshInstance3D = _glow_chunks[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow_used := false
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
			var center: Vector2 = _grid.grid_to_world(pos, true)
			var cx := center.x * WORLD_SCALE
			var cz := center.y * WORLD_SCALE
			var heights := _corner_heights(pos, cell)
			var fog := _grid.fog_state_at(GameManager.Team.PLAYER, pos)
			# Visible lava (and magma rock touching it) renders in the
			# emissive glow pass instead of the albedo pass; hidden lava
			# keeps the flat fog-tinted quad so the terrain stays covered.
			if fog == 2 and (cell.type == GridWorld.CellType.LAVA
					or (cell.type == GridWorld.CellType.MAGMA_ROCK and _has_lava_neighbor(pos))):
				_add_flat_quad(gst, cx, cz, (heights[0] + heights[1] + heights[2] + heights[3]) * 0.25 + GLOW_LIFT)
				glow_used = true
				continue
			var color := _cell_color(cell, pos, max_ore)
			match fog:
				0:
					color = Constants.FOG_COLOR
				1:
					color = color.lerp(Constants.FOG_COLOR, Constants.FOG_MEMORY_ALPHA)
			_add_quad(st, cx, cz, color, heights[0], heights[1], heights[2], heights[3])
	chunk.mesh = st.commit()
	if chunk.mesh != null:
		chunk.set_material_override(_mat)
	# Null (not an empty mesh) keeps invisible glow chunks cost-free.
	glow_chunk.mesh = gst.commit() if glow_used else null
	detail.rebuild_chunk(key, x_start, y_start, _underground_view, _snow_level)


## Deterministic sculpted Y per surface quad corner (§2.3): open ground
## undulates within ~+-0.03, wall cells rise as a ridge. Underground quads
## stay flat. Corner order matches _add_quad: (x0,z0), (x1,z0), (x1,z1), (x0,z1).
func _corner_heights(pos: Vector2i, cell: GridWorld.Cell) -> Array[float]:
	if _underground_view:
		return [0.0, 0.0, 0.0, 0.0]
	var base: float
	if cell.type == GridWorld.CellType.WALL:
		base = lerpf(0.12, 0.2, ArtStyle3D.cell_hash(pos, 2))
	else:
		base = lerpf(-0.03, 0.03, ArtStyle3D.cell_hash(pos, 1))
	return [
		base + (ArtStyle3D.cell_hash(pos, 11) - 0.5) * 0.02,
		base + (ArtStyle3D.cell_hash(pos, 12) - 0.5) * 0.02,
		base + (ArtStyle3D.cell_hash(pos, 13) - 0.5) * 0.02,
		base + (ArtStyle3D.cell_hash(pos, 14) - 0.5) * 0.02,
	]


func _has_lava_neighbor(pos: Vector2i) -> bool:
	for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var n: GridWorld.Cell = _grid.get_cell(pos + dir)
		if n != null and n.type == GridWorld.CellType.LAVA:
			return true
	return false


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


func _add_quad(st: SurfaceTool, cx: float, cz: float, color: Color, y00 := 0.0, y10 := 0.0, y11 := 0.0, y01 := 0.0) -> void:
	var half: float = GridWorld.CELL_SIZE * 0.5 * WORLD_SCALE
	var x0 := cx - half
	var x1 := cx + half
	var z0 := cz - half
	var z1 := cz + half
	st.set_color(color)
	st.add_vertex(Vector3(x0, y00, z0))
	st.set_color(color)
	st.add_vertex(Vector3(x1, y10, z0))
	st.set_color(color)
	st.add_vertex(Vector3(x1, y11, z1))
	st.set_color(color)
	st.add_vertex(Vector3(x0, y00, z0))
	st.set_color(color)
	st.add_vertex(Vector3(x1, y11, z1))
	st.set_color(color)
	st.add_vertex(Vector3(x0, y01, z1))


## Glow-pass quad: no vertex colors at all — the chunk's shared emissive
## material supplies the flat lava albedo.
func _add_flat_quad(st: SurfaceTool, cx: float, cz: float, y: float) -> void:
	var half: float = GridWorld.CELL_SIZE * 0.5 * WORLD_SCALE
	var x0 := cx - half
	var x1 := cx + half
	var z0 := cz - half
	var z1 := cz + half
	st.add_vertex(Vector3(x0, y, z0))
	st.add_vertex(Vector3(x1, y, z0))
	st.add_vertex(Vector3(x1, y, z1))
	st.add_vertex(Vector3(x0, y, z0))
	st.add_vertex(Vector3(x1, y, z1))
	st.add_vertex(Vector3(x0, y, z1))


func _cell_color(cell: GridWorld.Cell, pos: Vector2i, max_ore: int) -> Color:
	match cell.type:
		GridWorld.CellType.SURFACE_GROUND:
			# Snow cover (§2.3): storms lerp the ice toward the snow palette,
			# melting restores it.
			return GameManager.COLOR_ICE.lerp(ArtStyle3D.PALETTE.snow, _snow_level * 0.85)
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
