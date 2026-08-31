extends GutTest

# SettingsManager: SFX volume clamping, bus application, and persistence.


func after_all() -> void:
	SettingsManager.set_sfx_volume(1.0)  # Restore the default in settings.cfg.


func test_set_sfx_volume_applies_to_bus() -> void:
	SettingsManager.set_sfx_volume(0.5)
	var bus: int = AudioServer.get_bus_index("SFX")
	assert_ne(bus, -1, "SFX bus exists")
	assert_almost_eq(AudioServer.get_bus_volume_db(bus), linear_to_db(0.5), 0.01)
	assert_false(AudioServer.is_bus_mute(bus))


func test_zero_volume_mutes_bus() -> void:
	SettingsManager.set_sfx_volume(0.0)
	var bus: int = AudioServer.get_bus_index("SFX")
	assert_true(AudioServer.is_bus_mute(bus))


func test_volume_is_clamped() -> void:
	SettingsManager.set_sfx_volume(2.0)
	assert_eq(SettingsManager.get_sfx_volume(), 1.0)
	SettingsManager.set_sfx_volume(-1.0)
	assert_eq(SettingsManager.get_sfx_volume(), 0.0)


func test_volume_persists_to_config() -> void:
	SettingsManager.set_sfx_volume(0.3)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(SettingsManager.CONFIG_PATH), OK)
	assert_almost_eq(cfg.get_value("audio", "sfx_volume", -1.0), 0.3, 0.001)
