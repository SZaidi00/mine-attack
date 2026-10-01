extends GutTest

# Dynamic music: a synthesized combat percussion layer fades with a 0..1 combat
# intensity that combat pulses raise and that decays over ~4.5s; snowstorms
# duck the drums and the cave drips, and a volcano eruption ducks the drips so
# the rumble owns the low end.

const DECAY: float = 4.5


func before_each() -> void:
	WeatherManager.force_snowstorm_end()
	WeatherManager.force_volcano_end()
	AudioManager.combat_pulse(0.0)
	AudioManager._combat_intensity = 0.0


func after_all() -> void:
	WeatherManager.force_snowstorm_end()
	WeatherManager.force_volcano_end()
	AudioManager._combat_intensity = 0.0


func test_combat_pulse_raises_intensity() -> void:
	AudioManager.combat_pulse(0.7)
	assert_almost_eq(AudioManager.get_combat_intensity(), 0.7, 0.001)
	AudioManager.combat_pulse(0.4)
	assert_almost_eq(AudioManager.get_combat_intensity(), 0.7, 0.001,
		"a weaker pulse does not lower the intensity")
	AudioManager.combat_pulse(1.2)
	assert_almost_eq(AudioManager.get_combat_intensity(), 1.0, 0.001, "clamped to 1")


func test_intensity_decays_over_time() -> void:
	AudioManager.combat_pulse(1.0)
	AudioManager._process(1.0)
	assert_almost_eq(AudioManager.get_combat_intensity(), 1.0 - 1.0 / DECAY, 0.01,
		"one second decays one DECAY-th")
	for i in range(10):
		AudioManager._process(1.0)
	assert_almost_eq(AudioManager.get_combat_intensity(), 0.0, 0.001, "decays to zero")


func test_drum_volume_follows_intensity() -> void:
	var quiet: float = AudioManager.get_combat_drum_target_db()
	AudioManager.combat_pulse(1.0)
	var loud: float = AudioManager.get_combat_drum_target_db()
	assert_gt(loud, quiet, "full intensity targets a louder drum layer")


func test_snowstorm_ducks_drums_and_drips() -> void:
	AudioManager.combat_pulse(1.0)
	var drums_clear: float = AudioManager.get_combat_drum_target_db()
	var drips_clear: float = AudioManager.get_drips_target_db()
	WeatherManager.force_snowstorm_start()
	assert_lt(AudioManager.get_combat_drum_target_db(), drums_clear, "storm thins the drums")
	assert_lt(AudioManager.get_drips_target_db(), drips_clear, "storm thins the drips")
	WeatherManager.force_snowstorm_end()
	assert_almost_eq(AudioManager.get_combat_drum_target_db(), drums_clear, 0.001,
		"drums return when the storm passes")
	assert_almost_eq(AudioManager.get_drips_target_db(), drips_clear, 0.001,
		"drips return when the storm passes")


func test_volcano_ducks_drips_but_not_drums() -> void:
	AudioManager.combat_pulse(1.0)
	var drums_clear: float = AudioManager.get_combat_drum_target_db()
	var drips_clear: float = AudioManager.get_drips_target_db()
	WeatherManager.force_volcano_start()
	assert_lt(AudioManager.get_drips_target_db(), drips_clear, "eruption thins the drips")
	assert_almost_eq(AudioManager.get_combat_drum_target_db(), drums_clear, 0.001,
		"the drums do not fight the rumble layer-wise (drips duck instead)")
	WeatherManager.force_volcano_end()
	assert_almost_eq(AudioManager.get_drips_target_db(), drips_clear, 0.001,
		"drips return when the eruption ends")


func test_layer_volumes_ease_toward_targets() -> void:
	# The drums player exists and moves toward the target as _process runs.
	assert_not_null(AudioManager._drums_player, "combat drum layer is playing")
	for i in range(30):
		AudioManager.combat_pulse(1.0)  # pin intensity: the target itself decays
		AudioManager._process(0.1)
	var target: float = AudioManager.get_combat_drum_target_db()
	assert_almost_eq(AudioManager._drums_player.volume_db, target, 1.0,
		"the drum layer eases to its target volume")
