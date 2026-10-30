## Chunked sim-to-render terrain projection. Surface and underground rows
## rebuild independently on Tab, with deterministic corner heights, lit vertex
## colors, weather snow cover, fog dimming, and a separate pulsing lava pass.
## R2 replaces the inherited 2D browns/ice with the revamp's shadow-snow,
## indigo rock, cooled dirt, tiered ore, and warm lava tokens. R3 (visual
## revamp) displaces the surface quads onto the HeightField3D dune field —
## same chunk path and vertex count, corners sampled from the shared field so
## seams stay watertight and proxies/camera ground-snap read the same ground.
## The grid is only read, never written.
extends Node3D

const WORLD_SCALE: float = 0.01
const LIT_TERRAIN: bool = true
const REBUILD_INTERVAL: float = 0.15
## Player-fog poll cadence: the tick only dirties chunks when the sim's fog
## diff actually bumped player_fog_revision (was: unconditional full rebuild).
const FOG_REFRESH_INTERVAL: float = 0.5
## Slow full-sweep backstop for the signal-less cell mutations (cave-in
## restore, ore respawn, depletion tint) the fog diff can't see.
const BACKSTOP_INTERVAL: float = 5.0
const CHUNK_COLS: int = 21
const CHUNK_ROWS: int = 8
const SNOW_RATE: float = 0.1
## Snow-dirty quantization: the cover tween marks chunks dirty only when the
## level crosses a 1/N step, so a storm ramp rebuilds ~N times total instead
## of every frame for its whole duration.
const SNOW_DIRTY_STEPS: int = 32
const GLOW_LIFT: float = 0.004

const LAVA_COLOR := ArtStyle3D.PALETTE.lava
const MAGMA_ROCK_COLOR := ArtStyle3D.PALETTE.magma
const FRESH_ORE_COLOR := ArtStyle3D.PALETTE.rust
const SOLID_ROCK_COLOR := ArtStyle3D.PALETTE.rock_dark
const DEPLETED_ORE_COLOR := ArtStyle3D.PALETTE.wood_dark
const WALL_DAMAGED_COLOR := Color("#8E3228")
const BORDER_WALL_COLOR := ArtStyle3D.PALETTE.night
const ORE_TIER_BRIGHT := ArtStyle3D.PALETTE.ore_bright
const DIRT_SHALLOW_COLOR := Color("#4A4850")
const DIRT_MID_COLOR := ArtStyle3D.PALETTE.rock
const DIRT_DEEP_COLOR := ArtStyle3D.PALETTE.rock_dark
const FOG_VOID_TINT := ArtStyle3D.PALETTE.fog_void
const FOG_SHADOW_TINT := ArtStyle3D.PALETTE.rock_dark

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
var _backstop_accum := 0.0
var _seen_fog_revision := -1
var _last_snow_step := -1
## Structure-clearance re-stamp is gated on the entity proxies actually
## spawning/culling a structure proxy (signal from main_3d); true at setup so
## the first rebuild batch stamps the initial board.
var _clearances_dirty := true
var _snow_level := 0.0  # 0..1 surface snow accumulation (presentation only)
var _snow_target := 0.0
var _pulse_time := 0.0

## Per-chunk decorative geometry (ore crystals, snow drifts, ember spikes).
var detail: TerrainDetail3D

## R3 dune field: the surface quads displace onto it, world_height_at()
## answers from it, and proxies ground-snap against the same function.
var height_field: HeightField3D


func setup(grid: GridWorld) -> void:
	_grid = grid
	height_field = HeightField3D.new()
	height_field.setup(grid)
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = ArtStyle3D.MATERIAL_ROUGHNESS
	if not LIT_TERRAIN:
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# One shared emissive material for every glow chunk; _process pulses its
	# emission_energy_multiplier (ArtStyle3D's cache makes it shared state).
	_glow_mat = ArtStyle3D.get_material(ArtStyle3D.PALETTE.lava, ArtStyle3D.PALETTE.lava, 1.0)
	# Chunk starts cover the full cell range (incl. border walls at x=+-41,
	# the surface band above row 0, and the y=22 floor row); posmod keeps them
	# aligned to CHUNK_* sizes.
	var x0: int = GridWorld.X_MIN - 1 - int(posmod(GridWorld.X_MIN - 1, CHUNK_COLS))
	while x0 <= GridWorld.X_MAX + 1:
		_chunk_x_starts.append(x0)
		x0 += CHUNK_COLS
	var y0: int = GridWorld.SURFACE_TOP - int(posmod(GridWorld.SURFACE_TOP, CHUNK_ROWS))
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
	_seen_fog_revision = _grid.player_fog_revision


func get_snow_level() -> float:
	return _snow_level


## 3D rework phase 3: true when the albedo pass is a lit material (receives
## mood light, sun shadows, and fog) instead of the old unshaded matte.
func uses_lit_terrain() -> bool:
	return _mat != null and _mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED


## Read-only ground height in world units at a world XZ position — the same
## deterministic height field the render pass samples, so a query lands on
## the visible ground (the underground layer is flat 0). The camera rig's
## zoom-to-cursor ray marches against this.
func world_height_at(world_x: float, world_z: float) -> float:
	if height_field == null:
		return 0.0
	return height_field.height_at(world_x, world_z)


## Changes whenever the field's output changes (storm flattening, structure
## clearances) without the query position moving — ground-snapped proxies
## watch this to re-sample standing poses.
func ground_height_revision() -> int:
	return height_field.revision if height_field != null else 0


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
## EntityProxies3D emits structure_set_changed when a reconcile spawns or
## culls a structure proxy; the height field's clearance stamps only need a
## re-run at those moments (plus the first rebuild batch after setup).
## The re-stamp runs inside a rebuild batch, so a structure change must also
## dirty the chunks — otherwise the dune re-flattening and the plan-07 prop
## scatter re-filter would wait for the 5s backstop instead of landing with
## the next batch.
func notify_structures_changed() -> void:
	_clearances_dirty = true
	_mark_all_dirty()


## Public alias for the full-dirty mark (live quality switches, external
## callers); keeps the _dirty mechanics internal.
func force_full_rebuild() -> void:
	_mark_all_dirty()


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
	# the level only marks chunks dirty when it crosses a 1/SNOW_DIRTY_STEPS
	# step (the chunk throttle below absorbs the ramp). The same tween
	# flattens the dune field (§2.4: storms fill the relief) — the height
	# field applies it on its next sample and bumps its revision.
	if _snow_level != _snow_target:
		_snow_level = move_toward(_snow_level, _snow_target, SNOW_RATE * delta)
		var snow_step := int(_snow_level * SNOW_DIRTY_STEPS + 0.5)
		if snow_step != _last_snow_step:
			_last_snow_step = snow_step
			_mark_all_dirty()
	if height_field != null:
		height_field.set_storm_level(_snow_level)
	# Slow emissive heartbeat on the shared lava material (~0.6s period).
	_pulse_time += delta
	_glow_mat.emission_energy_multiplier = lerpf(0.7, 1.6, 0.5 + 0.5 * sin(_pulse_time * TAU / 0.6))
	# Fog moves with vision every frame; GridFogOfWar diffs the player's fog
	# state each frame and bumps player_fog_revision on real changes, so this
	# tick only dirties the chunks those changed cells fall in (the old
	# unconditional full sweep rebuilt all 16 chunks every 0.5s for the whole
	# match). A slow full backstop covers the signal-less mutations.
	_fog_accum += delta
	if _fog_accum >= FOG_REFRESH_INTERVAL:
		_fog_accum = 0.0
		if _grid != null and _grid.player_fog_revision != _seen_fog_revision:
			_seen_fog_revision = _grid.player_fog_revision
			for cell in _grid.consume_player_fog_changes():
				_dirty[_chunk_key_for(cell)] = true
	_backstop_accum += delta
	if _backstop_accum >= BACKSTOP_INTERVAL:
		_backstop_accum = 0.0
		_mark_all_dirty()
	if _dirty.is_empty() and not _dirty_all:
		return
	_accum += delta
	if _accum < REBUILD_INTERVAL:
		return
	_accum = 0.0
	# Structure placements mid-match re-stamp their clearances before the
	# batch samples heights — gated on the entity proxies actually
	# spawning/culling a structure proxy (main_3d wires the signal).
	if _clearances_dirty and height_field != null:
		_clearances_dirty = false
		height_field.refresh_clearances()
	var probe_start := Time.get_ticks_usec() if Probe3D.enabled else 0
	if _dirty_all:
		_dirty_all = false
		_dirty.clear()
		for key in _chunks:
			_rebuild_chunk(key)
	else:
		for key in _dirty:
			_rebuild_chunk(key)
		_dirty.clear()
	if Probe3D.enabled:
		Probe3D.add("terrain_rebuild", (Time.get_ticks_usec() - probe_start) / 1000.0)


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
			if pos.y < GridWorld.SURFACE_TOP or pos.y > GridWorld.Y_MAX + 1:
				continue
			if not _grid.has_cell(pos):
				continue
			if _underground_view and _grid.is_surface_row(pos.y):
				continue
			if not _underground_view and not _grid.is_surface_row(pos.y):
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
					color = FOG_VOID_TINT
				1:
					color = color.lerp(FOG_SHADOW_TINT, 0.8)
			_add_quad(st, cx, cz, color, heights[0], heights[1], heights[2], heights[3])
	if LIT_TERRAIN:
		# Flat per-face normals off the sculpted corner heights; the glow
		# pass is unshaded/emissive and needs none.
		st.generate_normals()
	chunk.mesh = st.commit()
	if chunk.mesh != null:
		chunk.set_material_override(_mat)
	# Null (not an empty mesh) keeps invisible glow chunks cost-free.
	glow_chunk.mesh = gst.commit() if glow_used else null
	detail.rebuild_chunk(key, x_start, y_start, _underground_view, _snow_level, height_field)


## R3: the four quad corners sample the shared dune field at their cell-space
## positions (corner order matches _add_quad: (x0,z0), (x1,z0), (x1,z1),
## (x0,z1)) — adjacent chunks sample the same continuous function, so seams
## stay watertight. Underground quads stay flat. Wall cells keep their ridge
## and open ground rolls in dunes, both inside the field.
func _corner_heights(pos: Vector2i, _cell: GridWorld.Cell) -> Array[float]:
	if _underground_view:
		return [0.0, 0.0, 0.0, 0.0]
	return [
		height_field.height_at_cell(pos.x, pos.y),
		height_field.height_at_cell(pos.x + 1, pos.y),
		height_field.height_at_cell(pos.x + 1, pos.y + 1),
		height_field.height_at_cell(pos.x, pos.y + 1),
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
			var snow_mix := lerpf(0.45, 1.0, _snow_level)
			return ArtStyle3D.PALETTE.snow_shadow.lerp(ArtStyle3D.PALETTE.snow, snow_mix)
		GridWorld.CellType.DIRT:
			return _dirt_color(cell.layer)
		GridWorld.CellType.ORE:
			var tier := ArtStyle3D.PALETTE.rust
			if max_ore > 0:
				tier = tier.lerp(ORE_TIER_BRIGHT, clampf(float(cell.coin_value) / float(max_ore), 0.0, 1.0) * 0.7)
			if cell.coin_value > 0:
				var frac := clampf(1.0 - float(cell.coin_remaining) / float(cell.coin_value), 0.0, 1.0)
				return tier.lerp(DEPLETED_ORE_COLOR, frac)
			return tier
		GridWorld.CellType.WALL:
			if _grid.is_central_wall(pos):
				return ArtStyle3D.PALETTE.steel.lerp(WALL_DAMAGED_COLOR, 1.0 - _grid.get_wall_hp_ratio())
			return BORDER_WALL_COLOR
		GridWorld.CellType.LAVA:
			return LAVA_COLOR
		GridWorld.CellType.MAGMA_ROCK:
			return MAGMA_ROCK_COLOR
		GridWorld.CellType.FRESH_ORE:
			return FRESH_ORE_COLOR
		GridWorld.CellType.SOLID_ROCK:
			return SOLID_ROCK_COLOR
	return ArtStyle3D.PALETTE.night


func _dirt_color(layer: int) -> Color:
	if layer <= 2:
		return DIRT_SHALLOW_COLOR
	if layer <= 4:
		return DIRT_MID_COLOR
	return DIRT_DEEP_COLOR
