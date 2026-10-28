extends GutTest

# Phase 2 art pass (roadmap/3d-conversion/phase-2-art-pass.md §2.5):
# Effects3D builds quality-aware GPUParticles3D pools under World3D and wires
# them to grid/weather/view state — underground dust motes, storm snow drift,
# cave-in dust bursts, volcano embers — reading sim state only.
#
# 3D rework Phase 5 (roadmap/3d-rework/phase-5-effects-and-telegraphs--k3.md):
# EventProxies3D mirrors the sim's meteors/burning patches and event-zone
# warnings into 3D (reconcile pattern, sim burn state is the only source of
# truth), the eruption warning drives a sun pulse + ember ramp + rig rumble,
# and explicit attack orders flash pooled telegraph arcs (Telegraph3D).

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


func test_weather_emitters_cover_camera_local_depth_volumes() -> void:
	await _frames(10)
	var effects := _effects()
	var camera: Camera3D = _shell.get_node("CameraRig/Camera3D")
	for emitter_name in [Effects3D.STORM_NAME, Effects3D.EMBERS_NAME, Effects3D.ASH_NAME, Effects3D.METEOR_SHOWER_NAME]:
		var p: GPUParticles3D = effects.get_node(str(emitter_name))
		assert_true(p.local_coords, "%s moves with the camera" % emitter_name)
		var mat := (p.draw_pass_1 as QuadMesh).material as StandardMaterial3D
		assert_true(mat.disable_fog, "%s stays visible inside weather fog" % emitter_name)
		var pm := p.process_material as ParticleProcessMaterial
		assert_gt(pm.emission_box_extents.z, 10.0, "%s spans near-to-far depth" % emitter_name)
		var center := Effects3D.STORM_VOLUME_CENTER if emitter_name == Effects3D.STORM_NAME else Effects3D.ERUPTION_VOLUME_CENTER
		assert_gt(center.z + pm.emission_box_extents.z, 0.0,
			"%s starts behind the camera, with no visible near-face band" % emitter_name)
	for emitter_name in [Effects3D.STORM_NEAR_NAME, Effects3D.ASH_NEAR_NAME]:
		var p: GPUParticles3D = effects.get_node(str(emitter_name))
		assert_true(p.local_coords, "%s supplies overlapping foreground weather" % emitter_name)
		assert_gt(Effects3D.NEAR_VOLUME_CENTER.z + Effects3D.NEAR_VOLUME_EXTENTS.z, 0.0,
			"foreground volume also starts behind the camera")
	_shell._focus += Vector3(1.0, 0.0, 0.0)
	await _frames(2)
	var expected: Vector3 = camera.to_global(Effects3D.ERUPTION_VOLUME_CENTER)
	assert_almost_eq(effects._ash.global_position.distance_to(expected), 0.0, 0.001,
		"eruption volume tracks the live camera transform")


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


# ─── 3D rework Phase 5: event proxies & telegraphs ───

func _event_proxies() -> EventProxies3D:
	return _shell.get_node("World3D/EventProxies3D") as EventProxies3D


func test_event_proxies_node_exists() -> void:
	assert_not_null(_event_proxies(), "World3D hosts an EventProxies3D node")


func test_meteor_gets_falling_proxy_and_impact_ring() -> void:
	await _frames(10)
	var ep := _event_proxies()
	WeatherManager.force_volcano_start()  # _start_volcano spawns a meteor at once
	var meteor: Meteor = null
	for i in range(60):
		await get_tree().process_frame
		for child in get_tree().current_scene.get_children():
			if child is Meteor:
				meteor = child
				break
		if meteor != null and ep._meteor_proxies.has(meteor.get_instance_id()):
			break
	WeatherManager.force_volcano_end()  # no further meteors; the live one finishes
	assert_not_null(meteor, "forced eruption spawns a meteor")
	if meteor == null:
		return
	assert_true(ep._meteor_proxies.has(meteor.get_instance_id()), "live meteor gets a 3D proxy")
	if not ep._meteor_proxies.has(meteor.get_instance_id()):
		return
	var proxy: Node3D = ep._meteor_proxies[meteor.get_instance_id()]
	if not meteor._impacted:
		assert_true((proxy.get_node("Streak") as MeshInstance3D).visible, "fall phase shows the streak")
		assert_gt(proxy.position.y, 0.5, "the streak drops out of the sky (starts high)")
	# The fall is 0.4s, the impact flash 0.45s — the ring phase must appear.
	var saw_ring := false
	for i in range(240):
		await get_tree().process_frame
		for id in ep._meteor_proxies:
			if (ep._meteor_proxies[id].get_node("ImpactRing") as MeshInstance3D).visible:
				saw_ring = true
		if saw_ring or ep._meteor_proxies.is_empty():
			break
	assert_true(saw_ring, "impact phase projects an expanding ring")
	# After the flash the sim frees the meteor and the proxy recycles.
	var gone := false
	for i in range(240):
		await get_tree().process_frame
		if ep._meteor_proxies.is_empty():
			gone = true
			break
	assert_true(gone, "proxy returns to the pool once the meteor is freed")


func test_burn_patch_decal_tracks_sim_burn_state() -> void:
	await _frames(10)
	var ep := _event_proxies()
	WeatherManager.force_volcano_start()
	# A meteor impacts within ~1s and (no storm) leaves a burning patch.
	var patch: BurningGround = null
	for i in range(300):
		await get_tree().process_frame
		if patch != null and not is_instance_valid(patch):
			patch = null  # an earlier patch expired mid-search
		if patch == null:
			for node in get_tree().get_nodes_in_group("burning_grounds"):
				if node is BurningGround:
					patch = node
					break
		if patch != null and ep._burn_decals.has(patch.get_instance_id()):
			break
	assert_not_null(patch, "meteor impact leaves a burning patch")
	if patch == null:
		WeatherManager.force_volcano_end()
		return
	var patch_id: int = patch.get_instance_id()
	assert_true(ep._burn_decals.has(patch_id), "burn patch gets a 3D decal")
	var decal: Node3D = ep._burn_decals[patch_id]
	var expected: Vector3 = Presentation3D.to_3d(patch.global_position, 0.0)
	assert_almost_eq(decal.position.x, expected.x, 0.001, "decal sits at the patch's world x")
	assert_almost_eq(decal.position.z, expected.z, 0.001, "decal sits at the patch's world z")
	# A snowstorm extinguishes volcano fires in the sim; the decal must follow
	# the sim state (never tracked separately).
	WeatherManager.force_snowstorm_start()
	await _frames(3)
	assert_false(ep._burn_decals.has(patch_id),
		"storm-extinguished patch loses its decal on the next reconcile")
	WeatherManager.force_snowstorm_end()
	WeatherManager.force_volcano_end()
	await _frames(3)


func test_lava_warning_shimmer_marks_flood_zone() -> void:
	await _frames(10)
	var ep := _event_proxies()
	var grid := _grid()
	grid.set_reveal_all(GameManager.Team.PLAYER, true)  # fog gates the shimmer cells
	grid.force_lava_warning(7)  # deepest rise: flood zone spans every column
	ep.set_underground_view(true)
	await _frames(3)
	assert_true(ep._lava_shimmer.visible, "warning shimmer shows in the underground view")
	assert_gt(ep._lava_shimmer_mesh.instance_count, 0, "shimmer covers the cells that will flood")
	ep.set_underground_view(false)
	await _frames(3)
	assert_false(ep._lava_shimmer.visible, "shimmer is underground-view only")
	# Fast-forward the warning: the rising tide hands off to the terrain glow.
	ep.set_underground_view(true)
	grid._events._lava_warning_left = 0.01
	await _frames(4)
	assert_false(ep._lava_shimmer.visible, "shimmer clears once the lava starts rising")
	grid.force_lava_recede()
	ep.set_underground_view(false)
	grid.set_reveal_all(GameManager.Team.PLAYER, false)
	await _frames(2)


func test_cave_in_warning_zone_marks_target_area() -> void:
	await _frames(10)
	var ep := _event_proxies()
	var grid := _grid()
	grid._events._start_cavein_warning()
	var center: Vector2i = grid._events._cavein_warning_center
	ep.set_underground_view(true)
	await _frames(3)
	assert_true(ep._cavein_zone.visible, "warning zone shows in the underground view")
	var quads := 0
	for child in ep._cavein_zone.get_children():
		if child is MeshInstance3D:
			quads += 1
	assert_eq(quads, 9, "the warning darkens the 3x3 target area")
	var expected: Vector2 = grid.grid_to_world(center) * EventProxies3D.WORLD_SCALE
	assert_almost_eq(ep._cavein_zone.position.x, expected.x, 0.001, "zone sits at the warning x")
	assert_almost_eq(ep._cavein_zone.position.z, expected.y, 0.001, "zone sits at the warning z")
	# Let the drop land; the zone hands off to the Effects3D dust bursts.
	grid._events._cavein_warning_left = 0.01
	await _frames(4)
	assert_false(ep._cavein_zone.visible, "zone hides when the cave-in drops")
	grid._events._cavein_restore_left = 0.0  # restore the collapsed rock
	ep.set_underground_view(false)
	await _frames(2)


func test_attack_telegraph_spawns_under_shell_only() -> void:
	await _frames(5)
	# Tests adopt the sim as current_scene, so without flipping back the spawn
	# must no-op (standalone 2D mode keeps its order markers).
	assert_false(Telegraph3D.spawn_attack(get_tree(), Vector2(-500, 0), Vector2(-300, 0)),
		"no telegraph without the 3D shell")
	get_tree().current_scene = _shell
	var spawned: bool = Telegraph3D.spawn_attack(get_tree(), Vector2(-500, 0), Vector2(-300, 0))
	get_tree().current_scene = _main
	assert_true(spawned, "telegraph spawns when the 3D shell runs the scene")
	var telegraph: Telegraph3D = null
	for child in _shell.get_node("World3D/Effects3D").get_children():
		if child is Telegraph3D:
			telegraph = child
			break
	assert_not_null(telegraph, "telegraph lives under the shell's Effects3D container")
	if telegraph == null:
		return
	assert_eq(telegraph._dashes.size(), Telegraph3D.DASH_COUNT, "the arc is a pooled dashed line")
	var first: Vector3 = telegraph._dashes[0].position
	var last: Vector3 = telegraph._dashes[Telegraph3D.DASH_COUNT - 1].position
	assert_gt(last.x, first.x, "the arc runs from the attacker group toward the target")
	var recycled := false
	for i in range(150):
		await get_tree().process_frame
		if not telegraph.visible:
			recycled = true
			break
	assert_true(recycled, "the telegraph fades out and returns to the pool")


func test_volcano_warning_ramps_embers_and_rumbles() -> void:
	await _frames(10)
	var embers: GPUParticles3D = _effects().get_node("VolcanoEmbers")
	var ash: GPUParticles3D = _effects().get_node("VolcanoAsh")
	assert_false(embers.emitting, "no embers before the warning")
	assert_false(ash.emitting, "no ash before the eruption")
	WeatherManager.force_volcano_warning()
	await _frames(3)
	assert_true(embers.emitting, "embers trickle in during the eruption warning")
	assert_false(ash.emitting, "warning keeps full ashfall back until the eruption")
	assert_lt(embers.amount, int(Effects3D.EMBERS_BASE_AMOUNT * ArtStyle3D.particle_mult()),
		"warning density ramps up from below the full eruption")
	assert_gt(_shell.get("_shake"), 0.0, "the warning rumbles the camera rig")
	WeatherManager.force_volcano_start()
	await _frames(3)
	assert_eq(embers.amount, int(Effects3D.EMBERS_BASE_AMOUNT * ArtStyle3D.particle_mult()),
		"the eruption runs embers at full density")
	assert_true(ash.emitting, "ash falls through the whole view during the eruption")
	assert_eq(ash.amount, int(Effects3D.ASH_BASE_AMOUNT * ArtStyle3D.particle_mult()),
		"ash count scales with the quality preset")
	WeatherManager.force_volcano_end()
	await _frames(3)
	assert_false(embers.emitting, "embers stop when the eruption ends")
	assert_false(ash.emitting, "ash stops when the eruption ends")


func test_volcano_warning_pulses_the_sun() -> void:
	await _frames(10)
	var lighting: Lighting3D = _shell.get_node("World3D/Lighting3D")
	var base: Dictionary = Lighting3D._MOODS["volcano"]
	# The pulse modulates the tween TARGET; drive the beat to its peak
	# directly so the check is independent of headless frame pacing.
	WeatherManager.force_volcano_warning()
	lighting._warning_pulse_time = Lighting3D.WARNING_PULSE_PERIOD * 0.25
	var pulsed: Dictionary = lighting._apply_warning_pulse(base, 0.0)
	assert_gt(float(pulsed["sun_energy"]), float(base["sun_energy"]) * 1.3,
		"a beat peak overdrives the sun above the plain volcano mood")
	assert_gt((pulsed["sun_color"] as Color).r / maxf((pulsed["sun_color"] as Color).b, 0.001),
		(base["sun_color"] as Color).r / maxf((base["sun_color"] as Color).b, 0.001),
		"a beat peak reddens the sun toward the eruption cast")
	WeatherManager.force_volcano_start()  # warning over -> pulse gates off
	var unpulsed: Dictionary = lighting._apply_warning_pulse(base, 0.0)
	assert_eq(float(unpulsed["sun_energy"]), float(base["sun_energy"]),
		"the pulse only runs during the warning window")
	WeatherManager.force_volcano_end()
