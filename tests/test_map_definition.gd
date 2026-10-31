extends GutTest

var _map: MapDefinition


func before_each() -> void:
	_map = load("res://scripts/resources/maps/default.tres").duplicate(true)


func test_default_layout_uses_wider_markers() -> void:
	assert_eq(_map.player_building_cell, Vector2i(-40, 0))
	assert_eq(_map.enemy_building_cell, Vector2i(40, 0))
	assert_eq(_map.player_mine_cell, Vector2i(-20, -5))
	assert_eq(_map.enemy_mine_cell, Vector2i(20, -5))


func test_front_road_and_mine_spurs_cover_their_cells() -> void:
	for x in range(GridWorld.X_MIN, GridWorld.X_MAX + 1):
		assert_true(_map.is_road(Vector2i(x, 0)), "front road covers x=%d" % x)
	for x in [-20, 20]:
		for y in range(-5, 1):
			assert_true(_map.is_road(Vector2i(x, y)), "mine spur covers %s" % Vector2i(x, y))
		assert_false(_map.is_road(Vector2i(x, -6)), "spur does not continue above the mine")
	assert_false(_map.is_road(Vector2i(0, -5)), "open midfield is not a road")


func test_authored_regions_use_distinct_recipes() -> void:
	assert_eq(_map.region_at(Vector2i(-32, -5)).get("recipe"), "trees")
	assert_eq(_map.region_at(Vector2i(32, -5)).get("recipe"), "rocks")
	assert_eq(_map.region_at(Vector2i(0, -5)), {})
	assert_gt(_map.region_at(Vector2i(-32, -5)).get("density"), 1.0)
	assert_gt(_map.region_at(Vector2i(32, -5)).get("density"), 1.0)


func test_authored_rectangles_stay_inside_the_surface() -> void:
	for rect in _map.surface_roads:
		_assert_rect_inside_surface(rect)
	for region in _map.surface_regions:
		_assert_rect_inside_surface(region.rect)


func _assert_rect_inside_surface(rect: Rect2i) -> void:
	assert_true(rect.position.x >= GridWorld.X_MIN and rect.end.x - 1 <= GridWorld.X_MAX, "horizontal bounds fit %s" % rect)
	assert_true(rect.position.y >= GridWorld.SURFACE_TOP and rect.end.y - 1 <= GridWorld.Y_MIN, "vertical bounds fit %s" % rect)
