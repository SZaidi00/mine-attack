## Phase 2 terrain detail (roadmap/3d-conversion/phase-2-art-pass.md §2.3/§2.7).
##
## Per-chunk decorative geometry projected from GridWorld cells, drawn as one
## MultiMeshInstance3D per decoration type per chunk: low-poly ore crystals
## underground (tinted by richness), ember spikes on visible lava, and
## snow-drift mounds on the surface while _snow_level accumulates. Plan 07
## (plans/07-surface-prop-scattering.md) adds the seeded surface prop scatter;
## plan 09 composes generated + curated pack GLBs into map-seeded cluster
## noise and zone-aware kinds on visible SURFACE_GROUND cells. Plan 12 adds
## MapDefinition-authored road exclusion and tree/rock region recipes. Plan 13
## adds the underground decoration pass: timber support frames on DIRT cells
## bordering excavated floors and sparse curated pebble rubble on solid rock /
## depleted ore, logged to underground_log (never scatter_log) and probed as
## underground_detail. Every instance
## is dune-grounded and skipped inside structure clearances. Multi-node kit
## meshes bake node transforms into merged surfaces, including normal-map
## tangents. Pure sim -> render (the grid is read, never written); densities
## are quality-aware so Potato stays cheap.
##
## NOTE: extends MeshInstance3D (with mesh left null) rather than Node3D so a
## direct child of Terrain3D survives the Phase 1 port test's child loop,
## which casts every Terrain3D child to MeshInstance3D. The plan-07 scatter
## extends this class in place for exactly the same reason (a sibling would
## have to be another null-mesh MeshInstance3D, which buys nothing).
class_name TerrainDetail3D
extends MeshInstance3D

const WORLD_SCALE: float = 0.01
const CHUNK_COLS: int = 26
const CHUNK_ROWS: int = 8

const PROP_KEYS: Array[String] = [
	"prop_boulder", "prop_pine", "prop_stump", "prop_crate",
	"pack_rock_medium_1", "pack_rock_medium_2", "pack_rock_medium_3",
	"pack_dead_tree_3", "pack_dead_tree_5", "pack_grass_wispy", "pack_bush_common",
]
const ROCK_KINDS: Array[int] = [0, 4, 5, 6]
const TREE_KINDS: Array[int] = [1, 7, 8]
const LOW_KINDS: Array[int] = [2, 3, 9, 10]
const BASE_PROP_DENSITY: float = 0.12
const CLUSTER_PROP_DENSITY: float = 0.42
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

## Plan 13 underground decoration: the only curated rubble keys (already
## imported kit pebbles). Their authored footprints span up to ~2 cells, so
## instances are squashed flat against the host cell's edge — never placed in
## missing tunnel-floor cells, never blocking walkable centers.
const UNDERGROUND_PEBBLE_KEYS: Array[String] = [
	"pack_pebble_round_1", "pack_pebble_round_3", "pack_pebble_square_2",
]
## Salt family 1200..1299 — distinct from drift/crystal/ember (7..99) and
## scatter (500..505); seed-mixed via _scatter_salt so a pinned seed replays
## the same decoration.
const SALT_SUPPORT := 1200
const SALT_SUPPORT_HEIGHT := 1201
const SALT_PEBBLE := 1210
const SALT_PEBBLE_KIND := 1211
const SALT_PEBBLE_SIDE := 1212
const SUPPORT_CHANCE: float = 0.16
const ROCK_PEBBLE_CHANCE: float = 0.3
const DEPLETED_ORE_PEBBLE_CHANCE: float = 0.24
## Timber frame dims (world units): small doorframe silhouettes that stay
## below unit height and well inside their host cell.
const SUPPORT_POST_W: float = 0.036
const SUPPORT_LINTEL_L: float = 0.30
const SUPPORT_LINTEL_H: float = 0.05
const SUPPORT_LINTEL_D: float = 0.045
const SUPPORT_EDGE_INSET: float = 0.035
const PEBBLE_MARGIN: float = 0.008

## BENCH toggle (plan 07 verification): false measures the terrain section
## without the scatter pass for the overhead comparison.
static var scatter_enabled: bool = true

var _grid: GridWorld
var map_definition: MapDefinition
var _containers: Dictionary = {}  # Vector2i chunk key -> Node3D holder
## Plan 07 scatter manifest: chunk key -> {prop kind key: Array[Transform3D]}
## of the current rebuild — the same arrays the prop MultiMeshes are built
## from, kept readable because MultiMesh instance data has no reliable
## headless read-back (the dummy/opengl3 servers serve identity), which the
## GUT suite and the F3 probe read for counts/verification.
var scatter_log: Dictionary = {}
## Plan 13 underground manifest: chunk key -> {entry kind: Array[Transform3D]}
## of the current rebuild — kinds are "support_post", "support_lintel", and the
## UNDERGROUND_PEBBLE_KEYS. Kept separate from scatter_log, which the surface
## region tests interpret as surface props; MultiMesh data itself has no
## reliable headless read-back, so the arrays are stored alongside.
var underground_log: Dictionary = {}
var _seed: int = 0
var _cluster_noise := FastNoiseLite.new()


func setup(grid: GridWorld, definition: MapDefinition = null) -> void:
	_grid = grid
	map_definition = definition
	# Same contract as HeightField3D.setup: GridWorld resolves the effective
	# map seed in _ready (runs before the 3D shell sets up), so a pinned seed
	# replays the identical scatter.
	_seed = maxi(grid.map_seed, 0)
	_cluster_noise.seed = _seed * 31 + 503
	_cluster_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cluster_noise.frequency = 0.16
	_cluster_noise.fractal_octaves = 2


## Rebuild the decorations for one terrain chunk right after the chunk's own
## mesh pass. The chunk's holder node is pooled (only its MultiMesh children
## are replaced) and the crystal/drift materials are shared — the old path
## freed and recreated the holder plus two new materials per chunk per
## rebuild batch, which ran at 0.5s intervals for the whole match.
## ground (when given) lifts surface drifts onto the R3 dune field.
func rebuild_chunk(key: Vector2i, x_start: int, y_start: int, underground_view: bool, snow_level: float, ground: HeightField3D = null) -> void:
	scatter_log.erase(key)
	underground_log.erase(key)
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
					GridWorld.CellType.ORE, GridWorld.CellType.FRESH_ORE:
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
	if underground_view:
		# Plan 13: timber supports and edge rubble run as their own timed
		# section (underground_detail), never inside the surface scatter probe.
		var ug_start := Time.get_ticks_usec() if Probe3D.enabled else 0
		_populate_underground(key, x_start, y_start, holder)
		if Probe3D.enabled:
			Probe3D.add("underground_detail", (Time.get_ticks_usec() - ug_start) / 1000.0)
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


# ─── Plan 13: underground supports and rubble ───

## Timber frames on visible DIRT cells that border an excavated floor, plus
## sparse dark pebble rubble on cave-in/magma rock and depleted ore. Runs only
## on Standard/Fancy (the caller gates on detail_enabled), only on fog-visible
## cells, and everything is seed-deterministic via _scatter_salt. Decorative
## only — no collision, no support mechanic, no sim writes.
func _populate_underground(key: Vector2i, x_start: int, y_start: int, holder: Node3D) -> void:
	var posts_xf: Array[Transform3D] = []
	var posts_col: Array[Color] = []
	var lintels_xf: Array[Transform3D] = []
	var lintels_col: Array[Color] = []
	var pebble_xfs: Array = []
	for i in range(UNDERGROUND_PEBBLE_KEYS.size()):
		pebble_xfs.append([] as Array[Transform3D])
	for dy in range(CHUNK_ROWS):
		for dx in range(CHUNK_COLS):
			var pos := Vector2i(x_start + dx, y_start + dy)
			if pos.y < GridWorld.Y_MIN + 1 or pos.y > GridWorld.Y_MAX:
				continue
			var cell: GridWorld.Cell = _grid._cells.get(pos)
			if cell == null or cell.type == GridWorld.CellType.EMPTY:
				continue
			if _grid.fog_state_at(GameManager.Team.PLAYER, pos) != 2:
				continue
			var center: Vector2 = _grid.grid_to_world(pos, true)
			var cx := center.x * WORLD_SCALE
			var cz := center.y * WORLD_SCALE
			match cell.type:
				GridWorld.CellType.DIRT:
					_maybe_add_support(pos, cx, cz, posts_xf, posts_col, lintels_xf, lintels_col)
				GridWorld.CellType.SOLID_ROCK, GridWorld.CellType.MAGMA_ROCK:
					_maybe_add_pebble(pos, cx, cz, ROCK_PEBBLE_CHANCE, pebble_xfs)
				GridWorld.CellType.ORE:
					# Rich veins stay crystal-dominant; only exhausted tiles
					# gain a small rubble accent.
					if GridMining.is_depleted(cell):
						_maybe_add_pebble(pos, cx, cz, DEPLETED_ORE_PEBBLE_CHANCE, pebble_xfs)
	if not posts_xf.is_empty():
		holder.add_child(_make_multimesh(_box(), posts_xf, posts_col, _detail_material()))
		holder.add_child(_make_multimesh(_box(), lintels_xf, lintels_col, _detail_material()))
	for i in range(UNDERGROUND_PEBBLE_KEYS.size()):
		if not (pebble_xfs[i] as Array[Transform3D]).is_empty():
			holder.add_child(_make_prop_multimesh(UNDERGROUND_PEBBLE_KEYS[i], pebble_xfs[i]))
	var log: Dictionary = {}
	if not posts_xf.is_empty():
		log["support_post"] = posts_xf
		log["support_lintel"] = lintels_xf
	for i in range(UNDERGROUND_PEBBLE_KEYS.size()):
		if not (pebble_xfs[i] as Array[Transform3D]).is_empty():
			log[UNDERGROUND_PEBBLE_KEYS[i]] = pebble_xfs[i]
	if not log.is_empty():
		underground_log[key] = log


## First orthogonal neighbor (fixed scan order) that is an excavated cell —
## the tunnel mouth a support frame faces or a rubble pebble hugs. Returns
## Vector2i.ZERO when the cell borders no excavated space.
func _excavated_neighbor(pos: Vector2i) -> Vector2i:
	for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var n: Vector2i = pos + dir
		if n.y > GridWorld.Y_MIN and n.y <= GridWorld.Y_MAX \
				and n.x >= GridWorld.X_MIN and n.x <= GridWorld.X_MAX \
				and not _grid.has_cell(n):
			return dir
	return Vector2i.ZERO


## One timber doorframe per eligible cell: two posts plus a lintel spanning
## the edge shared with the excavated neighbor, standing just inside the solid
## cell so tunnel centers stay clear. Low probability plus the ore guard keep
## tunnels from becoming support forests and veins crystal-dominant.
func _maybe_add_support(pos: Vector2i, cx: float, cz: float,
		posts_xf: Array[Transform3D], posts_col: Array[Color],
		lintels_xf: Array[Transform3D], lintels_col: Array[Color]) -> void:
	var face := _excavated_neighbor(pos)
	if face == Vector2i.ZERO:
		return
	if ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_SUPPORT)) >= SUPPORT_CHANCE:
		return
	for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var n: GridWorld.Cell = _grid._cells.get(pos + dir)
		if n != null and (n.type == GridWorld.CellType.ORE
				or n.type == GridWorld.CellType.FRESH_ORE):
			return
	var height := lerpf(0.26, 0.32, ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_SUPPORT_HEIGHT)))
	var half_cell: float = GridWorld.CELL_SIZE * 0.5 * WORLD_SCALE
	var post_span := SUPPORT_LINTEL_L * 0.5 - SUPPORT_POST_W * 0.5
	# Frame plane sits inside the solid cell, this far off the shared edge.
	var fx := cx
	var fz := cz
	if face == Vector2i.RIGHT:
		fx = cx + half_cell - SUPPORT_EDGE_INSET
	elif face == Vector2i.LEFT:
		fx = cx - half_cell + SUPPORT_EDGE_INSET
	elif face == Vector2i.DOWN:
		fz = cz + half_cell - SUPPORT_EDGE_INSET
	else:
		fz = cz - half_cell + SUPPORT_EDGE_INSET
	# Posts stand along the frame axis (x for LEFT/RIGHT faces, z otherwise).
	var post_a := Vector3(fx, height * 0.5, cz - post_span)
	var post_b := Vector3(fx, height * 0.5, cz + post_span)
	var lintel_origin := Vector3(fx, height - SUPPORT_LINTEL_H * 0.5, cz)
	var post_scale := Vector3(SUPPORT_POST_W, height, SUPPORT_POST_W)
	var lintel_scale := Vector3(SUPPORT_LINTEL_D, SUPPORT_LINTEL_H, SUPPORT_LINTEL_L)
	if face == Vector2i.LEFT or face == Vector2i.RIGHT:
		post_a = Vector3(cx - post_span, height * 0.5, fz)
		post_b = Vector3(cx + post_span, height * 0.5, fz)
		lintel_origin = Vector3(cx, height - SUPPORT_LINTEL_H * 0.5, fz)
		lintel_scale = Vector3(SUPPORT_LINTEL_L, SUPPORT_LINTEL_H, SUPPORT_LINTEL_D)
	for p in [post_a, post_b]:
		posts_xf.append(Transform3D(Basis.from_scale(post_scale), p))
		posts_col.append(ArtStyle3D.PALETTE.wood)
	lintels_xf.append(Transform3D(Basis.from_scale(lintel_scale), lintel_origin))
	lintels_col.append(ArtStyle3D.PALETTE.wood_dark)


## Sparse dark rubble flush to a cell edge — the edge shared with an excavated
## neighbor when there is one, else a deterministic edge. The authored pebble
## footprints span up to ~2 cells, so each instance squashes the facing axis
## (and narrows the along axis) while keeping the imported 0.12 height band,
## and the whole footprint stays inside the host cell: rubble reads against
## the wall and never fills a walkable tunnel center.
func _maybe_add_pebble(pos: Vector2i, cx: float, cz: float, chance: float, pebble_xfs: Array) -> void:
	if ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_PEBBLE)) >= chance:
		return
	var kind := mini(int(ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_PEBBLE_KIND)) \
		* UNDERGROUND_PEBBLE_KEYS.size()), UNDERGROUND_PEBBLE_KEYS.size() - 1)
	var source := _prop_source(UNDERGROUND_PEBBLE_KEYS[kind])
	if source.is_empty():
		return
	var norm := source["norm"] as Transform3D
	var bounds: AABB = (source["mesh"] as Mesh).get_aabb()
	var norm_scale := norm.basis.get_scale().x
	# World extents after the imported footprint normalization.
	var ext_x := bounds.size.x * norm_scale
	var ext_z := bounds.size.z * norm_scale
	var face := _excavated_neighbor(pos)
	if face == Vector2i.ZERO:
		var side := int(ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_PEBBLE_SIDE)) * 4.0)
		face = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN][mini(side, 3)]
	var h1 := ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_PEBBLE_SIDE + 1))
	var h2 := ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_PEBBLE_SIDE + 2))
	# Uniform squash (0.34..0.48) keeps every authored footprint inside the
	# 0.32 cell while preserving the imported 0.12 height band; facing axis
	# numbers below are shared by both orientations.
	var squash := lerpf(0.34, 0.48, h1)
	var half_cell: float = GridWorld.CELL_SIZE * 0.5 * WORLD_SCALE
	var px := cx
	var pz := cz
	var span := half_cell - maxf(ext_x, ext_z) * squash * 0.5 - PEBBLE_MARGIN
	if face == Vector2i.RIGHT:
		px = cx + half_cell - ext_x * squash * 0.5 - PEBBLE_MARGIN
		pz = cz + span * (h2 * 2.0 - 1.0)
	elif face == Vector2i.LEFT:
		px = cx - half_cell + ext_x * squash * 0.5 + PEBBLE_MARGIN
		pz = cz + span * (h2 * 2.0 - 1.0)
	elif face == Vector2i.DOWN:
		pz = cz + half_cell - ext_z * squash * 0.5 - PEBBLE_MARGIN
		px = cx + span * (h2 * 2.0 - 1.0)
	else:
		pz = cz - half_cell + ext_z * squash * 0.5 + PEBBLE_MARGIN
		px = cx + span * (h2 * 2.0 - 1.0)
	var place := Transform3D(Basis.from_scale(Vector3(squash, 1.0, squash)), Vector3(px, 0.0, pz))
	(pebble_xfs[kind] as Array[Transform3D]).append(place * norm)


func _add_prop(pos: Vector2i, cx: float, cz: float, ground: HeightField3D, xfs: Array) -> void:
	if map_definition != null and map_definition.is_road(pos):
		return
	var cluster := _cluster_noise.get_noise_2d(pos.x, pos.y)
	var region: Dictionary = map_definition.region_at(pos) if map_definition != null else {}
	var density: float = _prop_density(pos, cluster) * float(region.get("density", 1.0))
	if ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_KIND)) >= density:
		return
	var ox := (ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_OFFSET_X)) - 0.5) * 0.18
	var oz := (ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_OFFSET_Z)) - 0.5) * 0.18
	var wx := cx + ox
	var wz := cz + oz
	if ground != null and ground.clearance_at_cell(wx / HeightField3D.CELL_WORLD, wz / HeightField3D.CELL_WORLD) > 0.0:
		return
	var band := ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_BAND))
	var kind := _pick_kind(pos, band, cluster, str(region.get("recipe", "")))
	var source := _prop_source(PROP_KEYS[kind])
	if source.is_empty():
		return
	var rot := ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_ROT)) * TAU
	var s := lerpf(PROP_SCALE_MIN, PROP_SCALE_MAX, ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_SCALE)))
	var gy := 0.0 if ground == null else ground.height_at(wx, wz)
	var place := Transform3D(Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s)), Vector3(wx, gy, wz))
	(xfs[kind] as Array[Transform3D]).append(place * (source["norm"] as Transform3D))


func _prop_density(pos: Vector2i, cluster: float) -> float:
	var density := lerpf(BASE_PROP_DENSITY, CLUSTER_PROP_DENSITY, smoothstep(-0.35, 0.65, cluster))
	if pos.y >= -1:
		density *= 0.65
	if abs(pos.x) <= 6:
		density *= 0.55
	return density


func _pick_kind(pos: Vector2i, band: float, cluster: float, recipe: String = "") -> int:
	var choices := ROCK_KINDS
	match recipe:
		"trees":
			choices = TREE_KINDS
		"rocks":
			choices = ROCK_KINDS
		"low":
			choices = LOW_KINDS
		_:
			if abs(pos.x) > 10 and cluster > 0.05 and pos.y < 0 and band < 0.34:
				choices = TREE_KINDS
			elif band >= 0.68:
				choices = LOW_KINDS
	var index := mini(int(ArtStyle3D.cell_hash(pos, _scatter_salt(SALT_KIND + 17)) * choices.size()), choices.size() - 1)
	return choices[index]


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
				var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
				var normal_xform := xform.basis.inverse().transposed()
				for i in range(verts.size()):
					verts[i] = xform * verts[i]
					if i < normals.size():
						normals[i] = (normal_xform * normals[i]).normalized()
					if tangents.size() == verts.size() * 4:
						var tangent := (normal_xform * Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])).normalized()
						tangents[i * 4] = tangent.x
						tangents[i * 4 + 1] = tangent.y
						tangents[i * 4 + 2] = tangent.z
				arrays[Mesh.ARRAY_VERTEX] = verts
				arrays[Mesh.ARRAY_NORMAL] = normals
				arrays[Mesh.ARRAY_TANGENT] = tangents if tangents.size() == verts.size() * 4 else null
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


## Shared unit cube for the plan-13 timber frames; per-instance transforms
## scale/place the posts and lintels.
static var _unit_box: BoxMesh


static func _box() -> BoxMesh:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE
	return _unit_box


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
