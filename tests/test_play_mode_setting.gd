extends GutTest

# Play-mode setting: the default is "3d", a round-trip persists to
# settings.cfg, an invalid stored value reads back "3d", and the main menu's
# Play target (and its Mode dropdown, plus the settings panel's Display row)
# follow the setting. settings.cfg is written for real — the prior value is
# restored in after_all.

const MainMenuScene := preload("res://scenes/ui/main_menu.tscn")

var _prior: String


func before_all() -> void:
	_prior = SettingsManager.get_play_mode()


func after_all() -> void:
	SettingsManager.set_play_mode(_prior)


# ─── Setting storage ───

func test_default_is_3d_when_nothing_stored() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SettingsManager.CONFIG_PATH)
	var had := cfg.has_section_key("video", "play_mode")
	if had:
		var prior: Variant = cfg.get_value("video", "play_mode", "")
		cfg.erase_section_key("video", "play_mode")
		cfg.save(SettingsManager.CONFIG_PATH)
		assert_eq(SettingsManager.get_play_mode(), "3d", "no stored value reads the default")
		cfg.set_value("video", "play_mode", prior)
		cfg.save(SettingsManager.CONFIG_PATH)
	else:
		assert_eq(SettingsManager.get_play_mode(), "3d", "no stored value reads the default")


func test_invalid_stored_value_falls_back_to_3d() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SettingsManager.CONFIG_PATH)
	cfg.set_value("video", "play_mode", "vr")
	cfg.save(SettingsManager.CONFIG_PATH)
	assert_eq(SettingsManager.get_play_mode(), "3d")


func test_set_normalizes_invalid_value() -> void:
	SettingsManager.set_play_mode("hologram")
	assert_eq(SettingsManager.get_play_mode(), "3d")


func test_round_trip_persists() -> void:
	SettingsManager.set_play_mode("2d")
	assert_eq(SettingsManager.get_play_mode(), "2d")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(SettingsManager.CONFIG_PATH), OK)
	assert_eq(str(cfg.get_value("video", "play_mode", "")), "2d", "persisted to settings.cfg")
	SettingsManager.set_play_mode("3d")
	assert_eq(SettingsManager.get_play_mode(), "3d")


# ─── Main menu ───

func test_play_targets_3d_shell_by_default() -> void:
	SettingsManager.set_play_mode("3d")
	var menu: Control = MainMenuScene.instantiate()
	add_child_autofree(menu)
	assert_eq(menu._play_scene_path(), "res://scenes/main_3d.tscn",
		"_on_play change_scene target for the default mode")


func test_play_targets_2d_legacy_when_set() -> void:
	SettingsManager.set_play_mode("2d")
	var menu: Control = MainMenuScene.instantiate()
	add_child_autofree(menu)
	assert_eq(menu._play_scene_path(), "res://scenes/main.tscn",
		"_on_play change_scene target for the legacy mode")


func test_menu_mode_dropdown_initializes_from_setting() -> void:
	SettingsManager.set_play_mode("2d")
	var menu: Control = MainMenuScene.instantiate()
	add_child_autofree(menu)
	var option := _find_mode_option(menu)
	assert_not_null(option, "main menu has a Mode dropdown")
	assert_eq(option.selected, 1, "dropdown shows 2D legacy")


func test_menu_mode_dropdown_select_persists() -> void:
	SettingsManager.set_play_mode("3d")
	var menu: Control = MainMenuScene.instantiate()
	add_child_autofree(menu)
	var option := _find_mode_option(menu)
	option.item_selected.emit(1)
	assert_eq(SettingsManager.get_play_mode(), "2d", "selecting 2D legacy persists")
	option.item_selected.emit(0)
	assert_eq(SettingsManager.get_play_mode(), "3d", "selecting 3D persists")


# ─── Settings panel ───

func test_settings_panel_mode_row_updates_setting() -> void:
	SettingsManager.set_play_mode("3d")
	var panel: Control = SettingsPanel.create()
	add_child_autofree(panel)
	var option := _find_mode_option(panel)
	assert_not_null(option, "settings panel has a Mode dropdown")
	assert_eq(option.selected, 0, "panel dropdown shows 3D")
	option.item_selected.emit(1)
	assert_eq(SettingsManager.get_play_mode(), "2d", "panel flip persists")


func test_settings_panel_labels_next_play() -> void:
	var panel: Control = SettingsPanel.create()
	add_child_autofree(panel)
	var labels: Array = []
	_collect_labels(panel, labels)
	var found := false
	for label: Label in labels:
		if label.text == "next Play":
			found = true
	assert_true(found, "settings panel should label the Mode row as taking effect next Play")


# ─── Finders ───

## Both the main menu and the settings panel use the same Mode dropdown items.
func _find_mode_option(root: Node) -> OptionButton:
	var found: Array = []
	_collect_options(root, found)
	for opt: OptionButton in found:
		if opt.item_count == 2 and opt.get_item_text(0) == "3D (recommended)":
			return opt
	return null


func _collect_options(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is OptionButton:
			out.append(child)
		_collect_options(child, out)


func _collect_labels(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Label:
			out.append(child)
		_collect_labels(child, out)
