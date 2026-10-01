extends Control

## Corner minimap: terrain cells, fog of war, unit/building dots, and the
## camera viewport rect, all code-drawn. Clicking (or dragging) jumps the
## player camera. Self-contained: every external reference is resolved with
## get_node_or_null so the scene also loads standalone.

const UIThemeTokens = preload("res://scripts/ui/ui_theme_tokens.gd")

const _COLS: int = Constants.GRID_X_MAX - Constants.GRID_X_MIN + 1
const _ROWS: int = Constants.GRID_Y_MAX - Constants.GRID_Y_MIN + 1
const _REDRAW_INTERVAL: float = 0.25

const _DIRT_BY_LAYER: Dictionary = {
	1: GameManager.COLOR_DIRT_1,
	2: GameManager.COLOR_DIRT_2,
	3: GameManager.COLOR_DIRT_2,
}
const _COLOR_ORE: Color = Color("#D9A52E")
const _COLOR_FRESH_ORE: Color = Color("#FFD34D")
const _COLOR_LAVA: Color = Color("#D94E12")
const _COLOR_MAGMA_ROCK: Color = Color("#3D221A")
const _COLOR_SOLID_ROCK: Color = Color("#3A3D44")

var _grid: Node2D = null
var _camera: Camera2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(220, 64)
	_grid = get_node_or_null("/root/Main/World/GridWorld")
	_camera = get_node_or_null("/root/Main/Camera2D")
	var timer := Timer.new()
	timer.wait_time = _REDRAW_INTERVAL
	timer.autostart = true
	timer.timeout.connect(queue_redraw)
	add_child(timer)
	resized.connect(queue_redraw)
	if SettingsManager.has_signal("setting_changed"):
		SettingsManager.setting_changed.connect(func(_what: StringName) -> void: queue_redraw())
	queue_redraw()


# ─── Coordinate transforms (world = pixels at TILE_SIZE per cell) ───

func grid_to_map(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		(grid_pos.x - Constants.GRID_X_MIN) * size.x / _COLS,
		(grid_pos.y - Constants.GRID_Y_MIN) * size.y / _ROWS)


func world_to_map(world_pos: Vector2) -> Vector2:
	var fx: float = world_pos.x / Constants.TILE_SIZE - Constants.GRID_X_MIN
	var fy: float = world_pos.y / Constants.TILE_SIZE - Constants.GRID_Y_MIN
	return Vector2(fx * size.x / _COLS, fy * size.y / _ROWS)


func map_to_world(map_pos: Vector2) -> Vector2:
	var gx: float = map_pos.x * _COLS / maxf(size.x, 1.0) + Constants.GRID_X_MIN
	var gy: float = map_pos.y * _ROWS / maxf(size.y, 1.0) + Constants.GRID_Y_MIN
	var world := Vector2((gx + 0.5) * Constants.TILE_SIZE, (gy + 0.5) * Constants.TILE_SIZE)
	var x_min: float = Constants.GRID_X_MIN * Constants.TILE_SIZE
	var x_max: float = (Constants.GRID_X_MAX + 1) * Constants.TILE_SIZE
	var y_max: float = (Constants.GRID_Y_MAX + 1) * Constants.TILE_SIZE
	return Vector2(clampf(world.x, x_min, x_max), clampf(world.y, 0.0, y_max))


# ─── Input ───

func _gui_input(event: InputEvent) -> void:
	if _camera == null:
		return
	var map_pos := Vector2.ZERO
	var jump := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		map_pos = event.position
		jump = true
		accept_event()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		map_pos = event.position
		jump = true
	if jump:
		_camera.global_position = map_to_world(map_pos)


# ─── Drawing ───

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UIThemeTokens.COLOR_RECESSED_BG, true)
	if _grid != null and not _grid._cells.is_empty():
		_draw_terrain()
		_draw_entities()
		_draw_camera_view()
	draw_rect(Rect2(Vector2.ZERO, size), UIThemeTokens.COLOR_RECESSED_BORDER, false, 1.0)


func _draw_terrain() -> void:
	var cw: float = size.x / _COLS
	var ch: float = size.y / _ROWS
	var colorblind: bool = SettingsManager.get_colorblind()
	for pos: Vector2i in _grid._cells:
		var cell: GridWorld.Cell = _grid._cells[pos]
		var rect := Rect2(
			(pos.x - Constants.GRID_X_MIN) * cw,
			(pos.y - Constants.GRID_Y_MIN) * ch,
			cw + 0.6, ch + 0.6)
		match cell.type:
			GridWorld.CellType.SURFACE_GROUND:
				draw_rect(rect, GameManager.COLOR_ICE, true)
			GridWorld.CellType.DIRT:
				draw_rect(rect, _DIRT_BY_LAYER.get(cell.layer, GameManager.COLOR_DIRT_3), true)
			GridWorld.CellType.ORE:
				_draw_ore_cell(rect, colorblind)
			GridWorld.CellType.WALL:
				draw_rect(rect, GameManager.COLOR_STEEL, true)
			GridWorld.CellType.LAVA:
				_draw_lava_cell(rect, colorblind)
			GridWorld.CellType.MAGMA_ROCK:
				draw_rect(rect, _COLOR_MAGMA_ROCK, true)
			GridWorld.CellType.FRESH_ORE:
				draw_rect(rect, _COLOR_FRESH_ORE, true)
				if colorblind:
					draw_rect(rect, Color(0.0, 0.0, 0.0, 0.7), false, 1.0)
			GridWorld.CellType.SOLID_ROCK:
				draw_rect(rect, _COLOR_SOLID_ROCK, true)
		var fog: int = _grid.fog_state_at(GameManager.Team.PLAYER, pos)
		if fog == 0:
			draw_rect(rect, Color(0.02, 0.03, 0.06, 0.88), true)
		elif fog == 1:
			draw_rect(rect, Color(0.02, 0.03, 0.06, 0.45), true)


## Colorblind-safe ore: neutral fill plus a dark dot pattern so the vein does
## not rely on hue alone.
func _draw_ore_cell(rect: Rect2, colorblind: bool) -> void:
	if not colorblind:
		draw_rect(rect, _COLOR_ORE, true)
		return
	draw_rect(rect, Color(0.42, 0.40, 0.38), true)
	var center: Vector2 = rect.get_center()
	draw_rect(Rect2(center - Vector2.ONE * 0.8, Vector2(1.6, 1.6)), Color(0.08, 0.08, 0.09), true)
	draw_rect(Rect2(rect.position + rect.size * 0.2 - Vector2.ONE * 0.6, Vector2(1.2, 1.2)), Color(0.08, 0.08, 0.09), true)
	draw_rect(Rect2(rect.end - rect.size * 0.2 - Vector2.ONE * 0.6, Vector2(1.2, 1.2)), Color(0.08, 0.08, 0.09), true)


## Colorblind-safe lava: dark base with bright diagonal stripes instead of a
## flat hot color.
func _draw_lava_cell(rect: Rect2, colorblind: bool) -> void:
	if not colorblind:
		draw_rect(rect, _COLOR_LAVA, true)
		return
	draw_rect(rect, Color(0.16, 0.10, 0.09), true)
	var a: Vector2 = rect.position + Vector2(rect.size.x * 0.25, 0.0)
	var b: Vector2 = rect.position + Vector2(rect.size.x * 0.75, rect.size.y)
	draw_line(a, b, _COLOR_LAVA, 1.2, true)


func _draw_entities() -> void:
	for b in get_tree().get_nodes_in_group("buildings"):
		if not (b is Node2D):
			continue
		_draw_dot(world_to_map(b.global_position), b.get("team"), 4.0)
	for unit in get_tree().get_nodes_in_group("units"):
		if not (unit is Node2D):
			continue
		_draw_dot(world_to_map(unit.global_position), unit.team, 2.5)


func _draw_dot(map_pos: Vector2, team: Variant, radius: float) -> void:
	var color: Color = UIThemeTokens.COLOR_PLAYER if team == GameManager.Team.PLAYER else UIThemeTokens.COLOR_ENEMY
	draw_rect(Rect2(map_pos - Vector2.ONE * radius * 0.5, Vector2.ONE * radius), color, true)


func _draw_camera_view() -> void:
	if _camera == null:
		return
	var view_size: Vector2 = _camera.get_viewport_rect().size / _camera.zoom
	var tl := world_to_map(_camera.global_position - view_size * 0.5)
	var br := world_to_map(_camera.global_position + view_size * 0.5)
	draw_rect(Rect2(tl, (br - tl).max(Vector2(4.0, 4.0))), Color(1.0, 1.0, 1.0, 0.55), false, 1.0)
