extends GutTest

# Phase 2 art pass (roadmap/3d-conversion/phase-2-art-pass.md §2.5):
# Effects3D builds quality-aware GPUParticles3D pools under World3D and wires
# them to grid/weather/view state — underground dust motes, storm snow drift,
# cave-in dust bursts, volcano embers — reading sim state only.

var _shell: Node
var _main: Node


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	# No random weather/lava/cave-in rolls mid-test; forced triggers only.
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
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


func _effects() -> Effects3D:
	return _shell.get_node("World3D/Effects3D") as Effects3D


func _grid() -> GridWorld:
	return _main.get_node("World/GridWorld") as GridWorld


func test_effects_node_builds_emitter_pool() -> void:
	await _frames(30)
	var effects := _effects()
	assert_not_null(effects, "World3D hosts an Effects3D node")
	if effects == null:
		return
	var particles := 0
	for c in effects.get_children():
		if c is GPUParticles3D:
			particles += 1
	assert_gt(particles, 0, "Effects3D builds GPUParticles3D emitters")
	assert_not_null(effects.get_node_or_null("DustMotes"), "dust motes emitter exists")
	assert_not_null(effects.get_node_or_null("StormSnow"), "storm snow emitter exists")
	assert_not_null(effects.get_node_or_null("VolcanoEmbers"), "volcano embers emitter exists")
	assert_not_null(effects.get_node_or_null("CaveInBurst0"), "cave-in burst pool exists")


func test_storm_snow_tracks_weather_state() -> void:
	await _frames(10)
	var storm: GPUParticles3D = _effects().get_node("StormSnow")
	assert_false(storm.emitting, "no storm snow before a snowstorm")
	WeatherManager.force_snowstorm_start()
	await _frames(3)
	assert_true(storm.emitting, "storm snow emits while a snowstorm is active")
	assert_eq(storm.amount, int(Effects3D.STORM_SNOW_BASE_AMOUNT * ArtStyle3D.particle_mult()),
		"storm count scales with ArtStyle3D.particle_mult()")
	WeatherManager.force_snowstorm_end()
	await _frames(3)
	assert_false(storm.emitting, "storm snow stops when the snowstorm ends")


func test_cave_in_spawns_dust_burst_at_grid_position() -> void:
	await _frames(10)
	var center := Vector2i(-20, 10)
	_grid().force_cave_in(center)
	await _frames(2)
	var active: GPUParticles3D = null
	for i in range(Effects3D.BURST_POOL_SIZE):
		var b: GPUParticles3D = _effects().get_node("CaveInBurst%d" % i)
		if b.emitting:
			active = b
			break
	assert_not_null(active, "a cave-in burst emitter fires on cave_in_occurred")
	if active != null:
		var expected: Vector2 = _grid().grid_to_world(center) * Effects3D.WORLD_SCALE
		assert_almost_eq(active.position.x, expected.x, 0.001,
			"burst sits at the cave-in's world x")
		assert_almost_eq(active.position.z, expected.y, 0.001,
			"burst sits at the cave-in's world z")
	# Let the rock restore so nothing downstream sees collapsed terrain.
	_grid()._events._cavein_restore_left = 0.0


func test_underground_view_enables_dust_motes() -> void:
	await _frames(10)
	var effects := _effects()
	var motes: GPUParticles3D = effects.get_node("DustMotes")
	assert_false(motes.emitting, "motes idle in the surface view")
	effects.set_underground_view(true)
	await _frames(3)
	assert_true(motes.emitting, "motes drift while the underground view is active")
	effects.set_underground_view(false)
	await _frames(3)
	assert_false(motes.emitting, "motes stop when back on the surface")
