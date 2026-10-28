## R3 height-field surface (roadmap/3d-visual-revamp/03-technical-plan.md §2).
##
## Deterministic dune field over the surface band: layered value noise plus
## ridged bands elongated along map X (wind sweeping the narrow battlefield
## strip), sampled per terrain-quad corner so chunk meshes displace without
## extra vertices. Seeded from the match's map seed (GridWorld.map_seed), so
## seeded captures replay the exact same dunes. The field is a pure function
## of position — no storage, no sim writes.
##
## Clearances: dunes flatten to trampled ground within 1 cell of structures,
## wall segments, mine entries, and building footprints (queried from
## GridWorld occupancy + the live structure groups), and across the central
## wall's packed-snow approach. A snowstorm progressively flattens the dunes
## and fills dips (the terrain's snow cover tween drives set_storm_level).
class_name HeightField3D
extends RefCounted

## World-units size of one grid cell (matches Presentation3D.WORLD_SCALE).
const CELL_WORLD: float = GridWorld.CELL_SIZE * 0.01
## §2 budget: dune peaks never exceed 0.4 cells.
const DUNE_HEIGHT: float = 0.4 * CELL_WORLD
## Full flat within 1 cell of a stamped structure, feathering out to 2.
const CLEAR_RADIUS: float = 2.0
## Storm-attenuation cap: a settled storm keeps 20% of the relief.
const STORM_KEEP: float = 0.2

var _grid: GridWorld
var _seed: int = 0
var _storm_level: float = 0.0
## Surface cells within a structure clearance, strength 0..1 (bilinear-
## sampled between cells so the feather stays continuous at corners).
var _clear: Dictionary = {}  # Vector2i -> float


func setup(grid: GridWorld) -> void:
	_grid = grid
	# GridWorld resolves the effective seed in _ready (user-pinned, debug, or
	# rolled once per match), so the dunes are identical for the same map.
	_seed = maxi(grid.map_seed, 0)


func set_storm_level(level: float) -> void:
	_storm_level = clampf(level, 0.0, 1.0)


## Ground height in world units at a world XZ position (0 outside the
## sculpted surface band — the underground floor stays flat for the flat
## X-Y plane view, §3).
func height_at(world_x: float, world_z: float) -> float:
	return height_at_cell(world_x / CELL_WORLD, world_z / CELL_WORLD)


## Ground height at continuous grid-cell coordinates (cell (0,0) spans
## [0,1) x [0,1)). Corner-shared between adjacent quads, so chunk seams stay
## watertight.
func height_at_cell(cx: float, cy: float) -> float:
	if _grid == null:
		return 0.0
	var cell_pos := Vector2i(floori(cx), floori(cy))
	var cell: GridWorld.Cell = _grid.get_cell(cell_pos)
	if cell == null or cell.type == GridWorld.CellType.EMPTY:
		return 0.0
	if not _grid.is_surface_row(cell_pos.y):
		return 0.0
	if cell.type == GridWorld.CellType.WALL:
		# Wall cells keep their packed-snow ridge (the clearance only flattens
		# the approach); a fine jitter keeps the ridge from reading machined.
		var ridge := lerpf(0.12, 0.2, ArtStyle3D.cell_hash(cell_pos, 2))
		ridge += (_value_noise(cx * 2.7, cy * 2.7, 105) - 0.5) * 0.02
		return ridge
	var n := _dune_noise(cx, cy)
	# Shape into mostly-positive mounds with shallow dips; peaks hit the
	# DUNE_HEIGHT cap, dips bottom out around -0.55 of it.
	var shape := clampf((n - 0.40) * 1.7, -0.55, 1.0)
	var amp := 1.0 - _clearance_at(cx, cy)
	amp *= lerpf(1.0, STORM_KEEP, _storm_level)
	return DUNE_HEIGHT * shape * amp


## Rebuild the structure-clearance stamp set. Called by the terrain at each
## rebuild batch (throttled); structure placement mid-match re-flattens its
## neighbourhood on the next pass.
func refresh_clearances() -> void:
	_clear.clear()
	if _grid == null or not _grid.is_inside_tree():
		return
	# WALL-type surface cells: central wall, map border, and building
	# footprints (building.gd seals its band cells as WALL).
	for x in range(GridWorld.X_MIN - 1, GridWorld.X_MAX + 2):
		for y in range(GridWorld.SURFACE_TOP, GridWorld.Y_MIN + 1):
			var cell: GridWorld.Cell = _grid.get_cell(Vector2i(x, y))
			if cell != null and cell.type == GridWorld.CellType.WALL:
				_stamp(x, y)
	# Live structures that stand on plain ground cells (towers, lanterns,
	# wall segments, traps, mine entries) — occupancy the cell types don't
	# record.
	var tree := _grid.get_tree()
	for group in [&"buildings", &"towers", &"lanterns", &"walls", &"traps", &"mine_entries"]:
		for node in tree.get_nodes_in_group(group):
			if node is not Node2D:
				continue
			var cell_pos: Vector2i = _grid.world_to_grid((node as Node2D).global_position)
			if cell_pos.y >= GridWorld.SURFACE_TOP and cell_pos.y <= GridWorld.Y_MIN:
				_stamp(cell_pos.x, cell_pos.y)


# ─── Internals ───


func _stamp(cx: int, cy: int) -> void:
	var r := int(ceil(CLEAR_RADIUS))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d := Vector2(dx, dy).length()
			var s := clampf(CLEAR_RADIUS - d, 0.0, 1.0)
			if s <= 0.0:
				continue
			var pos := Vector2i(cx + dx, cy + dy)
			_clear[pos] = maxf(float(_clear.get(pos, 0.0)), s)


func _clearance_at(cx: float, cy: float) -> float:
	var x0 := floori(cx)
	var y0 := floori(cy)
	var fx := cx - x0
	var fy := cy - y0
	var s00 := _strength_at(x0, y0)
	var s10 := _strength_at(x0 + 1, y0)
	var s01 := _strength_at(x0, y0 + 1)
	var s11 := _strength_at(x0 + 1, y0 + 1)
	return lerpf(lerpf(s00, s10, fx), lerpf(s01, s11, fx), fy)


func _strength_at(x: int, y: int) -> float:
	return float(_clear.get(Vector2i(x, y), 0.0))


## Rolling base: three octaves of value noise (periods ~13/6/3 cells).
## Ridged bands: value noise stretched along map X so crests run with the
## wind across the narrow surface band, sharpened by a pow curve. Both in
## [0,1], blended 60/40.
func _dune_noise(cx: float, cy: float) -> float:
	var base := _value_noise(cx * 0.075, cy * 0.075, 101) * 0.5 \
		+ _value_noise(cx * 0.16, cy * 0.16, 102) * 0.3 \
		+ _value_noise(cx * 0.33, cy * 0.33, 103) * 0.2
	var band := _value_noise(cx * 0.045 + 17.3, cy * 0.38 + 5.9, 104)
	band = pow(1.0 - absf(2.0 * band - 1.0), 1.6)
	return base * 0.6 + band * 0.4


## Seeded 2D value noise on the integer lattice, smootherstep-interpolated —
## deterministic and independent of any global RNG stream.
func _value_noise(x: float, y: float, salt: int) -> float:
	var x0 := floori(x)
	var y0 := floori(y)
	var ux := x - x0
	var uy := y - y0
	ux = ux * ux * (3.0 - 2.0 * ux)
	uy = uy * uy * (3.0 - 2.0 * uy)
	var v00 := _hash(x0, y0, salt)
	var v10 := _hash(x0 + 1, y0, salt)
	var v01 := _hash(x0, y0 + 1, salt)
	var v11 := _hash(x0 + 1, y0 + 1, salt)
	return lerpf(lerpf(v00, v10, ux), lerpf(v01, v11, ux), uy)


func _hash(ix: int, iy: int, salt: int) -> float:
	var h: int = ix * 374761393 + iy * 668265263 + salt * 1442695041 + _seed * 69069
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)
