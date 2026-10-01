extends GutTest

# Minimap: presence under the HUD, grid/world -> map transforms, and
# click-to-move camera jumping.

const PLAYER: int = 0

var _main: Node
var _minimap: Control


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	await wait_seconds(0.6)
	_minimap = _main.get_node("UI/HUD/Minimap")


func after_all() -> void:
	_main.free()
	GameManager.clear_map_seed()


func test_minimap_exists_under_hud_with_expected_size() -> void:
	assert_not_null(_minimap, "Minimap must be a child of the HUD")
	assert_true(_minimap is Control)
	assert_almost_eq(_minimap.size.x, 220.0, 1.0)
	assert_almost_eq(_minimap.size.y, 64.0, 1.0)


func test_grid_to_map_maps_known_cells() -> void:
	var origin: Vector2 = _minimap.grid_to_map(Vector2i(Constants.GRID_X_MIN, Constants.GRID_Y_MIN))
	assert_almost_eq(origin.x, 0.0, 0.01)
	assert_almost_eq(origin.y, 0.0, 0.01)
	var cols: int = Constants.GRID_X_MAX - Constants.GRID_X_MIN + 1
	var rows: int = Constants.GRID_Y_MAX - Constants.GRID_Y_MIN + 1
	var cell_zero: Vector2 = _minimap.grid_to_map(Vector2i(0, 1))
	assert_almost_eq(cell_zero.x, -Constants.GRID_X_MIN * _minimap.size.x / cols, 0.5)
	assert_almost_eq(cell_zero.y, (1 - Constants.GRID_Y_MIN) * _minimap.size.y / rows, 0.01)
	# The last cell's top-left corner sits one cell-size short of the edge.
	var far: Vector2 = _minimap.grid_to_map(Vector2i(Constants.GRID_X_MAX, Constants.GRID_Y_MAX))
	assert_almost_eq(far.x, (cols - 1) * _minimap.size.x / cols, 0.5)
	assert_almost_eq(far.y, (rows - 1) * _minimap.size.y / rows, 0.5)


func test_world_to_map_matches_grid_origin() -> void:
	# World (0, 0) is the top-left corner of cell (0, 0).
	var at_world_origin: Vector2 = _minimap.world_to_map(Vector2(0.0, 0.0))
	var cell_origin: Vector2 = _minimap.grid_to_map(Vector2i(0, 0))
	assert_almost_eq(at_world_origin.x, cell_origin.x, 0.5)
	assert_almost_eq(at_world_origin.y, cell_origin.y, 0.5)


func test_map_to_world_jumps_camera_inside_grid() -> void:
	var camera: Camera2D = _main.get_node("Camera2D")
	# Click the top-left corner of the minimap.
	camera.global_position = _minimap.map_to_world(Vector2(1.0, 1.0))
	var cam_cell: Vector2i = _main.get_node("World/GridWorld").world_to_grid(camera.global_position)
	assert_eq(cam_cell, Vector2i(Constants.GRID_X_MIN, Constants.GRID_Y_MIN))
	# Clicking far outside the control still clamps into the grid.
	camera.global_position = _minimap.map_to_world(Vector2(99999.0, 99999.0))
	var clamped: Vector2 = camera.global_position
	assert_true(clamped.x <= (Constants.GRID_X_MAX + 1) * Constants.TILE_SIZE)
	assert_true(clamped.y <= (Constants.GRID_Y_MAX + 1) * Constants.TILE_SIZE)
	assert_true(clamped.x >= Constants.GRID_X_MIN * Constants.TILE_SIZE)
	assert_true(clamped.y >= 0.0)
