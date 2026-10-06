## Phase 2 terrain detail (roadmap/3d-conversion/phase-2-art-pass.md §2.3/§2.7).
##
## Per-chunk decorative geometry projected from GridWorld cells, drawn as one
## MultiMeshInstance3D per decoration type per chunk: low-poly ore crystals
## underground (tinted by richness), ember spikes on visible lava, and
## snow-drift mounds on the surface while _snow_level accumulates. Pure
## sim -> render (the grid is read, never written); densities are
## quality-aware so Potato stays cheap.
##
## NOTE: extends MeshInstance3D (with mesh left null) rather than Node3D so a
## direct child of Terrain3D survives the Phase 1 port test's child loop,
## which casts every Terrain3D child to MeshInstance3D.
class_name TerrainDetail3D
extends MeshInstance3D

const WORLD_SCALE: float = 0.01
const CHUNK_COLS: int = 21
const CHUNK_ROWS: int = 8

var _grid: GridWorld
var _containers: Dictionary = {}  # Vector2i chunk key -> Node3D holder


func setup(grid: GridWorld) -> void:
	_grid = grid


## Rebuild the decorations for one terrain chunk right after the chunk's own
## mesh pass. Frees and replaces the chunk's previous decoration holder.
func rebuild_chunk(key: Vector2i, x_start: int, y_start: int, underground_view: bool, snow_level: float) -> void:
	if _containers.has(key):
		_containers[key].free()
		_containers.erase(key)
	var holder := Node3D.new()
	holder.name = "Detail_%d_%d" % [key.x, key.y]
	add_child(holder)
	_containers[key] = holder
	if not ArtStyle3D.detail_enabled():
		return
	var crystals_xf: Array[Transform3D] = []
	var crystals_col: Array[Color] = []
	var drifts_xf: Array[Transform3D] = []
	var drifts_col: Array[Color] = []
	var embers_xf: Array[Transform3D] = []
	var embers_col: Array[Color] = []
	for dy in range(CHUNK_ROWS):
		for dx in range(CHUNK_COLS):
			var pos := Vector2i(x_start + dx, y_start + dy)
			if pos.y < GridWorld.Y_MIN or pos.y > GridWorld.Y_MAX + 1:
				continue
			if not _grid.has_cell(pos):
				continue
			if underground_view and pos.y == 0:
				continue
			if not underground_view and pos.y != 0:
				continue
			var cell: GridWorld.Cell = _grid.get_cell(pos)
			if cell.type == GridWorld.CellType.EMPTY:
				continue
			# No decoration on fog-hidden cells; remembered intel is left
			# plain rather than half-decorated.
			if _grid.fog_state_at(GameManager.Team.PLAYER, pos) != 2:
				continue
			var center: Vector2 = _grid.grid_to_world(pos, true)
			var cx := center.x * WORLD_SCALE
			var cz := center.y * WORLD_SCALE
			if underground_view:
				match cell.type:
					GridWorld.CellType.ORE:
						_add_crystals(pos, cx, cz, cell, crystals_xf, crystals_col)
					GridWorld.CellType.LAVA:
						_add_embers(pos, cx, cz, embers_xf, embers_col)
			elif cell.type == GridWorld.CellType.SURFACE_GROUND:
				_add_drift(pos, cx, cz, snow_level, drifts_xf, drifts_col)
	if not crystals_xf.is_empty():
		holder.add_child(_make_multimesh(_cone(), crystals_xf, crystals_col, _crystal_material()))
	if not drifts_xf.is_empty():
		holder.add_child(_make_multimesh(_cone(), drifts_xf, drifts_col, _drift_material()))
	if not embers_xf.is_empty():
		holder.add_child(_make_multimesh(_cone(), embers_xf, embers_col, _ember_material()))


func _add_crystals(pos: Vector2i, cx: float, cz: float, cell: GridWorld.Cell, xforms: Array[Transform3D], colors: Array[Color]) -> void:
	var count := 1 + int(ArtStyle3D.cell_hash(pos, 3) * 2.999)
	count = maxi(1, int(round(count * ArtStyle3D.particle_mult())))
	var richness := clampf(float(cell.coin_value) / 40.0, 0.0, 1.0)
	for i in range(count):
		var h := lerpf(0.09, 0.2, ArtStyle3D.cell_hash(pos, 20 + i))
		var r := lerpf(0.035, 0.06, ArtStyle3D.cell_hash(pos, 30 + i))
		var ox := (ArtStyle3D.cell_hash(pos, 40 + i) - 0.5) * 0.2
		var oz := (ArtStyle3D.cell_hash(pos, 50 + i) - 0.5) * 0.2
		var xf := Transform3D(Basis.IDENTITY, Vector3(cx + ox, h * 0.35, cz + oz))
		xf.basis = Basis.from_euler(Vector3(0.0, ArtStyle3D.cell_hash(pos, 60 + i) * TAU, 0.0)).scaled(Vector3(r, h, r))
		xforms.append(xf)
		var tint := ArtStyle3D.PALETTE.rust.lerp(ArtStyle3D.PALETTE.ore_bright, richness)
		tint = tint.lerp(Color.WHITE, ArtStyle3D.cell_hash(pos, 70 + i) * 0.25)
		colors.append(tint)


func _add_drift(pos: Vector2i, cx: float, cz: float, snow_level: float, xforms: Array[Transform3D], colors: Array[Color]) -> void:
	if snow_level < 0.25:
		return
	# Density scales with accumulation: rare at first flurries, common in a
	# settled storm.
	if ArtStyle3D.cell_hash(pos, 7) >= 0.35 * snow_level:
		return
	var r := lerpf(0.07, 0.12, ArtStyle3D.cell_hash(pos, 80))
	var h := lerpf(0.025, 0.05, ArtStyle3D.cell_hash(pos, 81))
	var ox := (ArtStyle3D.cell_hash(pos, 82) - 0.5) * 0.16
	var oz := (ArtStyle3D.cell_hash(pos, 83) - 0.5) * 0.16
	var xf := Transform3D(Basis.IDENTITY, Vector3(cx + ox, h * 0.3, cz + oz))
	xf.basis = Basis.from_euler(Vector3(0.0, ArtStyle3D.cell_hash(pos, 84) * TAU, 0.0)).scaled(Vector3(r, h, r))
	xforms.append(xf)
	colors.append(ArtStyle3D.PALETTE.snow)


func _add_embers(pos: Vector2i, cx: float, cz: float, xforms: Array[Transform3D], colors: Array[Color]) -> void:
	var count := 1 + int(ArtStyle3D.cell_hash(pos, 90) * 1.999)
	for i in range(count):
		var h := lerpf(0.05, 0.12, ArtStyle3D.cell_hash(pos, 91 + i))
		var r := lerpf(0.02, 0.035, ArtStyle3D.cell_hash(pos, 93 + i))
		var ox := (ArtStyle3D.cell_hash(pos, 95 + i) - 0.5) * 0.2
		var oz := (ArtStyle3D.cell_hash(pos, 97 + i) - 0.5) * 0.2
		var xf := Transform3D(Basis.IDENTITY, Vector3(cx + ox, h * 0.4, cz + oz))
		xf.basis = Basis.from_euler(Vector3(0.0, ArtStyle3D.cell_hash(pos, 99 + i) * TAU, 0.0)).scaled(Vector3(r, h, r))
		xforms.append(xf)
		colors.append(Color.WHITE)


## Shared unit 4-sided cone (apex up, centered at the origin); per-instance
## transforms scale/place it.
static var _unit_cone: CylinderMesh


static func _cone() -> CylinderMesh:
	if _unit_cone == null:
		_unit_cone = CylinderMesh.new()
		_unit_cone.top_radius = 0.0
		_unit_cone.bottom_radius = 1.0
		_unit_cone.height = 1.0
		_unit_cone.radial_segments = 4
	return _unit_cone


func _make_multimesh(mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color], material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.set_material_override(material)
	return mmi


func _crystal_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	return mat


func _drift_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	return mat


func _ember_material() -> StandardMaterial3D:
	return ArtStyle3D.get_material(ArtStyle3D.PALETTE.lava, ArtStyle3D.PALETTE.lava, 2.0)
