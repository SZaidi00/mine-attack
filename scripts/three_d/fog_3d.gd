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
## Per-cell base colors from the last rebuild (both layers, one-cell skirt).
var _colors: Dictionary = {}  # Vector2i -> Color


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


func is_underground_view() -> bool:
	return _underground_view


func set_underground_view(underground: bool) -> void:
	if _underground_view == underground:
		return
	_underground_view = underground
	_rebuild()


func alpha_at_cell(pos: Vector2i) -> float:
	return color_at_cell(pos).a


func color_at_cell(pos: Vector2i) -> Color:
	return _colors.get(pos, Color(VOID_COLOR, ALPHA_HIDDEN))


func _process(delta: float) -> void:
	_accum += delta
	if _accum >= REFRESH_INTERVAL:
		_accum = 0.0
		_rebuild()


func _cell_color(pos: Vector2i) -> Color:
	match _grid.fog_state_at(GameManager.Team.PLAYER, pos):
		2:
			return Color(1.0, 1.0, 1.0, ALPHA_VISIBLE)
		1:
			return Color(SHADOW_COLOR, ALPHA_REMEMBERED)
	return Color(VOID_COLOR, ALPHA_HIDDEN)


## Average full RGBA values so the hidden void and remembered shadow feather
## into one another as well as into visible ground. Off-map cells count hidden.
func _vertex_color(vx: int, vy: int) -> Color:
	var sum := Color(0.0, 0.0, 0.0, 0.0)
	for cell in [Vector2i(vx - 1, vy - 1), Vector2i(vx, vy - 1), Vector2i(vx - 1, vy), Vector2i(vx, vy)]:
		sum += color_at_cell(cell)
	return sum * 0.25


func _vertex_alpha(vx: int, vy: int) -> float:
	return _vertex_color(vx, vy).a


func _rebuild() -> void:
	if _grid == null:
		return
	if _grid._reveal_all.get(GameManager.Team.PLAYER, false):
		mesh = null
		_colors.clear()
		return
	_colors.clear()
	for x in range(GridWorld.X_MIN - 1, GridWorld.X_MAX + 2):
		for y in range(GridWorld.SURFACE_TOP - 1, GridWorld.Y_MAX + 2):
			var pos := Vector2i(x, y)
			_colors[pos] = _cell_color(pos)
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
