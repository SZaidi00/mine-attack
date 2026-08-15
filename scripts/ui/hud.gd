extends CanvasLayer
class_name HUD

const _Constants = preload("res://scripts/autoload/constants.gd")

const HUDStyling = preload("res://scripts/ui/hud_styling.gd")
const HUDMenus = preload("res://scripts/ui/hud_menus.gd")
const HUDUpdates = preload("res://scripts/ui/hud_updates.gd")

const _ICON_COIN: Texture2D = preload("res://frost_mines_assets/icons/icon_coin.png")
const _ICON_MINER: Texture2D = preload("res://frost_mines_assets/icons/icon_miner.png")
const _ICON_SWORDSMAN: Texture2D = preload("res://frost_mines_assets/icons/icon_swordsman.png")
const _ICON_ARCHER: Texture2D = preload("res://frost_mines_assets/icons/icon_archer.png")
const _ICON_WIZARD: Texture2D = preload("res://frost_mines_assets/icons/icon_wizard.png")
const _ICON_DRAGON: Texture2D = preload("res://frost_mines_assets/icons/icon_dragon.png")
const _ICON_HP: Texture2D = preload("res://frost_mines_assets/icons/icon_hp.png")
const _ICON_ATTACK: Texture2D = preload("res://frost_mines_assets/icons/icon_attack.png")
const _ICON_LAVA: Texture2D = preload("res://frost_mines_assets/icons/icon_lava.png")
const _ICON_SNOWSTORM: Texture2D = preload("res://frost_mines_assets/icons/icon_snowstorm.png")

@onready var _coin_label: Label = $TopBar/MarginContainer/VBoxContainer/StatsRow/LeftGroup/CoinLabel
@onready var _miner_level_label: Label = $TopBar/MarginContainer/VBoxContainer/StatsRow/LeftGroup/MinerLevelLabel
@onready var _unit_count_label: Label = $TopBar/MarginContainer/VBoxContainer/StatsRow/CenterGroup/UnitCountLabel
@onready var _unit_count_labels: Dictionary = {
	"Miner": $TopBar/MarginContainer/VBoxContainer/StatsRow/CenterGroup/UnitBreakdown/MinerCountLabel,
	"Swordsman": $TopBar/MarginContainer/VBoxContainer/StatsRow/CenterGroup/UnitBreakdown/SwordsmanCountLabel,
	"Archer": $TopBar/MarginContainer/VBoxContainer/StatsRow/CenterGroup/UnitBreakdown/ArcherCountLabel,
	"Wizard": $TopBar/MarginContainer/VBoxContainer/StatsRow/CenterGroup/UnitBreakdown/WizardCountLabel,
	"Dragon": $TopBar/MarginContainer/VBoxContainer/StatsRow/CenterGroup/UnitBreakdown/DragonCountLabel,
	"Pigeon": $TopBar/MarginContainer/VBoxContainer/StatsRow/CenterGroup/UnitBreakdown/PigeonCountLabel,
}
@onready var _player_hp_label: Label = $TopBar/MarginContainer/VBoxContainer/StatsRow/RightGroup/PlayerHPLabel
@onready var _enemy_hp_label: Label = $TopBar/MarginContainer/VBoxContainer/StatsRow/RightGroup/EnemyHPLabel
@onready var _selection_label: Label = %SelectionLabel
@onready var _surface_button: Button = $TopBar/MarginContainer/VBoxContainer/TabsRow/TabGroup/SurfaceButton
@onready var _underground_button: Button = $TopBar/MarginContainer/VBoxContainer/TabsRow/TabGroup/UndergroundButton
@onready var _pause_button: Button = $TopBar/MarginContainer/VBoxContainer/TabsRow/SpeedGroup/PauseButton
@onready var _speed_buttons: Dictionary = {
	1.0: $TopBar/MarginContainer/VBoxContainer/TabsRow/SpeedGroup/Speed1Button,
	2.0: $TopBar/MarginContainer/VBoxContainer/TabsRow/SpeedGroup/Speed2Button,
	3.0: $TopBar/MarginContainer/VBoxContainer/TabsRow/SpeedGroup/Speed3Button,
	5.0: $TopBar/MarginContainer/VBoxContainer/TabsRow/SpeedGroup/Speed5Button,
	10.0: $TopBar/MarginContainer/VBoxContainer/TabsRow/SpeedGroup/Speed10Button,
}
@onready var _upgrade_button: Button = $BottomBar/MarginContainer/HBoxContainer/UpgradeMinerButton
@onready var _fighter_upgrade_buttons: Dictionary = {
	"swordsman": $BottomBar/MarginContainer/HBoxContainer/UpgradeSwordsmanButton,
	"archer": $BottomBar/MarginContainer/HBoxContainer/UpgradeArcherButton,
	"wizard": $BottomBar/MarginContainer/HBoxContainer/UpgradeWizardButton,
	"dragon": $BottomBar/MarginContainer/HBoxContainer/UpgradeDragonButton,
}
@onready var _attack_button: Button = $BottomBar/MarginContainer/HBoxContainer/AttackButton
@onready var _defend_button: Button = $BottomBar/MarginContainer/HBoxContainer/DefendButton
@onready var _garrison_button: Button = $BottomBar/MarginContainer/HBoxContainer/GarrisonButton
@onready var _rally_button: Button = $BottomBar/MarginContainer/HBoxContainer/RallyButton
@onready var _kill_button: Button = $BottomBar/MarginContainer/HBoxContainer/KillButton
@onready var _research_button: Button = $BottomBar/MarginContainer/HBoxContainer/ResearchButton
@onready var _build_button: Button = $BottomBar/MarginContainer/HBoxContainer/BuildButton
@onready var _research_panel: Control = $ResearchPanel
@onready var _player_faction_icon: TextureRect = $TopBar/MarginContainer/VBoxContainer/StatsRow/LeftGroup/PlayerFactionIcon
@onready var _enemy_faction_icon: TextureRect = $TopBar/MarginContainer/VBoxContainer/StatsRow/RightGroup/EnemyFactionIcon
@onready var _enemy_faction_label: Label = $TopBar/MarginContainer/VBoxContainer/StatsRow/RightGroup/EnemyFactionLabel
@onready var _stance_buttons: Dictionary = {}
@onready var _game_over_panel: PanelContainer = $GameOverPanel

var _styling: HUDStyling
var _menus: HUDMenus
var _updates: HUDUpdates


func _init() -> void:
	_styling = HUDStyling.new(self)
	_menus = HUDMenus.new(self)
	_updates = HUDUpdates.new(self)


func _ready() -> void:
	# The HUD must keep processing while the tree is paused so the pause menu
	# stays visible and clickable (the classic pause-menu-pauses-itself bug).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# A fresh Main scene means a fresh match: GameManager.match_time has been
	# accumulating since boot (through the menu), so the weather schedule must
	# restart here rather than trust any clock that survived the menu.
	WeatherManager.reset()
	# Same for the AI's intel: beliefs reference the previous match's units.
	AIBeliefSystem.reset()
	_styling._ignore_mouse_recursive($TopBar)
	_styling._ignore_mouse_recursive($BottomBar)
	_styling._ignore_mouse_recursive(_game_over_panel)
	# QueuePanel keeps default mouse handling: its ScrollContainer needs wheel
	# input and its runtime cancel buttons need clicks.
	_styling._style_panel($TopBar)
	_styling._style_panel($BottomBar)
	_styling._style_panel($QueuePanel)
	_styling._style_panel(_game_over_panel)
	_styling._style_tab_buttons()
	_styling._style_speed_buttons()
	_styling._style_upgrade_button()
	_styling._style_fighter_upgrade_buttons()
	_styling._style_stance_buttons()
	_stance_buttons = {
		"attack": _attack_button,
		"defend": _defend_button,
		"garrison": _garrison_button,
	}
	_add_stat_icons()
	_add_unit_breakdown_icons()
	_add_attack_button_icon()

	_upgrade_button.pressed.connect(_upgrade_miner)
	for unit_id: String in _fighter_upgrade_buttons:
		_fighter_upgrade_buttons[unit_id].pressed.connect(_upgrade_fighter.bind(unit_id))
	_attack_button.pressed.connect(_stance.bind("attack"))
	_defend_button.pressed.connect(_stance.bind("defend"))
	_garrison_button.pressed.connect(_stance.bind("garrison"))
	_rally_button.pressed.connect(_stance.bind("rally"))
	_kill_button.pressed.connect(_kill_selected)
	_research_button.pressed.connect(toggle_research_panel)
	_build_button.pressed.connect(_menus._toggle_build_menu)
	_surface_button.pressed.connect(_set_view.bind(false))
	_underground_button.pressed.connect(_set_view.bind(true))
	_pause_button.pressed.connect(_toggle_soft_pause)
	for speed: float in _speed_buttons:
		_speed_buttons[speed].pressed.connect(_set_game_speed.bind(speed))
	$GameOverPanel/MarginContainer/VBoxContainer/QuitButton.pressed.connect(_quit_to_menu)
	$GameOverPanel/MarginContainer/VBoxContainer/PlayAgainButton.pressed.connect(_play_again)
	for btn: Button in [_upgrade_button, _attack_button, _defend_button, _garrison_button, _rally_button, _kill_button, _research_button, _build_button, _surface_button, _underground_button, _pause_button]:
		btn.pressed.connect(func(): AudioManager.play("click"))
	for unit_id: String in _fighter_upgrade_buttons:
		_fighter_upgrade_buttons[unit_id].pressed.connect(func(): AudioManager.play("click"))
	for speed: float in _speed_buttons:
		_speed_buttons[speed].pressed.connect(func(): AudioManager.play("click"))

	EconomyManager.coin_changed.connect(_on_economy_changed)
	EconomyManager.population_changed.connect(_on_economy_changed)
	EconomyManager.miner_level_changed.connect(_on_economy_changed)

	var player_building: Node2D = _get_player_building()
	if player_building:
		player_building.hp_changed.connect(_on_building_hp_changed.bind(player_building))
	var enemy_building: Node2D = _get_enemy_building()
	if enemy_building:
		enemy_building.hp_changed.connect(_on_building_hp_changed.bind(enemy_building))

	GameManager.game_over.connect(_on_game_over)
	_updates._setup_faction_icons()
	_menus._build_pause_menu()
	_menus._build_build_menu()
	_build_lava_banner()
	_build_weather_banner()
	_build_faction_popup()
	_on_economy_changed(GameManager.Team.PLAYER)
	_updates._sync_view_buttons()
	_updates._sync_speed_buttons()
	_updates._initialize_hp_labels()


func _process(_delta: float) -> void:
	var pc: PlayerController = _get_player_controller()
	if pc:
		_updates._update_selection_label(pc)
		_updates._sync_view_buttons()
		# The Rally button is a momentary arm: it stays "pressed" only while
		# the controller waits for the rally-point right-click.
		if _rally_button.button_pressed != pc.is_rally_armed():
			_rally_button.set_pressed_no_signal(pc.is_rally_armed())
		var build_menu_open: bool = _build_menu != null and _build_menu.visible
		if _build_button.button_pressed != build_menu_open:
			_build_button.set_pressed_no_signal(build_menu_open)
		_updates._sync_stance_buttons(pc)
	_updates._update_upgrade_button()
	_updates._update_fighter_upgrade_buttons()
	_updates._update_unit_breakdown()
	_update_lava_banner()
	_update_weather_banner()
	if _build_menu != null and _build_menu.visible:
		_menus._update_build_menu()
	# Keep the pause menu in sync with the tree state (pause is toggled from
	# PlayerController via Space/Esc) — except when the pause is owned by the
	# research overlay's "Pause game" toggle, which has its own UI on top.
	var pause_menu_wanted: bool = get_tree().paused and not _research_panel.owns_pause()
	if _pause_panel != null and _pause_panel.visible != pause_menu_wanted:
		_pause_panel.visible = pause_menu_wanted


func _on_pause_restart() -> void:
	get_tree().paused = false
	GameManager.reset()
	FactionManager.reset()
	EconomyManager.reset()
	ResearchManager.reset()
	WeatherManager.reset()
	AIBeliefSystem.reset()
	get_tree().reload_current_scene()


## In-game Quit returns to the main menu (the home screen) instead of closing
## the app — quitting is a no-op in the web export, and desktop players get a
## consistent "back to menu" flow. Global state is reset so the menu and the
## next match start clean.
func _quit_to_menu() -> void:
	get_tree().paused = false
	GameManager.reset()
	FactionManager.reset()
	EconomyManager.reset()
	ResearchManager.reset()
	WeatherManager.reset()
	AIBeliefSystem.reset()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _set_game_speed(speed: float) -> void:
	GameManager.set_game_speed(speed)
	_updates._sync_speed_buttons()


func _toggle_soft_pause() -> void:
	GameManager.set_soft_paused(not GameManager.soft_paused)
	_updates._sync_speed_buttons()


func _add_stat_icons() -> void:
	_add_icon_before_label(_coin_label, _ICON_COIN)
	_add_icon_before_label(_miner_level_label, _ICON_MINER)
	_add_icon_before_label(_unit_count_label, _ICON_SWORDSMAN)
	_add_icon_before_label(_player_hp_label, _ICON_HP)
	_add_icon_before_label(_enemy_hp_label, _ICON_HP)


func _add_icon_before_label(label: Label, texture: Texture2D) -> void:
	var parent: Node = label.get_parent()
	if not (parent is HBoxContainer):
		return
	var icon: TextureRect = TextureRect.new()
	icon.name = label.name + "Icon"
	icon.texture = texture
	icon.custom_minimum_size = Vector2(18, 18)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_FIT_HEIGHT
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	parent.move_child(icon, label.get_index())


func _add_unit_breakdown_icons() -> void:
	var icons: Dictionary = {
		"Miner": _ICON_MINER,
		"Swordsman": _ICON_SWORDSMAN,
		"Archer": _ICON_ARCHER,
		"Wizard": _ICON_WIZARD,
		"Dragon": _ICON_DRAGON,
	}
	for unit_name: String in _unit_count_labels:
		var label: Label = _unit_count_labels[unit_name]
		if icons.has(unit_name):
			_add_icon_before_label(label, icons[unit_name])
		label.tooltip_text = "%s count" % unit_name


func _add_attack_button_icon() -> void:
	var icon: TextureRect = TextureRect.new()
	icon.name = "AttackIcon"
	icon.texture = _ICON_ATTACK
	icon.custom_minimum_size = Vector2(24, 24)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_FIT_HEIGHT
	icon.position = Vector2(38, 6)
	icon.size = Vector2(24, 24)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attack_button.add_child(icon)
	_attack_button.move_child(icon, 0)


func _upgrade_fighter(unit_id: String) -> void:
	var pc: PlayerController = _get_player_controller()
	if pc:
		pc.upgrade_fighter(unit_id)


func _upgrade_miner() -> void:
	var pc: PlayerController = _get_player_controller()
	if pc:
		pc.upgrade_miner()


func _stance(stance: String) -> void:
	var pc: PlayerController = _get_player_controller()
	if pc:
		pc.set_stance(stance)


func _kill_selected() -> void:
	var pc: PlayerController = _get_player_controller()
	if pc:
		pc.kill_selected()


## BottomBar Research button / R hotkey: shows or hides the research panel.
func toggle_research_panel() -> void:
	_research_panel.visible = not _research_panel.visible


func is_research_panel_open() -> bool:
	return _research_panel.visible


func _set_view(underground: bool) -> void:
	var pc: PlayerController = _get_player_controller()
	if pc:
		pc.set_view(underground)
	_updates._sync_view_buttons()


func _on_economy_changed(team: GameManager.Team) -> void:
	if team != GameManager.Team.PLAYER:
		return
	_coin_label.text = "%d" % EconomyManager.get_coin(team)
	_miner_level_label.text = "L%d" % EconomyManager.get_miner_level(team)
	_unit_count_label.text = "%d/%d" % [EconomyManager.get_population(team), _Constants.MAX_UNITS]


func _on_building_hp_changed(current: int, _maximum: int, building: Node2D) -> void:
	if building == null:
		return
	if building.get("team") == GameManager.Team.PLAYER:
		_player_hp_label.text = "%d" % current
	else:
		_enemy_hp_label.text = "%d" % current


func _get_player_controller() -> PlayerController:
	# Explicit cast: during scene teardown the node may already be scriptless,
	# and an implicit downcast would throw a return-type error every frame.
	return get_node_or_null("/root/Main/PlayerController") as PlayerController


func _get_player_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == GameManager.Team.PLAYER:
			return b
	return null


func _get_enemy_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") != GameManager.Team.PLAYER:
			return b
	return null


var _pause_panel: PanelContainer = null
# Radial build menu (Revamp Phase 7): options fan out above the Build button.
var _build_menu: Control = null
var _build_lantern_button: Button = null
var _build_mine_lantern_button: Button = null
var _build_tower_button: Button = null
var _build_wall_button: Button = null
var _build_pigeon_button: Button = null

# Lava warning banner (Revamp Phase 4): flashing countdown above the bottom
# bar while a lava rise is imminent. Driven entirely by GridWorld signals and
# its live countdown, so it stays correct through pauses and speed changes.
var _lava_banner: HBoxContainer = null
var _lava_banner_label: Label = null

# Weather banner + storm vignette (Revamp Phase 5): flashing countdown at the
# top center while a snowstorm is imminent, and a dark-blue edge vignette
# while the storm rages. Driven by WeatherManager signals and its live
# countdown, same as the lava banner.
var _weather_banner: HBoxContainer = null
var _weather_banner_label: Label = null
var _storm_vignette: TextureRect = null


func _build_lava_banner() -> void:
	_lava_banner = HBoxContainer.new()
	_lava_banner.name = "LavaWarningBanner"
	_lava_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	_lava_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lava_banner.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_lava_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lava_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_lava_banner.position.y = -150.0
	var icon: TextureRect = TextureRect.new()
	icon.texture = _ICON_LAVA
	icon.custom_minimum_size = Vector2(26, 26)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_FIT_HEIGHT
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lava_banner.add_child(icon)
	_lava_banner_label = Label.new()
	_lava_banner_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.15))
	_lava_banner_label.add_theme_font_size_override("font_size", 28)
	_lava_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lava_banner.add_child(_lava_banner_label)
	_lava_banner.visible = false
	add_child(_lava_banner)
	var grid: GridWorld = get_node_or_null("/root/Main/World/GridWorld")
	if grid != null:
		grid.lava_warning_started.connect(_on_lava_warning_started)
		grid.lava_risen.connect(_on_lava_risen)


func _on_lava_warning_started(_seconds: float, _layers: int) -> void:
	_lava_banner.visible = true


func _on_lava_risen(_layers: int) -> void:
	_lava_banner.visible = false


func _update_lava_banner() -> void:
	if _lava_banner == null or not _lava_banner.visible:
		return
	var grid: GridWorld = get_node_or_null("/root/Main/World/GridWorld")
	if grid == null:
		_lava_banner.visible = false
		return
	var remaining: float = grid.get_lava_warning_remaining()
	if remaining <= 0.0 or not GameManager.game_active:
		_lava_banner.visible = false
		return
	_lava_banner_label.text = "LAVA RISING IN %ds" % ceili(remaining)
	# Flashing orange pulse.
	var pulse: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 120.0)
	_lava_banner.modulate = Color(1.0, 1.0, 1.0, pulse)


func _build_weather_banner() -> void:
	_weather_banner = HBoxContainer.new()
	_weather_banner.name = "WeatherWarningBanner"
	_weather_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	_weather_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weather_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_weather_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_weather_banner.grow_vertical = Control.GROW_DIRECTION_END
	_weather_banner.position.y = 120.0
	var icon: TextureRect = TextureRect.new()
	icon.texture = _ICON_SNOWSTORM
	icon.custom_minimum_size = Vector2(26, 26)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_FIT_HEIGHT
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weather_banner.add_child(icon)
	_weather_banner_label = Label.new()
	# Revamp Phase 7: the warning flashes red (the storm itself stays icy).
	_weather_banner_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
	_weather_banner_label.add_theme_font_size_override("font_size", 28)
	_weather_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weather_banner.add_child(_weather_banner_label)
	_weather_banner.visible = false
	add_child(_weather_banner)

	# Storm vignette: dark-blue edges closing in while the snowstorm rages.
	_storm_vignette = TextureRect.new()
	_storm_vignette.name = "StormVignette"
	_storm_vignette.texture = _make_vignette_texture()
	_storm_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_storm_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_storm_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_storm_vignette.visible = false
	add_child(_storm_vignette)

	WeatherManager.weather_warning_started.connect(_on_weather_warning_started)
	WeatherManager.snowstorm_started.connect(_on_snowstorm_started)
	WeatherManager.snowstorm_ended.connect(_on_snowstorm_ended)


## Radial gradient: transparent center fading to dark blue at the edges.
func _make_vignette_texture() -> Texture2D:
	var size: int = 256
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center: float = (size - 1) / 2.0
	for x in range(size):
		for y in range(size):
			var d: float = Vector2(x - center, y - center).length() / center
			var alpha: float = clampf((d - 0.45) / 0.55, 0.0, 1.0) ** 1.6 * 0.55
			img.set_pixel(x, y, Color(0.08, 0.16, 0.42, alpha))
	return ImageTexture.create_from_image(img)


func _on_weather_warning_started(_seconds: float) -> void:
	_weather_banner.visible = true


func _on_snowstorm_started() -> void:
	_weather_banner.visible = false
	_storm_vignette.visible = true


func _on_snowstorm_ended() -> void:
	_storm_vignette.visible = false


func _update_weather_banner() -> void:
	if _weather_banner == null:
		return
	if _weather_banner.visible:
		var remaining: float = WeatherManager.get_snowstorm_warning_remaining()
		if remaining <= 0.0 or not GameManager.game_active:
			_weather_banner.visible = false
		else:
			_weather_banner_label.text = "SNOWSTORM IN %ds" % ceili(remaining)
			# Flashing red pulse.
			var pulse: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 120.0)
			_weather_banner.modulate = Color(1.0, 1.0, 1.0, pulse)
	# The vignette follows the live storm state (covers scene reloads and
	# game-over freezes where signals alone would leave it stuck).
	var storm_on: bool = WeatherManager.is_snowstorm_active() and GameManager.game_active
	if _storm_vignette != null and _storm_vignette.visible != storm_on:
		_storm_vignette.visible = storm_on


# Faction identified popup (Revamp Phase 7): a brief center-screen banner
# with the enemy faction's icon when a scout reaches their base.
var _faction_popup: PanelContainer = null
var _faction_popup_icon: TextureRect = null
var _faction_popup_label: Label = null
var _faction_popup_tween: Tween = null


func _build_faction_popup() -> void:
	_faction_popup = PanelContainer.new()
	_faction_popup.name = "FactionIdentifiedPopup"
	_faction_popup.visible = false
	_faction_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_styling._style_panel(_faction_popup)
	_faction_popup.set_anchors_preset(Control.PRESET_CENTER)
	_faction_popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_faction_popup.grow_vertical = Control.GROW_DIRECTION_BOTH
	_faction_popup.position.y = -160.0
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_faction_popup.add_child(hbox)
	_faction_popup_icon = TextureRect.new()
	_faction_popup_icon.custom_minimum_size = Vector2(40, 40)
	_faction_popup_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_faction_popup_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_faction_popup_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_faction_popup_icon)
	_faction_popup_label = Label.new()
	_faction_popup_label.add_theme_font_size_override("font_size", 24)
	_faction_popup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_faction_popup_label)
	add_child(_faction_popup)
	FactionManager.faction_identified.connect(_on_faction_identified_popup)


func _on_faction_identified_popup(team: GameManager.Team) -> void:
	# Only the player learning the ENEMY faction warrants a popup (the AI
	# scouting the player's base is its own business).
	if team != GameManager.Team.ENEMY:
		return
	var faction: FactionData = FactionManager.get_faction(GameManager.Team.ENEMY)
	if faction == null:
		return
	_faction_popup_icon.texture = faction.icon
	_faction_popup_label.text = "ENEMY FACTION IDENTIFIED: %s" % faction.faction_name.to_upper()
	_faction_popup_label.add_theme_color_override("font_color", faction.menu_color)
	if _faction_popup_tween != null and _faction_popup_tween.is_valid():
		_faction_popup_tween.kill()
	_faction_popup.visible = true
	_faction_popup.modulate.a = 0.0
	_faction_popup_tween = create_tween()
	_faction_popup_tween.tween_property(_faction_popup, "modulate:a", 1.0, 0.3)
	_faction_popup_tween.tween_interval(3.5)
	_faction_popup_tween.tween_property(_faction_popup, "modulate:a", 0.0, 0.6)
	_faction_popup_tween.tween_callback(func(): _faction_popup.visible = false)


func _on_game_over(winner: GameManager.Team) -> void:
	# Let the slow-mo collapse play out before the panel fades in (real-time
	# delay, independent of the 0.3 time scale).
	await get_tree().create_timer(1.4, true, false, true).timeout
	_game_over_panel.visible = true
	_game_over_panel.modulate.a = 0.0
	var container: VBoxContainer = $GameOverPanel/MarginContainer/VBoxContainer
	var label: Label = $GameOverPanel/MarginContainer/VBoxContainer/ResultLabel
	if winner == GameManager.Team.PLAYER:
		label.text = "VICTORY"
		label.modulate = Color.GREEN
	else:
		label.text = "DEFEAT"
		label.modulate = Color.RED

	var stats: Label = Label.new()
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var total_seconds: int = int(GameManager.match_time)
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	stats.text = "Time: %d:%02d\nUnits Trained: %d\nCoin Mined: %d" % [
		minutes,
		seconds,
		EconomyManager.get_units_trained(GameManager.Team.PLAYER),
		EconomyManager.get_coin_mined(GameManager.Team.PLAYER)
	]
	container.add_child(stats)
	container.move_child(stats, 1)
	var fade: Tween = create_tween()
	fade.tween_property(_game_over_panel, "modulate:a", 1.0, 0.5)


func _play_again() -> void:
	# Autoloads survive scene reload, so reset global state before restarting.
	get_tree().paused = false
	GameManager.reset()
	FactionManager.reset()
	EconomyManager.reset()
	ResearchManager.reset()
	WeatherManager.reset()
	AIBeliefSystem.reset()
	get_tree().reload_current_scene()
