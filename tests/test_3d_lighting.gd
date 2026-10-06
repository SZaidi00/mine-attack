extends GutTest

# Phase 2 art pass (roadmap/3d-conversion/phase-2-art-pass.md):
# §2.4 weather-reactive lighting moods, §2.5 camera shake juice (reduced-motion
# aware), §2.6 the 3D audio listener, §2.7 quality presets flipping the
# shadows gate in ArtStyle3D.

var _shell: Node
var _main: Node
var _lighting: Lighting3D
var _sun: DirectionalLight3D
var _prev_reduced_motion: bool


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	_prev_reduced_motion = SettingsManager.get_reduced_motion()
	WeatherManager.reset()
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)
	# The sim mounts deferred; adopt it as current_scene like test_3d_port.
	for i in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	get_tree().current_scene = _main
	_lighting = _shell.get_node("World3D/Lighting3D")
	_sun = _shell.get_node("World3D/Lights/DirectionalLight3D")
	await _frames(10)


func before_each() -> void:
	# Clean weather state between mood tests (a lingering volcano would win
	# the mood priority over a forced storm).
	WeatherManager.reset()
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)


func after_all() -> void:
	WeatherManager.reset()
	WeatherManager.set_weather_events_enabled(true)
	WeatherManager.set_volcano_events_enabled(true)
	SettingsManager.set_reduced_motion(_prev_reduced_motion)
	# Free immediately (not queue_free): see test_3d_port.after_all.
	_shell.free()
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
	GameManager.clear_map_seed()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## The lighting tweens run at ~2/s, so a mood change needs a moment to land;
## wait for the overcast steady state before sampling a baseline (a previous
## test may have left the sun mid-tween).
func _settle_overcast(max_frames: int = 150) -> void:
	for i in range(max_frames):
		await get_tree().process_frame
		if _lighting.get_mood_name() == "overcast" and absf(_sun.light_energy - 1.1) < 0.05:
			return


# ─── §2.6 audio listener ───

func test_audio_listener_3d_exists_and_is_current() -> void:
	var listener: AudioListener3D = _shell.get_node_or_null("CameraRig/AudioListener3D")
	assert_not_null(listener, "shell parents an AudioListener3D under CameraRig")
	if listener == null:
		return
	assert_true(listener.is_current(), "the 3D listener is the current one")


# ─── §2.4 weather-reactive moods ───

func test_volcano_eruption_reddens_sun_and_back() -> void:
	await _settle_overcast()
	var base_energy: float = _sun.light_energy
	WeatherManager.force_volcano_start()
	var shifted := false
	for i in range(120):  # ~2s of frames: tweens run at ~2/s.
		await get_tree().process_frame
		if _lighting.get_mood_name() == "volcano" \
				and _sun.light_energy > base_energy + 0.2 \
				and _sun.light_color.r > _sun.light_color.b:
			shifted = true
			break
	assert_true(shifted, "volcano mood reddens + brightens the sun within ~1s")
	WeatherManager.force_volcano_end()
	var restored := false
	for i in range(120):
		await get_tree().process_frame
		if _lighting.get_mood_name() == "overcast" and absf(_sun.light_energy - base_energy) < 0.1:
			restored = true
			break
	assert_true(restored, "ending the eruption tweens back to the overcast base")


func test_snowstorm_flattens_sun_and_back() -> void:
	await _settle_overcast()
	var base_energy: float = _sun.light_energy
	WeatherManager.force_snowstorm_start()
	var shifted := false
	for i in range(120):
		await get_tree().process_frame
		if _lighting.get_mood_name() == "storm" and _sun.light_energy < base_energy - 0.2:
			shifted = true
			break
	assert_true(shifted, "storm mood dims the sun within ~1s")
	WeatherManager.force_snowstorm_end()
	var restored := false
	for i in range(120):
		await get_tree().process_frame
		if _lighting.get_mood_name() == "overcast" and absf(_sun.light_energy - base_energy) < 0.1:
			restored = true
			break
	assert_true(restored, "ending the storm tweens back to the overcast base")


func test_underground_view_darkens_mine_and_back() -> void:
	await _settle_overcast()
	var base_energy: float = _sun.light_energy
	# Equivalent of the Tab view switch (test_3d_port drives the terrain
	# directly; here the lighting hook is the contract under test).
	_lighting.set_underground_view(true)
	var darkened := false
	for i in range(120):
		await get_tree().process_frame
		if _lighting.get_mood_name() == "underground" and _sun.light_energy < base_energy * 0.6:
			darkened = true
			break
	assert_true(darkened, "underground mood drops the sun well below the surface base")
	_lighting.set_underground_view(false)
	await _settle_overcast(60)
	assert_eq(_lighting.get_mood_name(), "overcast", "surface view restores the base mood")


# ─── §2.5 camera shake juice ───

func test_camera_shake_respects_reduced_motion() -> void:
	var rig: Node3D = _shell.get_node("CameraRig")
	await _frames(5)
	var still: Vector3 = rig.position
	SettingsManager.set_reduced_motion(true)
	_shell.add_shake(1.0)
	await _frames(5)
	assert_eq(rig.position, still, "reduced motion: add_shake leaves the rig parked on the focus")
	SettingsManager.set_reduced_motion(false)
	_shell.add_shake(1.0)
	var shaken := false
	for i in range(10):
		await get_tree().process_frame
		if rig.position != still:
			shaken = true
			break
	assert_true(shaken, "with motion allowed, the rumble offsets the rig off the focus")
	await _frames(60)  # Let the shake decay so later tests start parked.


# ─── §2.7 quality presets ───

func test_quality_presets_flip_shadow_gate() -> void:
	var detected: int = ArtStyle3D.auto_detect_quality()
	ArtStyle3D.apply_quality(detected)
	assert_eq(ArtStyle3D.shadows_enabled(), detected == ArtStyle3D.Quality.FANCY,
		"apply_quality(auto_detect_quality()) sets the shadows gate")
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.POTATO)
	assert_false(ArtStyle3D.shadows_enabled(), "Potato disables shadows")
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.FANCY)
	assert_true(ArtStyle3D.shadows_enabled(), "Fancy enables shadows")
	ArtStyle3D.apply_quality(detected)  # Restore the shell's startup preset.
