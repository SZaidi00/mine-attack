## 3D fog-of-war mist overlay: replaces the 2.5D port's black-cell look with a
## translucent mist bank hovering over every cell the player cannot currently
## see. Presentation only — reads GridWorld's fog maps, never writes sim state.
##
## One ArrayMesh covers the active layer (surface band or underground, Tab
## view). Alpha lives in the vertex colors: each grid corner averages the fog
## alphas of the up-to-four cells touching it, so the bank feathers smoothly at
## the vision boundary instead of stepping per cell. A small shader drift
## (TIME-based sine noise over world XZ) keeps the mist shimmering like moving
## weather — the 3D equivalent of the 2D renderer's drifting fog puffs
## (grid_fog_of_war.gd _draw_fog_puff). The terrain underneath no longer bakes
## pure black (terrain_3d.gd dims toward FOG_GROUND_TINT), so hidden ground
## reads as terrain seen through mist.
##
## Fog emits no signals (vision recomputes every frame), so the mesh refreshes
## on the same slow poll the terrain uses (REFRESH_INTERVAL). Honors the
## debug/test reveal-all hook: the overlay vanishes entirely.
class_name Fog3D
extends MeshInstance3D

const WORLD_SCALE: float = 0.01
const REFRESH_INTERVAL: float = 0.5
## Hover heights: surface sits above the sculpted bumps and the 0.2 wall
## ridges; the underground floor is flat 0.
const SURFACE_LIFT: float = 0.28
const UNDERGROUND_LIFT: float = 0.06

const ALPHA_VISIBLE: float = 0.0
const ALPHA_REMEMBERED: float = 0.35
const ALPHA_HIDDEN: float = 0.95

## Mist colors mirror the 2D puff tints: cool blue-white clouds on the
## surface, darker cave mist underground.
const MIST_SURFACE := Color(0.62, 0.68, 0.8)
const MIST_UNDERGROUND := Color(0.42, 0.47, 0.58)

const _SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 mist_color : source_color = vec4(0.62, 0.68, 0.8, 1.0);
uniform float drift_enabled = 1.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float n = sin(local_pos.x * 1.7 + TIME * 0.33) * sin(local_pos.z * 2.3 - TIME * 0.21)
		+ 0.5 * sin(local_pos.x * 3.1 - TIME * 0.12 + local_pos.z * 1.3);
	float drift = mix(1.0, 0.82 + 0.18 * clamp(n * 0.5 + 0.5, 0.0, 1.0), drift_enabled);
	ALBEDO = mist_color.rgb;
	ALPHA = clamp(COLOR.a * drift, 0.0, 1.0);
}
"""

var _grid: GridWorld
var _mat: ShaderMaterial
var _underground_view := false
var _accum := 0.0
## Per-cell base alphas from the last rebuild (both layers, one-cell skirt);
## kept for vertex averaging and the alpha_at_cell test/debug helper.
var _alphas: Dictionary = {}  # Vector2i -> float


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


## Layer switch (Tab): rebuild for the other row band with its mist color.
func set_underground_view(underground: bool) -> void:
	if _underground_view == underground:
		return
	_underground_view = underground
	_mat.set_shader_parameter("mist_color", MIST_UNDERGROUND if underground else MIST_SURFACE)
	_rebuild()


## Base (non-feathered) fog alpha for a cell — test/debug helper.
func alpha_at_cell(pos: Vector2i) -> float:
	return _alphas.get(pos, ALPHA_HIDDEN)


func _process(delta: float) -> void:
	_accum += delta
	if _accum >= REFRESH_INTERVAL:
		_accum = 0.0
		_rebuild()


func _cell_alpha(pos: Vector2i) -> float:
	match _grid.fog_state_at(GameManager.Team.PLAYER, pos):
		2:
			return ALPHA_VISIBLE
		1:
			return ALPHA_REMEMBERED
	return ALPHA_HIDDEN


## Fog alpha at a grid corner: the average of the up-to-four cells touching it
## (cells off the map skirt count as hidden so the map edge stays foggy). This
## is what feathers the bank's edge between visible and hidden cells.
func _vertex_alpha(vx: int, vy: int) -> float:
	var sum := 0.0
	for cell in [Vector2i(vx - 1, vy - 1), Vector2i(vx, vy - 1), Vector2i(vx - 1, vy), Vector2i(vx, vy)]:
		sum += _alphas.get(cell, ALPHA_HIDDEN)
	return sum * 0.25


func _rebuild() -> void:
	if _grid == null:
		return
	# Debug/test reveal-all: no overlay at all (mirrors _draw_fog's early-out).
	if _grid._reveal_all.get(GameManager.Team.PLAYER, false):
		mesh = null
		_alphas.clear()
		return
	# Base alphas for the whole grid plus a one-cell skirt, so corner
	# averaging can reach past the rendered layer's edge rows.
	_alphas.clear()
	for x in range(GridWorld.X_MIN - 1, GridWorld.X_MAX + 2):
		for y in range(GridWorld.SURFACE_TOP - 1, GridWorld.Y_MAX + 2):
			_alphas[Vector2i(x, y)] = _cell_alpha(Vector2i(x, y))
	var lift: float = UNDERGROUND_LIFT if _underground_view else SURFACE_LIFT
	var y0: int = GridWorld.Y_MIN + 1 if _underground_view else GridWorld.SURFACE_TOP
	var y1: int = GridWorld.Y_MAX if _underground_view else GridWorld.Y_MIN
	var cell_world: float = GridWorld.CELL_SIZE * WORLD_SCALE
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in range(GridWorld.X_MIN - 1, GridWorld.X_MAX + 2):
		for y in range(y0, y1 + 1):
			# Corner order matches the quad: (x0,z0), (x1,z0), (x1,z1), (x0,z1).
			var a00 := _vertex_alpha(x, y)
			var a10 := _vertex_alpha(x + 1, y)
			var a11 := _vertex_alpha(x + 1, y + 1)
			var a01 := _vertex_alpha(x, y + 1)
			if maxf(maxf(a00, a10), maxf(a11, a01)) < 0.01:
				continue
			var x0: float = x * cell_world
			var x1: float = (x + 1) * cell_world
			var z0: float = y * cell_world
			var z1: float = (y + 1) * cell_world
			st.set_color(Color(1, 1, 1, a00))
			st.add_vertex(Vector3(x0, lift, z0))
			st.set_color(Color(1, 1, 1, a10))
			st.add_vertex(Vector3(x1, lift, z0))
			st.set_color(Color(1, 1, 1, a11))
			st.add_vertex(Vector3(x1, lift, z1))
			st.set_color(Color(1, 1, 1, a00))
			st.add_vertex(Vector3(x0, lift, z0))
			st.set_color(Color(1, 1, 1, a11))
			st.add_vertex(Vector3(x1, lift, z1))
			st.set_color(Color(1, 1, 1, a01))
			st.add_vertex(Vector3(x0, lift, z1))
	mesh = st.commit()
