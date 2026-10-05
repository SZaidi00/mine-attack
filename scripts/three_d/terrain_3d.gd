## Spike-only terrain (see roadmap/3d-conversion/phase-0-spike.md).
##
## One unshaded vertex-colored quad mesh rebuilt from GridWorld's cells: a
## pure sim -> render projection (the grid is read, never written). Cell
## colors mirror grid_drawing.gd's flat palette; the player's fog of war
## tints every quad the same way the 2D overlay does (fog / remembered /
## visible). Rebuilds are signal-driven with a short throttle since bursts
## like cells_revealed can touch hundreds of cells at once.
extends MeshInstance3D

const WORLD_SCALE: float = 0.01
const REBUILD_INTERVAL: float = 0.2

const LAVA_COLOR := Color(0.7, 0.14, 0.02)
const MAGMA_ROCK_COLOR := Color(0.16, 0.12, 0.11)
const FRESH_ORE_COLOR := Color(0.85, 0.42, 0.18)
const SOLID_ROCK_COLOR := Color(0.22, 0.21, 0.24)
const DEPLETED_ORE_COLOR := Color(0.45, 0.38, 0.3)
const WALL_DAMAGED_COLOR := Color(0.6, 0.15, 0.1)

var _grid: GridWorld
var _dirty := true
var _accum := 0.0


func setup(grid: GridWorld) -> void:
	_grid = grid
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.roughness = 1.0
	set_material_override(mat)
	_grid.cell_destroyed.connect(_on_world_changed)
	_grid.cells_revealed.connect(_on_world_changed)
	_grid.wall_hp_changed.connect(_on_world_changed)
	_grid.lava_risen.connect(_on_world_changed)
	_grid.lava_receded.connect(_on_world_changed)
	_grid.cave_in_occurred.connect(_on_world_changed)
	_rebuild()


func _on_world_changed(_arg1: Variant = null, _arg2: Variant = null) -> void:
	_dirty = true


func _process(delta: float) -> void:
	if not _dirty:
		return
	_accum += delta
	if _accum >= REBUILD_INTERVAL:
		_accum = 0.0
		_rebuild()


func _rebuild() -> void:
	_dirty = false
	if _grid == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = GridWorld.CELL_SIZE * 0.5 * WORLD_SCALE
	for y in range(GridWorld.Y_MIN, GridWorld.Y_MAX + 1):
		for x in range(GridWorld.X_MIN, GridWorld.X_MAX + 1):
			var pos := Vector2i(x, y)
			if not _grid.has_cell(pos):
				continue
			var cell: GridWorld.Cell = _grid.get_cell(pos)
			if cell.type == GridWorld.CellType.EMPTY:
				continue
			var color := _cell_color(cell)
			match _grid.fog_state_at(GameManager.Team.PLAYER, pos):
				0:
					color = Constants.FOG_COLOR
				1:
					color = color.lerp(Constants.FOG_COLOR, Constants.FOG_MEMORY_ALPHA)
			var center: Vector2 = _grid.grid_to_world(pos, true)
			_add_quad(st, center.x * WORLD_SCALE, center.y * WORLD_SCALE, half, color)
	mesh = st.commit()


func _add_quad(st: SurfaceTool, cx: float, cz: float, half: float, color: Color) -> void:
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


func _cell_color(cell: GridWorld.Cell) -> Color:
	match cell.type:
		GridWorld.CellType.SURFACE_GROUND:
			return GameManager.COLOR_ICE
		GridWorld.CellType.DIRT:
			return _dirt_color(cell.layer)
		GridWorld.CellType.ORE:
			if cell.coin_value > 0:
				var frac := clampf(1.0 - float(cell.coin_remaining) / float(cell.coin_value), 0.0, 1.0)
				return GameManager.COLOR_RUST.lerp(DEPLETED_ORE_COLOR, frac)
			return GameManager.COLOR_RUST
		GridWorld.CellType.WALL:
			return GameManager.COLOR_STEEL.lerp(WALL_DAMAGED_COLOR, 1.0 - _grid.get_wall_hp_ratio())
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
