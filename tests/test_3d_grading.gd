extends GutTest

# Per-mood color grading (Environment adjustments): each lighting mood
# carries a saturation/contrast/brightness target that Lighting3D tweens the
# WorldEnvironment toward, gated Standard+ like bloom. Storms bleach,
# underground crushes, eruptions push a hot grade; overcast stays neutral.

var _shell: Node
var _main: Node
var _lighting: Lighting3D
var _env: Environment


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	WeatherManager.reset()
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)
	# The sim mounts deferred; adopt it as current_scene (test_3d_port pattern).
	for i in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	get_tree().current_scene = _main
	_lighting = _shell.get_node("World3D/Lighting3D")
	_env = _shell.get_node("World3D/Lights/WorldEnvironment").environment
	await _frames(10)


func before_each() -> void:
	WeatherManager.reset()
	WeatherManager.set_weather_events_enabled(false)
	WeatherManager.set_volcano_events_enabled(false)


func after_all() -> void:
	WeatherManager.reset()
	WeatherManager.set_weather_events_enabled(true)
	WeatherManager.set_volcano_events_enabled(true)
	_shell.free()
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
	GameManager.clear_map_seed()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func test_adjustments_gate_matches_bloom_tiers() -> void:
	var detected: int = ArtStyle3D.auto_detect_quality()
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.POTATO)
	assert_false(ArtStyle3D.adjustments_enabled(), "Potato skips the grading pass")
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.STANDARD)
	assert_true(ArtStyle3D.adjustments_enabled(), "Standard grades")
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.FANCY)
	assert_true(ArtStyle3D.adjustments_enabled(), "Fancy grades")
	ArtStyle3D.apply_quality(detected)


func test_quality_apply_resets_grade_to_neutral() -> void:
	_env.adjustment_saturation = 0.5
	_lighting.apply_quality_settings()
	if ArtStyle3D.adjustments_enabled():
		assert_true(_env.adjustment_enabled, "grading pass enabled on Standard+")
		assert_eq(_env.adjustment_saturation, 1.0, "saturation reset to neutral")
		assert_eq(_env.adjustment_contrast, 1.0, "contrast reset to neutral")
		assert_eq(_env.adjustment_brightness, 1.0, "brightness reset to neutral")
	else:
		assert_false(_env.adjustment_enabled, "Potato keeps the grading pass off")


func test_mood_targets_carry_grades() -> void:
	# Target-level assertions (no tween waiting): the resolved mood must carry
	# the table's grade through to the tween input.
	_lighting.set_underground_view(false)
	var overcast: Dictionary = _lighting._resolve_mood(0.016, false)
	assert_eq(overcast["grade_sat"], 1.0, "overcast stays neutral")
	_lighting.set_underground_view(true)
	var underground: Dictionary = _lighting._resolve_mood(0.016, false)
	assert_true(float(underground["grade_sat"]) < 1.0,
		"underground desaturates")
	assert_true(float(underground["grade_con"]) > 1.0,
		"underground hardens contrast")
	_lighting.set_underground_view(false)


func test_storm_grade_reaches_the_environment() -> void:
	if not ArtStyle3D.adjustments_enabled():
		pass_test("Potato preset: grading gated off, nothing to assert")
		return
	WeatherManager.force_snowstorm_start()
	var desaturated := false
	for i in range(200):
		await get_tree().process_frame
		if _lighting.get_mood_name() == "storm" and _env.adjustment_saturation < 0.9:
			desaturated = true
			break
	assert_true(desaturated, "storm bleaches the frame (saturation drops)")
	WeatherManager.force_snowstorm_end()
	var restored := false
	for i in range(200):
		await get_tree().process_frame
		if absf(_env.adjustment_saturation - 1.0) < 0.05:
			restored = true
			break
	assert_true(restored, "ending the storm restores the neutral grade")
