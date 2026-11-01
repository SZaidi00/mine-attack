extends GutTest

# Plan 14: mode-specific world profiles. The Play Mode pick resolves a
# MapDefinition before GridWorld initializes: "3d"/capture/default tests boot
# the wide 101x10 authored board, "2d" boots the main-branch legacy board
# (81 columns, one surface row, bases at x=±30, corner-origin mines at
# x=±15 on row 0, camera (0,-150)). The GridWorld bounds are match-scoped
# statics applied atomically by apply_world_profile(); every sim _enter_tree
# re-applies its profile, and this script restores "wide" at the end so the
# statics cannot leak to later test scripts.

const DEFAULT_MAP: MapDefinition = preload("res://scripts/resources/maps/default.tres")
const LEGACY_MAP: MapDefinition = preload("res://scripts/resources/maps/legacy.tres")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _legacy_main: Node = null


func before_all() -> void:
	# Pin the launch intent even on a developer machine whose persisted
	# play-mode setting is "2d" — only explicit intent selects legacy.
	GameManager.set_world_profile_request("wide")


func after_all() -> void:
	_free_legacy()
	# Restore wide twice over: the statics directly, then one fresh sim boot
	# so the launch-intent path re-applies the wide profile too.
	GameManager.set_world_profile_request("wide")
	GridWorld.apply_world_profile(DEFAULT_MAP)
	var fresh: Node = MAIN_SCENE.instantiate()
	get_tree().root.add_child(fresh)
	get_tree().current_scene = fresh
	fresh.free()
	assert_eq(GridWorld.SURFACE_TOP, -9, "suite continues on the wide board")


func _free_legacy() -> void:
	if _legacy_main != null and is_instance_valid(_legacy_main):
		_legacy_main.free()
	_legacy_main = null


# ─── Static profile application ───

func test_default_profile_restores_wide_statics() -> void:
	GridWorld.apply_world_profile(DEFAULT_MAP)
	assert_eq(GridWorld.X_MIN, -50)
	assert_eq(GridWorld.X_MAX, 50)
	assert_eq(GridWorld.SURFACE_ROWS, 10)
	assert_eq(GridWorld.SURFACE_TOP, -9, "SURFACE_TOP derives from Y_MIN - rows + 1")


func test_legacy_profile_sets_main_style_bounds() -> void:
	GridWorld.apply_world_profile(LEGACY_MAP)
	assert_eq(GridWorld.X_MIN, -40)
	assert_eq(GridWorld.X_MAX, 40)
	assert_eq(GridWorld.SURFACE_ROWS, 1)
	assert_eq(GridWorld.SURFACE_TOP, 0, "a single surface row lives on row 0")
	GridWorld.apply_world_profile(DEFAULT_MAP)


func test_null_profile_restores_wide_defaults() -> void:
	GridWorld.apply_world_profile(LEGACY_MAP)
	GridWorld.apply_world_profile(null)
	assert_eq(GridWorld.X_MIN, -50)
	assert_eq(GridWorld.X_MAX, 50)
	assert_eq(GridWorld.SURFACE_ROWS, 10)
	assert_eq(GridWorld.SURFACE_TOP, -9)


func test_degenerate_profile_bounds_fall_back_to_wide() -> void:
	var inverted := MapDefinition.new()
	inverted.grid_x_min = 10
	inverted.grid_x_max = -10
	GridWorld.apply_world_profile(inverted)
	assert_push_error("degenerate world bounds")
	assert_eq(GridWorld.X_MIN, -50, "an inverted X range is rejected")
	assert_eq(GridWorld.X_MAX, 50)
	assert_eq(GridWorld.SURFACE_TOP, -9)
	var no_rows := MapDefinition.new()
	no_rows.surface_rows = 0
	GridWorld.apply_world_profile(no_rows)
	assert_push_error("degenerate world bounds")
	assert_eq(GridWorld.SURFACE_ROWS, 10, "surface_rows < 1 is rejected")


# ─── Launch intent ───

func test_request_defaults_wide_and_validates() -> void:
	GameManager.set_world_profile_request("wide")
	assert_eq(GameManager.world_profile_request, "wide")
	GameManager.set_world_profile_request("legacy")
	assert_eq(GameManager.world_profile_request, "legacy")
	GameManager.set_world_profile_request("hologram")
	assert_eq(GameManager.world_profile_request, "wide", "unknown requests fall back to wide")


func test_reset_preserves_world_profile_request() -> void:
	GameManager.set_world_profile_request("legacy")
	GameManager.reset()
	assert_eq(GameManager.world_profile_request, "legacy", "reset() must not clear launch intent")
	GameManager.set_world_profile_request("wide")
	GameManager.reset()
	assert_eq(GameManager.world_profile_request, "wide")


# ─── Legacy boot ───

func test_legacy_request_boots_main_style_world() -> void:
	GameManager.set_world_profile_request("legacy")
	_legacy_main = MAIN_SCENE.instantiate()
	get_tree().root.add_child(_legacy_main)
	get_tree().current_scene = _legacy_main
	var grid: GridWorld = _legacy_main.get_node("World/GridWorld")
	# The profile statics were applied before any child _ready ran.
	assert_eq(GridWorld.X_MIN, -40)
	assert_eq(GridWorld.X_MAX, 40)
	assert_eq(GridWorld.SURFACE_ROWS, 1)
	assert_eq(GridWorld.SURFACE_TOP, 0)
	assert_eq((_legacy_main.get("map_definition") as MapDefinition).resource_path,
		LEGACY_MAP.resource_path, "the legacy resource replaced the exported wide map")
	# Exactly 81 surface cells and all of them on row 0; nothing exists at y<0.
	var surface_count: int = 0
	for pos: Vector2i in grid._cells:
		assert_false(pos.y < 0, "no playable cells below row 0 (found %s)" % pos)
		if grid._cells[pos].type == GridWorld.CellType.SURFACE_GROUND:
			surface_count += 1
			assert_eq(pos.y, 0, "surface ground only lives on row 0")
	assert_eq(surface_count, 81, "the legacy board is 81 columns wide")
	# Border walls stand one column outside the playable range.
	for y in [0, 5, GridWorld.Y_MAX]:
		assert_true(grid.is_wall(Vector2i(-41, y)), "west border wall at y=%d" % y)
		assert_true(grid.is_wall(Vector2i(41, y)), "east border wall at y=%d" % y)
	# main-branch layout: bases at ±30, corner-origin mines at ±15, camera (0,-150).
	assert_eq(_legacy_main.get_node("World/PlayerBuilding").position, Vector2(-960, 0))
	assert_eq(_legacy_main.get_node("World/EnemyBuilding").position, Vector2(960, 0))
	assert_eq(_legacy_main.get_node("World/PlayerMineEntry").position, Vector2(-480, 0))
	assert_eq(_legacy_main.get_node("World/EnemyMineEntry").position, Vector2(480, 0))
	assert_eq(_legacy_main.get_node("Camera2D").position, Vector2(0, -150))
	# Shafts are carved only at x=±15 (no stale wide-map shafts at ±20).
	assert_null(grid.get_cell(Vector2i(-15, 3)), "player shaft carved at x=-15")
	assert_null(grid.get_cell(Vector2i(15, 3)), "enemy shaft carved at x=15")
	assert_not_null(grid.get_cell(Vector2i(-20, 3)), "no shaft at the wide-map column -20")
	assert_not_null(grid.get_cell(Vector2i(20, 3)), "no shaft at the wide-map column 20")
	_free_legacy()
	GameManager.set_world_profile_request("wide")
	GridWorld.apply_world_profile(DEFAULT_MAP)


func test_wide_request_boots_the_authored_world() -> void:
	GameManager.set_world_profile_request("wide")
	var wide_main: Node = MAIN_SCENE.instantiate()
	get_tree().root.add_child(wide_main)
	get_tree().current_scene = wide_main
	var grid: GridWorld = wide_main.get_node("World/GridWorld")
	assert_eq(GridWorld.SURFACE_TOP, -9)
	assert_eq(GridWorld.SURFACE_ROWS, 10)
	# Playable band cells (border walls stand one column outside X_MIN/X_MAX).
	var surface_count: int = 0
	for pos: Vector2i in grid._cells:
		if grid.is_surface_row(pos.y) and pos.x >= GridWorld.X_MIN and pos.x <= GridWorld.X_MAX:
			surface_count += 1
	assert_eq(surface_count, 101 * 10, "the wide board keeps its full surface band")
	assert_eq(wide_main.get_node("Camera2D").position, Vector2(0, -128))
	assert_null(grid.get_cell(Vector2i(-20, 3)), "wide shafts stay at the authored columns")
	assert_not_null(grid.get_cell(Vector2i(-15, 3)), "no legacy shaft at x=-15")
	wide_main.free()
