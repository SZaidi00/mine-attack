## 3D fog-of-war overlay. Unexplored cells are an opaque void, remembered
## cells sit in deep shadow, and visible cells are clear. Presentation only —
## reads GridWorld's fog maps, never writes sim state.
##
## One ArrayMesh covers the active layer. Each grid corner averages the RGBA
## colors of its four touching cells, feathering both color and opacity at the
## vision boundary. Shader noise perturbs only transitional alpha values, so
## fully hidden cells never become translucent and visible cells stay clear.
## Lantern OmniLights illuminate visible underground terrain inside the exact
## sim-owned vision cutoff; this overlay does not duplicate vision radii.
class_name Fog3D
extends MeshInstance3D

const WORLD_SCALE: float = 0.01
const REFRESH_INTERVAL: float = 0.5
const SURFACE_LIFT: float = 0.28
const UNDERGROUND_LIFT: float = 0.06

const ALPHA_VISIBLE: float = 0.0
const ALPHA_REMEMBERED: float = 0.72
const ALPHA_HIDDEN: float = 1.0
const VOID_COLOR := ArtStyle3D.PALETTE.fog_void
const SHADOW_COLOR := ArtStyle3D.PALETTE.rock_dark

const _SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform float drift_enabled = 1.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float n = sin(local_pos.x * 1.7 + TIME * 0.33) * sin(local_pos.z * 2.3 - TIME * 0.21)
		+ 0.5 * sin(local_pos.x * 3.1 - TIME * 0.12 + local_pos.z * 1.3);
	float base_alpha = clamp(COLOR.a, 0.0, 1.0);
	float edge_weight = sin(PI * base_alpha);
	float drift = n * 0.055 * edge_weight * drift_enabled;
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(base_alpha + drift, 0.0, 1.0);
}
"""

var _grid: GridWorld
var _mat: ShaderMaterial
var _underground_view := false
var _accum := 0.0
## Per-cell fog states (0 hidden / 1 remembered / 2 visible) from the last
## rebuild, stored as per-column Arrays indexed [x - (X_MIN-1)][y - (SURFACE_TOP-1)]
## (the one-cell skirt included, off-map reads hidden) — the corner-averaging
## pass used to do ~28k Dictionary lookups per rebuild against a color map;
## these are plain array reads and the three states map to three constants.
var _states: Array = []
## Last player_fog_revision consumed; the refresh tick only rebuilds when the
## sim's fog recompute actually changed something (vision moves, memory
## expiry, reveal-all flips) instead of committing a new mesh every 0.5s.
var _seen_revision := -1
## Lazily-filled corner-color table keyed by state counts (n2*100 + n1*10 +
## n0): all four corner colors are constants, so an average depends only on
## how many of each state the four touching cells are in.
var _corner_colors: Dictionary = {}


func setup(grid: GridWorld) -> void:
	_grid = grid
	var sh := Shader.new()
	sh.code = _SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("drift_enabled", 0.0 if ArtStyle3D.quality == ArtStyle3D.Quality.POTATO else 1.0)
	set_material_override(_mat)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rebuild()
	_seen_revision = _grid.player_fog_revision


func is_underground_view() -> bool:
	return _underground_view


## Quality flip (live settings switch): Potato turns the edge-drift shader
## noise off; the rebuild-driven state already follows ArtStyle3D elsewhere.
func apply_quality() -> void:
	_mat.set_shader_parameter("drift_enabled", 0.0 if ArtStyle3D.quality == ArtStyle3D.Quality.POTATO else 1.0)


func set_underground_view(underground: bool) -> void:
	if _underground_view == underground:
		return
	_underground_view = underground
	_rebuild()


func alpha_at_cell(pos: Vector2i) -> float:
	return color_at_cell(pos).a


func color_at_cell(pos: Vector2i) -> Color:
	match _state_at(pos.x, pos.y):
		2:
			return Color(1.0, 1.0, 1.0, ALPHA_VISIBLE)
		1:
			return Color(SHADOW_COLOR, ALPHA_REMEMBERED)
	return Color(VOID_COLOR, ALPHA_HIDDEN)


func _process(delta: float) -> void:
	_accum += delta
	if _accum < REFRESH_INTERVAL:
		return
	_accum = 0.0
	# Rebuild only when the sim's per-frame fog recompute detected an actual
	# state change (GridFogOfWar bumps player_fog_revision). The old 0.5s
	# unconditional rebuild committed a brand-new mesh twice a second for the
	# whole match, changed or not.
	if _grid == null or _grid.player_fog_revision == _seen_revision:
		return
	_seen_revision = _grid.player_fog_revision
	_rebuild()


## Fog state at grid-space corner coordinates; off-map counts hidden (the old
## _colors default) so the feathered edge fades into the void.
func _state_at(vx: int, vy: int) -> int:
	var ix: int = vx - (GridWorld.X_MIN - 1)
	var iy: int = vy - (GridWorld.SURFACE_TOP - 1)
	if ix < 0 or ix >= _states.size() or iy < 0:
		return 0
	var col: Array = _states[ix]
	if iy >= col.size():
		return 0
	return col[iy]


func _average_corner_color(n0: int, n1: int, n2: int) -> Color:
	var key := n2 * 100 + n1 * 10 + n0
	var cached: Variant = _corner_colors.get(key)
	if cached != null:
		return cached
	var c := (Color(VOID_COLOR, ALPHA_HIDDEN) * n0 \
		+ Color(SHADOW_COLOR, ALPHA_REMEMBERED) * n1 \
		+ Color(1.0, 1.0, 1.0, ALPHA_VISIBLE) * n2) * 0.25
	_corner_colors[key] = c
	return c


## Average the RGBA of the four touching cells. Every per-state color is a
## constant, so the average is a pure function of the state counts — table
## lookup instead of four Color adds per corner.
func _vertex_color(vx: int, vy: int) -> Color:
	var s00 := _state_at(vx - 1, vy - 1)
	var s10 := _state_at(vx, vy - 1)
	var s01 := _state_at(vx - 1, vy)
	var s11 := _state_at(vx, vy)
	var n2 := int(s00 == 2) + int(s10 == 2) + int(s01 == 2) + int(s11 == 2)
	var n1 := int(s00 == 1) + int(s10 == 1) + int(s01 == 1) + int(s11 == 1)
	return _average_corner_color(4 - n2 - n1, n1, n2)


func _vertex_alpha(vx: int, vy: int) -> float:
	return _vertex_color(vx, vy).a


func _rebuild() -> void:
	if _grid == null:
		return
	var probe_start := Time.get_ticks_usec() if Probe3D.enabled else 0
	if _grid._reveal_all.get(GameManager.Team.PLAYER, false):
		mesh = null
		_states.clear()
		if Probe3D.enabled:
			Probe3D.add("fog_rebuild", (Time.get_ticks_usec() - probe_start) / 1000.0)
		return
	# One fog_state_at per cell (skirt included); the quad pass below reads
	# these as plain array entries.
	_states.clear()
	for x in range(GridWorld.X_MIN - 1, GridWorld.X_MAX + 2):
		var col: Array = []
		col.resize(GridWorld.Y_MAX - GridWorld.SURFACE_TOP + 3)
		for y in range(GridWorld.SURFACE_TOP - 1, GridWorld.Y_MAX + 2):
			col[y - (GridWorld.SURFACE_TOP - 1)] = _grid.fog_state_at(GameManager.Team.PLAYER, Vector2i(x, y))
		_states.append(col)
	var lift: float = UNDERGROUND_LIFT if _underground_view else SURFACE_LIFT
	var y0: int = GridWorld.Y_MIN + 1 if _underground_view else GridWorld.SURFACE_TOP
	var y1: int = GridWorld.Y_MAX if _underground_view else GridWorld.Y_MIN
	var cell_world: float = GridWorld.CELL_SIZE * WORLD_SCALE
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in range(GridWorld.X_MIN - 1, GridWorld.X_MAX + 2):
		for y in range(y0, y1 + 1):
			var c00 := _vertex_color(x, y)
			var c10 := _vertex_color(x + 1, y)
			var c11 := _vertex_color(x + 1, y + 1)
			var c01 := _vertex_color(x, y + 1)
			if maxf(maxf(c00.a, c10.a), maxf(c11.a, c01.a)) < 0.01:
				continue
			var x0: float = x * cell_world
			var x1: float = (x + 1) * cell_world
			var z0: float = y * cell_world
			var z1: float = (y + 1) * cell_world
			st.set_color(c00)
			st.add_vertex(Vector3(x0, lift, z0))
			st.set_color(c10)
			st.add_vertex(Vector3(x1, lift, z0))
			st.set_color(c11)
			st.add_vertex(Vector3(x1, lift, z1))
			st.set_color(c00)
			st.add_vertex(Vector3(x0, lift, z0))
			st.set_color(c11)
			st.add_vertex(Vector3(x1, lift, z1))
			st.set_color(c01)
			st.add_vertex(Vector3(x0, lift, z1))
	mesh = st.commit()
	if Probe3D.enabled:
		Probe3D.add("fog_rebuild", (Time.get_ticks_usec() - probe_start) / 1000.0)
