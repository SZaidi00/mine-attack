## Phase 2 terrain detail (roadmap/3d-conversion/phase-2-art-pass.md §2.3/§2.7).
##
## Per-chunk decorative geometry projected from GridWorld cells, drawn as one
## MultiMeshInstance3D per decoration type per chunk: low-poly ore crystals
## underground (tinted by richness), ember spikes on visible lava, and
## snow-drift mounds on the surface while _snow_level accumulates. Plan 07
## (plans/07-surface-prop-scattering.md) adds the seeded surface prop scatter:
## the plan-06 prop GLBs (boulder/pine/stump/crate) instanced on visible
## SURFACE_GROUND cells, deterministic per (cell, map seed) hash, dune-grounded
## like the drifts, and skipped inside structure clearances. Pure
## sim -> render (the grid is read, never written); densities are
## quality-aware so Potato stays cheap.
##
## NOTE: extends MeshInstance3D (with mesh left null) rather than Node3D so a
## direct child of Terrain3D survives the Phase 1 port test's child loop,
## which casts every Terrain3D child to MeshInstance3D. The plan-07 scatter
## extends this class in place for exactly the same reason (a sibling would
## have to be another null-mesh MeshInstance3D, which buys nothing).
class_name TerrainDetail3D
extends MeshInstance3D

const WORLD_SCALE: float = 0.01
const CHUNK_COLS: int = 21
const CHUNK_ROWS: int = 8

## Plan 06 prop kinds, in scatter-band order (boulder is the most common
## read on a snow field, crate the rarest).
const PROP_KEYS: Array[String] = ["prop_boulder", "prop_pine", "prop_stump", "prop_crate"]
## Fraction of visible surface cells that grow a prop (~1 per 8 cells).
const PROP_DENSITY: float = 0.12
## Scatter hash salts — distinct from the drift/crystal/ember salts (7..99)
## and mixed with the map seed so a pinned seed replays the same board.
const SALT_KIND := 500
const SALT_OFFSET_X := 501
const SALT_OFFSET_Z := 502
const SALT_BAND := 503
const SALT_ROT := 504
const SALT_SCALE := 505
## Scale band keeps the plan-06 height bands visually sub-cell.
const PROP_SCALE_MIN := 0.7
const PROP_SCALE_MAX := 1.1

## BENCH toggle (plan 07 verification): false measures the terrain section
## without the scatter pass for the overhead comparison.
static var scatter_enabled: bool = true

var _grid: GridWorld
var _containers: Dictionary = {}  # Vector2i chunk key -> Node3D holder
## Plan 07 scatter manifest: chunk key -> {prop kind key: Array[Transform3D]}
## of the current rebuild — the same arrays the prop MultiMeshes are built
## from, kept readable because MultiMesh instance data has no reliable
## headless read-back (the dummy/opengl3 servers serve identity), which the
## GUT suite and the F3 probe read for counts/verification.
var scatter_log: Dictionary = {}
var _seed: int = 0


func setup(grid: GridWorld) -> void:
	_grid = grid
	# Same contract as HeightField3D.setup: GridWorld resolves the effective
	# map seed in _ready (runs before the 3D shell sets up), so a pinned seed
	# replays the identical scatter.
	_seed = maxi(grid.map_seed, 0)


## Rebuild the decorations for one terrain chunk right after the chunk's own
## mesh pass. The chunk's holder node is pooled (only its MultiMesh children
## are replaced) and the crystal/drift materials are shared — the old path
## freed and recreated the holder plus two new materials per chunk per
## rebuild batch, which ran at 0.5s intervals for the whole match.
## ground (when given) lifts surface drifts onto the R3 dune field.
func rebuild_chunk(key: Vector2i, x_start: int, y_start: int, underground_view: bool, snow_level: float, ground: HeightField3D = null) -> void:
	scatter_log.erase(key)
	var holder: Node3D
	if _containers.has(key):
		holder = _containers[key]
		for child in holder.get_children():
			child.free()
	else:
		holder = Node3D.new()
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
	var prop_xfs: Array = []  # per prop kind: Array[Transform3D]
	for i in range(PROP_KEYS.size()):
		prop_xfs.append([] as Array[Transform3D])
	var scatter_us := 0  # Probe3D: scatter share of this chunk rebuild
	for dy in range(CHUNK_ROWS):
		for dx in range(CHUNK_COLS):
			var pos := Vector2i(x_start + dx, y_start + dy)
			if pos.y < GridWorld.SURFACE_TOP or pos.y > GridWorld.Y_MAX + 1:
				continue
			if not _grid.has_cell(pos):
				continue
			if underground_view and _grid.is_surface_row(pos.y):
				continue
			if not underground_view and not _grid.is_surface_row(pos.y):
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
				_add_drift(pos, cx, cz, snow_level, drifts_xf, drifts_col, ground)
				if scatter_enabled:
					var scatter_start := Time.get_ticks_usec() if Probe3D.enabled else 0
					_add_prop(pos, cx, cz, ground, prop_xfs)
					if Probe3D.enabled:
						scatter_us += Time.get_ticks_usec() - scatter_start
	if not crystals_xf.is_empty():
		holder.add_child(_make_multimesh(_cone(), crystals_xf, crystals_col, _detail_material()))
	if not drifts_xf.is_empty():
		holder.add_child(_make_multimesh(_cone(), drifts_xf, drifts_col, _detail_material()))
	if not embers_xf.is_empty():
		holder.add_child(_make_multimesh(_cone(), embers_xf, embers_col, _ember_material()))
	for i in range(PROP_KEYS.size()):
		if not (prop_xfs[i] as Array[Transform3D]).is_empty():
			holder.add_child(_make_prop_multimesh(PROP_KEYS[i], prop_xfs[i]))
	if Probe3D.enabled and scatter_us > 0:
		Probe3D.add("terrain_scatter", scatter_us / 1000.0)
	var log: Dictionary = {}
	for i in range(PROP_KEYS.size()):
		if not (prop_xfs[i] as Array[Transform3D]).is_empty():
			log[PROP_KEYS[i]] = prop_xfs[i]
	if not log.is_empty():
		scatter_log[key] = log


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


func _add_drift(pos: Vector2i, cx: float, cz: float, snow_level: float, xforms: Array[Transform3D], colors: Array[Color], ground: HeightField3D) -> void:
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
	# R3: drifts ride the dune surface so a mound never floats over a dip
	# (ground is null only in legacy test call-sites, where 0 is right).
	var gy := 0.0 if ground == null else ground.height_at(cx + ox, cz + oz)
	var xf := Transform3D(Basis.IDENTITY, Vector3(cx + ox, gy + h * 0.3, cz + oz))
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


## Plan 07 surface scatter. One candidate per visible SURFACE_GROUND cell:
## the map-seed-mixed cell hash decides presence (PROP_DENSITY), sub-cell
## offset, prop kind band (boulder/pine/stump/crate), rotation, and scale.
## Candidates inside a structure clearance stamp are dropped (the same stamp
## set that flattens the dunes), and survivors ground-snap to the dune field
## exactly like the drifts. Never randf()/randi() — determinism is the
## Play Again promise (GameManager.map_seed).
func _add_prop(pos: Vector2i, cx: float, cz: float, ground: HeightField3D, xfs: Array) -> void:
	if ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_KIND)) >= PROP_DENSITY:
		return
	var ox := (ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_OFFSET_X)) - 0.5) * 0.18
	var oz := (ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_OFFSET_Z)) - 0.5) * 0.18
	var wx := cx + ox
	var wz := cz + oz
	# Clearance: the field flattens to trampled ground within CLEAR_RADIUS of
	# structures; props stay out of that whole disc (ground is null only in
	# legacy test call-sites, where clearance filtering has no meaning).
	if ground != null and ground.clearance_at_cell(wx / HeightField3D.CELL_WORLD, wz / HeightField3D.CELL_WORLD) > 0.0:
		return
	var band := ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_BAND))
	var kind := 0
	if band >= 0.38:
		kind = 1 if band < 0.68 else (2 if band < 0.84 else 3)
	var source := _prop_source(PROP_KEYS[kind])
	if source.is_empty():
		return
	var rot := ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_ROT)) * TAU
	var s := lerpf(PROP_SCALE_MIN, PROP_SCALE_MAX, ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_SCALE)))
	var gy := 0.0 if ground == null else ground.height_at(wx, wz)
	var place := Transform3D(Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s)), Vector3(wx, gy, wz))
	# Per-instance transform = placement * the loader-style normalization
	# (footprint scale, min-y at 0, XZ centered) baked once per prop kind.
	(xfs[kind] as Array[Transform3D]).append(place * (source["norm"] as Transform3D))


func _scatter_salt(base: int) -> int:
	return base + _seed * 31


## Shared prop meshes, cached per kind for the session ({} on load failure,
## which simply scatters nothing). The mesh keeps its imported per-surface
## materials — no override, no per-instance colors: the painted atlas is the
## read. norm is the StructureModelLoader-style normalization composed into
## every instance transform.
static var _prop_sources: Dictionary = {}


static func _prop_source(key: String) -> Dictionary:
	if _prop_sources.has(key):
		return _prop_sources[key]
	var source := {}
	var entry := ModelManifest.entry_for(key)
	var packed: Variant = null
	if not entry.is_empty():
		packed = load(str(entry.get("path", "")))
	if packed != null and packed is PackedScene:
		var instance: Node3D = (packed as PackedScene).instantiate()
		var scan := _MeshScan.new()
		_scan_meshes(instance, Transform3D.IDENTITY, scan)
		if scan.count == 1 and scan.first_xform.is_equal_approx(Transform3D.IDENTITY):
			# House GLBs are a single identity-transform mesh node: share the
			# imported mesh resource directly, no re-pack.
			source["mesh"] = scan.first_mesh
		elif scan.count > 0:
			source["mesh"] = _merged_mesh(scan)
		if source.has("mesh"):
			var bounds: AABB = (source["mesh"] as Mesh).get_aabb()
			var fp: Array = entry.get("footprint", [1, 1])
			var fw := float(fp[0]) * HeightField3D.CELL_WORLD
			var fh := float(fp[1]) * HeightField3D.CELL_WORLD
			var scale := minf(fw / maxf(bounds.size.x, 0.0001), fh / maxf(bounds.size.z, 0.0001))
			var center := bounds.get_center()
			var norm := Transform3D(Basis.from_scale(Vector3.ONE * scale), Vector3.ZERO)
			norm = norm.translated(Vector3(-center.x, -bounds.position.y, -center.z))
			source["norm"] = norm
		instance.free()
	_prop_sources[key] = source
	return source


class _MeshScan:
	var count := 0
	var first_mesh: Mesh = null
	var first_xform := Transform3D.IDENTITY
	## Merged-surface accumulation (multi-mesh props): arrays with the node's
	## scene-space transform baked into vertices/normals, material per source
	## surface.
	var surfaces: Array = []  # Array of {"arrays": Array, "material": Material}


static func _scan_meshes(node: Node3D, parent_xform: Transform3D, scan: _MeshScan) -> void:
	var xform := parent_xform * node.transform
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		if scan.count == 0:
			scan.first_mesh = mi.mesh
			scan.first_xform = xform
		scan.count += 1
		if not xform.is_equal_approx(Transform3D.IDENTITY):
			for s in range(mi.mesh.get_surface_count()):
				var arrays := (mi.mesh.surface_get_arrays(s) as Array).duplicate()
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var normal_xform := xform.basis.inverse().transposed()
				for i in range(verts.size()):
					verts[i] = xform * verts[i]
					if i < normals.size():
						normals[i] = (normal_xform * normals[i]).normalized()
				arrays[Mesh.ARRAY_VERTEX] = verts
				arrays[Mesh.ARRAY_NORMAL] = normals
				arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array()
				scan.surfaces.append({"arrays": arrays, "material": mi.mesh.surface_get_material(s)})
		else:
			for s in range(mi.mesh.get_surface_count()):
				scan.surfaces.append({"arrays": mi.mesh.surface_get_arrays(s), "material": mi.mesh.surface_get_material(s)})
	for child in node.get_children():
		if child is Node3D:
			_scan_meshes(child, xform, scan)


static func _merged_mesh(scan: _MeshScan) -> ArrayMesh:
	var merged := ArrayMesh.new()
	for surface in scan.surfaces:
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface["arrays"])
		merged.surface_set_material(merged.get_surface_count() - 1, surface["material"])
	return merged


static func _make_prop_multimesh(key: String, xforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _prop_source(key)["mesh"]
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Prop_" + key
	mmi.multimesh = mm
	return mmi

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


## Crystal and drift materials are configured identically (vertex-color
## albedo, shared roughness) — one cached instance serves both, so a rebuild
## batch no longer allocates two materials per chunk.
static var _detail_mat: StandardMaterial3D


static func _detail_material() -> StandardMaterial3D:
	if _detail_mat == null:
		_detail_mat = StandardMaterial3D.new()
		_detail_mat.vertex_color_use_as_albedo = true
		_detail_mat.roughness = ArtStyle3D.MATERIAL_ROUGHNESS
	return _detail_mat


func _ember_material() -> StandardMaterial3D:
	# 3D rework phase 5 emission hierarchy: decorative embers sit at the
	# bottom (was 2.0 — they outshone the ambient lava glow they decorate).
	return ArtStyle3D.get_material(ArtStyle3D.PALETTE.lava, ArtStyle3D.PALETTE.lava, 0.9)
