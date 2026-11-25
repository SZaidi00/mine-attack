## Ghost-surface "x-ray" memory layer. While the camera is underground, a
## translucent hologram of the surface band stays visible at its true board
## position: a per-cell terrain tint plus team-colored structure markers, all
## frozen at the moment the view left the surface — what you last knew up
## there, not live intel (live unit dots stay on the minimap's job). Cells
## hidden at snapshot time contribute nothing, so the ghost can never leak
## unexplored terrain or an unrevealed enemy base. Presentation only: reads
## GridWorld fog state and the structure groups, never writes sim state.
##
## One ArrayMesh per snapshot, vertex-colored, unshaded, depth-write off —
## the layer floats over the void where the surface terrain would be (the
## terrain pass skips surface rows while underground) and reads as a tactical
## projection of the world above. Everything lerps toward PALETTE.ice so it
## can never be mistaken for the live board.
class_name GhostLayer3D
extends MeshInstance3D

const WORLD_SCALE: float = 0.01
## Hover heights: above the flat plane but below Fog3D's lifts — the two
## never overlap (fog covers only the active layer), the ordering rule just
## keeps the "ground -> ghost -> fog" stack legible.
const GHOST_LIFT: float = 0.04
const MARK_LIFT: float = 0.055

const ALPHA_VISIBLE: float = 0.30
const ALPHA_REMEMBERED: float = 0.16
const ALPHA_MARK: float = 0.5

const HOLO_TINT := ArtStyle3D.PALETTE.ice
const HOLO_DEEP := ArtStyle3D.PALETTE.deep_ice

## Surface structures worth remembering. Traps are deliberately absent: a
## hidden mechanic has no business on a memory hologram. Ladders live
## underground; the mine entries mark the shafts.
const STRUCTURE_GROUPS: Array[StringName] = [
	&"buildings", &"towers", &"walls", &"lanterns", &"mine_entries",
]

var _grid: GridWorld
var _mat: StandardMaterial3D
var _underground_view := false
## Frozen snapshot, taken when the view goes underground: Vector2i cell ->
## fog state (1 remembered / 2 visible; hidden cells are not stored, which is
## what keeps the ghost information-safe).
var _snapshot: Dictionary = {}
## Frozen structure marks: {"cell": Vector2i, "team": GameManager.Team}.
var _marks: Array[Dictionary] = []


func setup(grid: GridWorld) -> void:
	_grid = grid
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	set_material_override(_mat)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = null


func is_underground_view() -> bool:
	return _underground_view


## Tab hook from the shell. Entering the underground freezes the snapshot and
## builds the ghost; surfacing drops it (the live terrain takes over).
func set_underground_view(underground: bool) -> void:
	if _underground_view == underground:
		return
	_underground_view = underground
	if underground:
		take_snapshot()
		_rebuild()
	else:
		_snapshot.clear()
		_marks.clear()
		mesh = null


## Captures the player's fog state over the surface band plus the surface
## structures standing on known cells. Public for tests; the layer otherwise
## only snapshots on the view switch.
func take_snapshot() -> void:
	_snapshot.clear()
	_marks.clear()
	if _grid == null:
		return
	for x in range(GridWorld.X_MIN, GridWorld.X_MAX + 1):
		for y in range(GridWorld.SURFACE_TOP, GridWorld.Y_MIN + 1):
			var pos := Vector2i(x, y)
			var state: int = _grid.fog_state_at(GameManager.Team.PLAYER, pos)
			if state > 0:
				_snapshot[pos] = state
	var tree := get_tree()
	if tree == null:
		return
	for group in STRUCTURE_GROUPS:
		for s in tree.get_nodes_in_group(group):
			var cell: Vector2i = _grid.world_to_grid((s as Node2D).global_position)
			if cell.y > GridWorld.Y_MIN:
				continue  # Underground structures stay off the surface ghost.
			if not _snapshot.has(cell):
				continue  # Never seen, never ghosted.
			var team_v: Variant = s.get("team")
			_marks.append({
				"cell": cell,
				"team": GameManager.Team.ENEMY if team_v == GameManager.Team.ENEMY else GameManager.Team.PLAYER,
			})


## Fog state the snapshot holds for a surface cell: 1/2 when known, 0 when
## the cell was hidden at freeze time, -1 when no snapshot is active (the
## surface view drops the snapshot entirely).
func snapshot_state_at(pos: Vector2i) -> int:
	if _snapshot.is_empty():
		return -1
	return int(_snapshot.get(pos, 0))


func mark_count() -> int:
	return _marks.size()


## Teams present in the frozen structure marks (test/debug readout).
func mark_teams() -> Array:
	var teams: Array = []
	for mark in _marks:
		teams.append(mark["team"])
	return teams


## Ghost alpha per fog state; hidden cells get nothing.
func ghost_alpha_for_state(state: int) -> float:
	match state:
		2:
			return ALPHA_VISIBLE
		1:
			return ALPHA_REMEMBERED
	return 0.0


## Ghost color per fog state (alpha included): visible cells read as pale
## ice, remembered cells sink toward deep-ice shadow.
func ghost_color_for_state(state: int) -> Color:
	match state:
		2:
			return Color(HOLO_TINT, ALPHA_VISIBLE)
		1:
			return Color(HOLO_DEEP, ALPHA_REMEMBERED)
	return Color(0.0, 0.0, 0.0, 0.0)


func _rebuild() -> void:
	if _grid == null or _snapshot.is_empty():
		mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pos: Vector2i in _snapshot:
		_add_quad(st, pos, GHOST_LIFT, ghost_color_for_state(int(_snapshot[pos])))
	for mark in _marks:
		var team_color := ArtStyle3D.team_color(int(mark["team"]))
		_add_quad(st, mark["cell"], MARK_LIFT, Color(team_color.lerp(HOLO_TINT, 0.3), ALPHA_MARK))
	mesh = st.commit()
	if mesh != null and mesh.get_surface_count() == 0:
		mesh = null


func _add_quad(st: SurfaceTool, pos: Vector2i, lift: float, color: Color) -> void:
	var center: Vector2 = _grid.grid_to_world(pos, true)
	var cx := center.x * WORLD_SCALE
	var cz := center.y * WORLD_SCALE
	var half: float = GridWorld.CELL_SIZE * 0.5 * WORLD_SCALE
	var x0 := cx - half
	var x1 := cx + half
	var z0 := cz - half
	var z1 := cz + half
	st.set_color(color)
	st.add_vertex(Vector3(x0, lift, z0))
	st.set_color(color)
	st.add_vertex(Vector3(x1, lift, z0))
	st.set_color(color)
	st.add_vertex(Vector3(x1, lift, z1))
	st.set_color(color)
	st.add_vertex(Vector3(x0, lift, z0))
	st.set_color(color)
	st.add_vertex(Vector3(x1, lift, z1))
	st.set_color(color)
	st.add_vertex(Vector3(x0, lift, z1))
