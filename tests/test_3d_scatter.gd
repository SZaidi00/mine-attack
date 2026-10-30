extends GutTest

# Plan 07 (plans/07-surface-prop-scattering.md): the surface band carries
# seeded, fog-honest, clearance-aware prop scatter — the plan-06 prop GLBs
# (boulder/pine/stump/crate) instanced per visible surface cell. Same pinned
# seed must replay the identical board (Play Again), a structure placement
# must clear props in its radius on notify_structures_changed(), hidden fog
# cells stay bare, and props ride the dune field like the drifts.

const CLEARED_CELLS := 0.9

var _shell: Node
var _main: Node
var _saved_quality: int


func before_all() -> void:
	_saved_quality = ArtStyle3D.quality


func after_all() -> void:
	ArtStyle3D.apply_quality(_saved_quality)


func after_each() -> void:
	_shutdown()


func _boot(map_seed: int) -> void:
	seed(12345)
	GameManager.set_map_seed(map_seed)
	# No random weather/lava/cave-in rolls mid-test; forced triggers only.
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	WeatherManager.force_snowstorm_end()
	WeatherManager.force_volcano_end()
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)
	# The sim mounts deferred; wait for it, then adopt it as current_scene
	# (house style from test_3d_terrain_art.gd).
	for i in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	get_tree().current_scene = _main
	(_main.get_node("World/GridWorld") as GridWorld).set_dynamic_events_enabled(false)


func _shutdown() -> void:
	# Restore the forced weather state and the scheduling flags the autoloads
	# keep across scene reloads, then free immediately (not queue_free) so the
	# next boot's /root/Main lookup isn't shadowed (house style).
	WeatherManager.force_snowstorm_end()
	WeatherManager.force_volcano_end()
	WeatherManager.set_weather_events_enabled(true)
	WeatherManager.set_volcano_events_enabled(true)
	var grid: GridWorld = get_node_or_null("/root/Main/World/GridWorld") as GridWorld
	if grid != null:
		grid.set_dynamic_events_enabled(true)
	if _shell != null:
		_shell.free()
		_shell = null
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
		_main = null
	GameManager.clear_map_seed()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _terrain() -> Node:
	return _shell.get_node("World3D/Terrain3D")


func _grid() -> GridWorld:
	return _main.get_node("World/GridWorld") as GridWorld


## Flattened per-instance transforms of the current scatter, straight from
## the manifest TerrainDetail3D rebuilds alongside the prop MultiMeshes
## (MultiMesh instance data has no reliable headless read-back).
func _collect_prop_transforms() -> Array:
	var out: Array = []
	var detail: Node = _terrain().get_node("TerrainDetail")
	for key in (detail as TerrainDetail3D).scatter_log:
		var kinds: Dictionary = (detail as TerrainDetail3D).scatter_log[key]
		for kind in kinds:
			for xf in kinds[kind]:
				out.append(xf)
	return out


func _cell_of(xf: Transform3D) -> Vector2i:
	return _grid().world_to_grid(Vector2(xf.origin.x, xf.origin.z) / TerrainDetail3D.WORLD_SCALE)


func test_same_seed_rebuilds_identical_scatter() -> void:
	await _boot(7)
	await _frames(30)
	var first := _collect_prop_transforms()
	assert_gt(first.size(), 0, "seed 7 scatters props on the surface band")
	_terrain().force_full_rebuild()
	await _frames(10)
	var second := _collect_prop_transforms()
	assert_eq(second.size(), first.size(), "same seed → same instance count across rebuilds")
	assert_eq(second, first, "same seed → identical transforms across rebuilds")


func test_different_seed_scatters_differently() -> void:
	await _boot(7)
	await _frames(30)
	var seed_seven := _collect_prop_transforms()
	assert_gt(seed_seven.size(), 0, "seed 7 scatters props on the surface band")
	_shutdown()
	await _boot(9)
	await _frames(30)
	var seed_nine := _collect_prop_transforms()
	assert_gt(seed_nine.size(), 0, "seed 9 scatters props on the surface band")
	assert_ne(seed_nine, seed_seven, "different pinned seeds scatter different boards")


func test_structure_placement_clears_props_in_its_radius() -> void:
	await _boot(7)
	await _frames(30)
	var grid := _grid()
	var before := _collect_prop_transforms()
	assert_gt(before.size(), 0, "props exist before the tower lands")
	# Tower on the cell of the first scattered prop: its cell center is within
	# the prop's offset, i.e. well inside the clearance radius being tested.
	var victim: Transform3D = before[0]
	var cell := _cell_of(victim)
	var center_px: Vector2 = grid.grid_to_world(cell)
	var tower: Node2D = load("res://scenes/tower.tscn").instantiate()
	tower.set("team", GameManager.Team.PLAYER)
	tower.position = center_px
	_main.get_node("Structures").add_child(tower)
	tower.set("_is_built", true)
	var center := center_px * TerrainDetail3D.WORLD_SCALE
	_terrain().notify_structures_changed()
	await _frames(40)
	var after := _collect_prop_transforms()
	var min_world := CLEARED_CELLS * HeightField3D.CELL_WORLD
	for xf in after:
		assert_gt(Vector2(xf.origin.x, xf.origin.z).distance_to(center), min_world,
			"no prop within %.1f cells of the new tower" % CLEARED_CELLS)
	tower.free()
	_terrain().notify_structures_changed()
	await _frames(40)
	assert_gt(_collect_prop_transforms().size(), 0,
		"demolishing the tower lets the neighbourhood scatter again")


func test_props_only_on_visible_cells() -> void:
	await _boot(7)
	await _frames(30)
	_terrain().force_full_rebuild()
	await _frames(10)
	var transforms := _collect_prop_transforms()
	assert_gt(transforms.size(), 0, "visible surface cells carry props")
	for xf in transforms:
		var cell := _cell_of(xf)
		assert_eq(_grid().fog_state_at(GameManager.Team.PLAYER, cell), 2,
			"prop at %s sits on a fog-visible cell" % cell)


func test_props_ride_the_dune_surface() -> void:
	await _boot(7)
	await _frames(30)
	var terrain := _terrain()
	var transforms := _collect_prop_transforms()
	assert_gt(transforms.size(), 0, "props exist to ground-check")
	for xf in transforms:
		var gy: float = terrain.world_height_at(xf.origin.x, xf.origin.z)
		assert_almost_eq(xf.origin.y, gy, 0.01,
			"prop base sits on the dune field, never floating over a dip")


func test_potato_disables_prop_scatter() -> void:
	await _boot(7)
	await _frames(30)
	assert_gt(_collect_prop_transforms().size(), 0,
		"precondition: the default quality scatters props")
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.POTATO)
	_terrain().force_full_rebuild()
	await _frames(30)
	assert_eq(_collect_prop_transforms().size(), 0,
		"Potato grows no props (the ArtStyle3D.detail_enabled gate)")


# Plan 07 perf gate: the scatter pass must stay a small fraction of the
# terrain rebuild section. Probe3D script-time averages with scatter on vs
# the scatter_enabled=false toggle (the BENCH comparison flag).
func test_scatter_cost_stays_a_small_fraction_of_terrain_rebuild() -> void:
	await _boot(7)
	await _frames(30)
	Probe3D.enabled = true
	Probe3D.reset()
	_terrain().force_full_rebuild()
	await _frames(30)
	var averages := Probe3D.averages()
	var scatter_ms: float = averages.get("terrain_scatter", 0.0)
	var total_ms: float = averages.get("terrain_rebuild", 0.0)
	TerrainDetail3D.scatter_enabled = false
	Probe3D.reset()
	_terrain().force_full_rebuild()
	await _frames(30)
	var without_scatter_ms: float = Probe3D.averages().get("terrain_rebuild", 0.0)
	Probe3D.enabled = false
	TerrainDetail3D.scatter_enabled = true
	print("PERF terrain_rebuild with scatter: %.3f ms avg (scatter %.3f ms) | without scatter: %.3f ms" \
		% [total_ms, scatter_ms, without_scatter_ms])
	assert_gt(scatter_ms, 0.0, "the probe captured the scatter section")
	assert_gt(total_ms, 0.0, "the probe captured the terrain rebuild batch")
	assert_lt(scatter_ms, total_ms * 0.25,
		"scatter stays under a quarter of the terrain rebuild section")
