extends GutTest

var _shell: Node
var _main: Node
var _saved_quality: int


func before_all() -> void:
	_saved_quality = ArtStyle3D.quality
	seed(12345)
	GameManager.set_map_seed(7)
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	WeatherManager.force_snowstorm_end()
	WeatherManager.force_volcano_end()
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)
	for index in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	get_tree().current_scene = _main
	(_main.get_node("World/GridWorld") as GridWorld).set_dynamic_events_enabled(false)
	await _frames(30)


func after_all() -> void:
	ArtStyle3D.apply_quality(_saved_quality)
	WeatherManager.force_snowstorm_end()
	WeatherManager.force_volcano_end()
	WeatherManager.set_weather_events_enabled(true)
	WeatherManager.set_volcano_events_enabled(true)
	var grid := get_node_or_null("/root/Main/World/GridWorld") as GridWorld
	if grid != null:
		grid.set_dynamic_events_enabled(true)
	if _shell != null:
		_shell.free()
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
	GameManager.clear_map_seed()


func _frames(count: int) -> void:
	for index in range(count):
		await get_tree().process_frame


func _backdrop() -> Backdrop3D:
	return _shell.get_node("World3D/Backdrop3D") as Backdrop3D


func test_seeded_layout_replays_and_stays_outside_playable_cells() -> void:
	var backdrop := _backdrop()
	assert_gt(backdrop.layout_log.size(), 20, "three populated ridge layers exist")
	assert_gt(backdrop.detail_log.size(), 20, "distant silhouette dressing exists")
	var first := backdrop.layout_signature()
	var rear_z := (GridWorld.SURFACE_TOP - 1) * Backdrop3D.CELL_WORLD - 0.6
	for mountain in backdrop.layout_log:
		assert_lte(float(mountain["front_z"]), rear_z, "mountain geometry stays behind the surface border")
	for pine in backdrop.detail_log:
		assert_lt(float(pine["z"]), rear_z, "distant pines stay behind the surface border")
	backdrop.setup(_main.get_node("World/GridWorld") as GridWorld)
	assert_eq(backdrop.layout_signature(), first, "the same map seed rebuilds identical backdrop geometry")


func test_tab_hides_and_restores_the_backdrop() -> void:
	var backdrop := _backdrop()
	assert_true(backdrop.visible, "surface view shows the backdrop")
	_main.get_node("PlayerController").set_view(true)
	await _frames(5)
	assert_false(backdrop.visible, "underground view hides all surface scenery")
	_main.get_node("PlayerController").set_view(false)
	await _frames(5)
	assert_true(backdrop.visible, "returning to the surface restores the backdrop")


func test_potato_drops_only_decorative_backdrop_details() -> void:
	_shell._apply_quality_live(ArtStyle3D.Quality.FANCY)
	var backdrop := _backdrop()
	assert_true(backdrop.get_node("Details").visible, "Fancy shows distant pines")
	_shell._apply_quality_live(ArtStyle3D.Quality.POTATO)
	assert_false(backdrop.get_node("Details").visible, "Potato hides distant pines")
	assert_true(backdrop.get_node("LargeForms").visible, "Potato retains cheap ground and ridge forms")
	assert_true(backdrop.visible, "Potato does not hide the whole backdrop")
	_shell._apply_quality_live(_saved_quality)
