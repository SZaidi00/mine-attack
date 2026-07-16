extends CanvasLayer

const _Constants = preload("res://scripts/autoload/constants.gd")

const _PANEL_BG: Texture2D = preload("res://frost_mines_assets/ui/panel_background.png")
const _BUTTON_NORMAL: Texture2D = preload("res://frost_mines_assets/ui/button_normal.png")
const _BUTTON_HOVER: Texture2D = preload("res://frost_mines_assets/ui/button_hover.png")
const _BUTTON_PRESSED: Texture2D = preload("res://frost_mines_assets/ui/button_pressed.png")
const _BUTTON_DISABLED: Texture2D = preload("res://frost_mines_assets/ui/button_disabled.png")
const _BUTTON_UPGRADE: Texture2D = preload("res://frost_mines_assets/ui/button_upgrade.png")
const _TAB_ACTIVE: Texture2D = preload("res://frost_mines_assets/ui/tab_active.png")
const _TAB_INACTIVE: Texture2D = preload("res://frost_mines_assets/ui/tab_inactive.png")
const _ICON_COIN: Texture2D = preload("res://frost_mines_assets/icons/icon_coin.png")
const _ICON_MINER: Texture2D = preload("res://frost_mines_assets/icons/icon_miner.png")
const _ICON_SWORDSMAN: Texture2D = preload("res://frost_mines_assets/icons/icon_swordsman.png")
const _ICON_BUILDING: Texture2D = preload("res://frost_mines_assets/icons/icon_building.png")

@onready var _coin_label: Label = $TopBar/MarginContainer/VBoxContainer/StatsRow/LeftGroup/CoinLabel
@onready var _miner_level_label: Label = $TopBar/MarginContainer/VBoxContainer/StatsRow/LeftGroup/MinerLevelLabel
@onready var _unit_count_label: Label = $TopBar/MarginContainer/VBoxContainer/StatsRow/CenterGroup/UnitCountLabel
@onready var _player_hp_label: Label = $TopBar/MarginContainer/VBoxContainer/StatsRow/RightGroup/PlayerHPLabel
@onready var _enemy_hp_label: Label = $TopBar/MarginContainer/VBoxContainer/StatsRow/RightGroup/EnemyHPLabel
@onready var _selection_label: Label = $SelectionLabel
@onready var _surface_button: Button = $TopBar/MarginContainer/VBoxContainer/TabsRow/TabGroup/SurfaceButton
@onready var _underground_button: Button = $TopBar/MarginContainer/VBoxContainer/TabsRow/TabGroup/UndergroundButton
@onready var _upgrade_button: Button = $BottomBar/MarginContainer/HBoxContainer/UpgradeMinerButton
@onready var _attack_button: Button = $BottomBar/MarginContainer/HBoxContainer/AttackButton
@onready var _defend_button: Button = $BottomBar/MarginContainer/HBoxContainer/DefendButton
@onready var _garrison_button: Button = $BottomBar/MarginContainer/HBoxContainer/GarrisonButton
@onready var _game_over_panel: PanelContainer = $GameOverPanel


func _ready() -> void:
	_ignore_mouse_recursive($TopBar)
	_ignore_mouse_recursive($BottomBar)
	_ignore_mouse_recursive(_game_over_panel)
	_style_panel($TopBar)
	_style_panel($BottomBar)
	_style_panel(_game_over_panel)
	_style_tab_buttons()
	_style_upgrade_button()
	_style_stance_buttons()
	_add_stat_icons()

	_upgrade_button.pressed.connect(_upgrade_miner)
	_attack_button.pressed.connect(_stance.bind("attack"))
	_defend_button.pressed.connect(_stance.bind("defend"))
	_garrison_button.pressed.connect(_stance.bind("garrison"))
	_surface_button.pressed.connect(_set_view.bind(false))
	_underground_button.pressed.connect(_set_view.bind(true))
	$GameOverPanel/MarginContainer/VBoxContainer/QuitButton.pressed.connect(func(): get_tree().quit())
	$GameOverPanel/MarginContainer/VBoxContainer/PlayAgainButton.pressed.connect(_play_again)

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
	_on_economy_changed(GameManager.Team.PLAYER)
	_sync_view_buttons()
	_initialize_hp_labels()


func _process(_delta: float) -> void:
	var pc: PlayerController = _get_player_controller()
	if pc:
		_selection_label.text = "Selected: %d" % pc.get_selected_units().size()
		_sync_view_buttons()
	_update_upgrade_button()


func _ignore_mouse_recursive(node: Node) -> void:
	if node is Control:
		# Keep buttons interactive; ignore everything else.
		if not (node is Button):
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse_recursive(child)


func _style_panel(panel: PanelContainer) -> void:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = _PANEL_BG
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	panel.add_theme_stylebox_override("panel", style)


func _style_tab_buttons() -> void:
	for btn in [_surface_button, _underground_button]:
		btn.custom_minimum_size = Vector2(90, 28)
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color", Color("#e2e8f0"))
		btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
		btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
		btn.add_theme_stylebox_override("normal", _make_textured_style(_TAB_INACTIVE, 4))
		btn.add_theme_stylebox_override("pressed", _make_textured_style(_TAB_ACTIVE, 4))
		btn.add_theme_stylebox_override("hover", _make_textured_style(_TAB_ACTIVE, 4))


func _style_upgrade_button() -> void:
	_upgrade_button.custom_minimum_size = Vector2(120, 70)
	_upgrade_button.add_theme_font_size_override("font_size", 12)
	_upgrade_button.add_theme_color_override("font_color", Color("#fbbf24"))
	_upgrade_button.add_theme_color_override("font_disabled_color", Color("#94a3b8"))
	_upgrade_button.add_theme_stylebox_override("normal", _make_textured_style(_BUTTON_UPGRADE, 6))
	_upgrade_button.add_theme_stylebox_override("hover", _make_textured_style(_BUTTON_UPGRADE, 6))
	_upgrade_button.add_theme_stylebox_override("pressed", _make_textured_style(_BUTTON_PRESSED, 6))
	_upgrade_button.add_theme_stylebox_override("disabled", _make_textured_style(_BUTTON_DISABLED, 6))


func _style_stance_buttons() -> void:
	for btn in [_attack_button, _defend_button, _garrison_button]:
		btn.custom_minimum_size = Vector2(100, 70)
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", Color("#e2e8f0"))
		btn.add_theme_stylebox_override("normal", _make_textured_style(_BUTTON_NORMAL, 6))
		btn.add_theme_stylebox_override("hover", _make_textured_style(_BUTTON_HOVER, 6))
		btn.add_theme_stylebox_override("pressed", _make_textured_style(_BUTTON_PRESSED, 6))


func _make_textured_style(texture: Texture2D, content_margin: int = 6) -> StyleBoxTexture:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = texture
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.content_margin_left = content_margin
	style.content_margin_top = content_margin
	style.content_margin_right = content_margin
	style.content_margin_bottom = content_margin
	return style


func _add_stat_icons() -> void:
	_add_icon_before_label(_coin_label, _ICON_COIN)
	_add_icon_before_label(_miner_level_label, _ICON_MINER)
	_add_icon_before_label(_unit_count_label, _ICON_SWORDSMAN)
	_add_icon_before_label(_player_hp_label, _ICON_BUILDING)
	_add_icon_before_label(_enemy_hp_label, _ICON_BUILDING)


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


func _update_upgrade_button() -> void:
	var level: int = EconomyManager.get_miner_level(GameManager.Team.PLAYER)
	var cost: int = EconomyManager.get_miner_upgrade_cost(GameManager.Team.PLAYER)
	if cost < 0:
		_upgrade_button.text = "Upgrade Miner\nMax Level"
		_upgrade_button.disabled = true
	else:
		_upgrade_button.text = "Upgrade Miner\nLv %d → %d | %d" % [level, level + 1, cost]
		_upgrade_button.disabled = false


func _upgrade_miner() -> void:
	var pc: PlayerController = _get_player_controller()
	if pc:
		pc.upgrade_miner()


func _stance(stance: String) -> void:
	var pc: PlayerController = _get_player_controller()
	if pc:
		pc.set_stance(stance)


func _set_view(underground: bool) -> void:
	var pc: PlayerController = _get_player_controller()
	if pc:
		pc.set_view(underground)
	_sync_view_buttons()


func _sync_view_buttons() -> void:
	var pc: PlayerController = _get_player_controller()
	var underground: bool = pc.is_underground_view() if pc else false
	if _surface_button.button_pressed != (not underground):
		_surface_button.set_pressed_no_signal(not underground)
	if _underground_button.button_pressed != underground:
		_underground_button.set_pressed_no_signal(underground)


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


func _initialize_hp_labels() -> void:
	var player_building: Node2D = _get_player_building()
	if player_building:
		_player_hp_label.text = "%d" % player_building.get("_hp")
	var enemy_building: Node2D = _get_enemy_building()
	if enemy_building:
		_enemy_hp_label.text = "%d" % enemy_building.get("_hp")


func _get_player_controller() -> PlayerController:
	return get_node_or_null("/root/Main/PlayerController")


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


func _on_game_over(winner: GameManager.Team) -> void:
	_game_over_panel.visible = true
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


func _play_again() -> void:
	# Autoloads survive scene reload, so reset global state before restarting.
	GameManager.reset()
	EconomyManager.reset()
	get_tree().reload_current_scene()
