extends GutTest

# Phase 2 art pass (roadmap/3d-conversion/phase-2-art-pass.md §2.3/§2.7):
# the terrain projection is sculpted — deterministic per-cell surface
# heights, storm-driven snow cover, a pulsing emissive lava pass — and
# TerrainDetail3D grows MultiMesh ore crystals / snow drifts / ember spikes
# per chunk. All presentation; the sim stays untouched (house style from
# test_3d_port.gd / test_3d_effects.gd).

var _shell: Node
var _main: Node


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	# No random weather/lava/cave-in rolls mid-test; forced triggers only.
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	WeatherManager.force_snowstorm_end()
	WeatherManager.force_volcano_end()
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)
	# The sim mounts deferred; wait for it, then adopt it as current_scene
	# (house style from test_3d_port.gd).
	for i in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	get_tree().current_scene = _main
	(_main.get_node("World/GridWorld") as GridWorld).set_dynamic_events_enabled(false)


func after_all() -> void:
	# Restore any forced weather state and the scheduling flags the autoloads
	# keep across scene reloads, then free immediately (not queue_free) so the
	# next test script's /root/Main lookup isn't shadowed (house style).
	WeatherManager.force_snowstorm_end()
	WeatherManager.force_volcano_end()
	WeatherManager.set_weather_events_enabled(true)
	WeatherManager.set_volcano_events_enabled(true)
	var grid: GridWorld = get_node_or_null("/root/Main/World/GridWorld") as GridWorld
	if grid != null:
		grid.set_dynamic_events_enabled(true)
	_shell.free()
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
	GameManager.clear_map_seed()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _terrain() -> Node:
	return _shell.get_node("World3D/Terrain3D")


func test_surface_chunks_are_sculpted_with_varying_height() -> void:
	await _frames(30)
	var terrain := _terrain()
	terrain.set_underground_view(false)
	await _frames(10)
	var min_y := 1e9
	var max_y := -1e9
	for chunk in terrain.get_children():
		if not (chunk is MeshInstance3D):
			continue
		var mi: MeshInstance3D = chunk
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var positions: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v in positions:
			min_y = minf(min_y, v.y)
			max_y = maxf(max_y, v.y)
	assert_gt(max_y, min_y, "surface quads have varying Y (sculpted terrain)")
	assert_gt(max_y, 0.1, "border wall cells rise as a ridge above the ground")


func test_snow_cover_accumulates_and_melts_with_storms() -> void:
	await _frames(10)
	var terrain := _terrain()
	assert_almost_eq(terrain.get_snow_level(), 0.0, 0.001, "no snow cover before any storm")
	WeatherManager.force_snowstorm_start()
	var waited := 0
	while terrain.get_snow_level() <= 0.0 and waited < 400:
		await _frames(1)
		waited += 1
	var early: float = terrain.get_snow_level()
	assert_gt(early, 0.0, "snow cover starts accumulating when a storm starts")
	await _frames(30)
	assert_gt(terrain.get_snow_level(), early, "snow cover keeps accumulating during the storm")
	WeatherManager.force_snowstorm_end()
	var peak: float = terrain.get_snow_level()
	waited = 0
	while terrain.get_snow_level() >= peak and waited < 400:
		await _frames(1)
		waited += 1
	assert_lt(terrain.get_snow_level(), peak, "snow cover melts after the storm ends")


func test_underground_view_builds_ore_crystal_multimeshes() -> void:
	await _frames(30)
	var terrain := _terrain()
	terrain.set_underground_view(true)
	await _frames(30)
	var detail: Node = terrain.get_node("TerrainDetail")
	assert_not_null(detail, "Terrain3D hosts a TerrainDetail3D child")
	var instances := 0
	for holder in detail.get_children():
		for deco in holder.get_children():
			if deco is MultiMeshInstance3D:
				instances += deco.multimesh.instance_count
	assert_gt(instances, 0, "visible ore cells grow crystal instances underground")
	terrain.set_underground_view(false)
	await _frames(5)


func test_lava_glow_pass_pulses_its_shared_emissive_material() -> void:
	await _frames(10)
	var terrain := _terrain()
	var glow_mat: StandardMaterial3D = null
	for chunk in terrain.get_children():
		if chunk is MeshInstance3D and chunk.material_override != null and (chunk.material_override as StandardMaterial3D).emission_enabled:
			glow_mat = chunk.material_override
			break
	assert_not_null(glow_mat, "glow chunks carry the shared emissive lava material")
	if glow_mat == null:
		return
	var first := glow_mat.emission_energy_multiplier
	var waited := 0
	while glow_mat.emission_energy_multiplier == first and waited < 200:
		await _frames(1)
		waited += 1
	assert_ne(glow_mat.emission_energy_multiplier, first,
		"the shared lava material's emission energy pulses over time")
