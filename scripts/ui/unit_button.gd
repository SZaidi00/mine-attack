class_name UnitButton
extends Button

const _Constants = preload("res://scripts/autoload/constants.gd")

const _ICON_MINER: Texture2D = preload("res://frost_mines_assets/icons/icon_miner.png")
const _ICON_SWORDSMAN: Texture2D = preload("res://frost_mines_assets/icons/icon_swordsman.png")
const _ICON_ARCHER: Texture2D = preload("res://frost_mines_assets/icons/icon_archer.png")
const _ICON_WIZARD: Texture2D = preload("res://frost_mines_assets/icons/icon_wizard.png")

const _UNIT_ICONS: Dictionary = {
	"miner": _ICON_MINER,
	"swordsman": _ICON_SWORDSMAN,
	"archer": _ICON_ARCHER,
	"wizard": _ICON_WIZARD,
}

const _UNIT_HOTKEYS: Dictionary = {
	"miner": "1",
	"swordsman": "2",
	"archer": "3",
	"wizard": "4",
}

@export var unit_id: String = "miner"
@export var player_controller: NodePath

@onready var _cost_label: Label = $CostLabel
@onready var _time_label: Label = $TimeLabel
@onready var _icon: TextureRect = $Icon

var _pc: PlayerController = null


func _ready() -> void:
	custom_minimum_size = Vector2(100, 70)
	pressed.connect(_on_pressed)
	_update_display()
	_refresh_controller()
	_setup_icon()
	_reposition_labels()
	_apply_style()
	_update_state()
	_ignore_child_mouse(_cost_label)
	_ignore_child_mouse(_time_label)
	_ignore_child_mouse(_icon)

	EconomyManager.coin_changed.connect(_on_economy_changed)
	EconomyManager.population_changed.connect(_on_economy_changed)

	# Re-check state whenever the building queue changes.
	var building: Node2D = _get_player_building()
	if building:
		building.queue_changed.connect(_on_queue_changed)


func _refresh_controller() -> void:
	if player_controller:
		_pc = get_node_or_null(player_controller) as PlayerController
	else:
		_pc = get_node_or_null("/root/Main/PlayerController") as PlayerController


func _update_display() -> void:
	if not _Constants.COSTS.has(unit_id):
		push_error("UnitButton: unknown unit_id '%s'" % unit_id)
		return
	text = ""  # Use child labels only; name is implied by icon/position.
	if _cost_label:
		_cost_label.text = "%d" % _Constants.COSTS[unit_id]
	if _time_label:
		_time_label.text = "%.1fs" % _Constants.TRAIN_TIMES[unit_id]


func _on_pressed() -> void:
	_refresh_controller()
	if _pc == null:
		return
	var success: bool = _pc.train_unit(unit_id)
	if success:
		AudioManager.play("click")
	else:
		_shake()


func _on_economy_changed(_team: GameManager.Team) -> void:
	_update_state()


func _on_queue_changed(_entries: Array) -> void:
	_update_state()


func _update_state() -> void:
	var can_afford: bool = false
	var has_space: bool = false
	var pop_maxed: bool = false

	var player_coin: int = EconomyManager.get_coin(GameManager.Team.PLAYER)
	can_afford = player_coin >= _Constants.COSTS.get(unit_id, 999999)

	var building: Node2D = _get_player_building()
	if building:
		var current_pop: int = EconomyManager.get_population(GameManager.Team.PLAYER)
		# One more unit must still fit under the population cap (the queue
		# itself is uncapped).
		pop_maxed = current_pop >= _Constants.MAX_UNITS
		has_space = not pop_maxed

	disabled = not (can_afford and has_space)
	# Explain why the button is disabled instead of going silently grey.
	if pop_maxed:
		tooltip_text = "POPULATION MAX (%d/%d)" % [EconomyManager.get_population(GameManager.Team.PLAYER), _Constants.MAX_UNITS]
	elif not can_afford:
		tooltip_text = "Not enough coin (%d needed)" % _Constants.COSTS.get(unit_id, 0)
	else:
		tooltip_text = "Train %s [%s]" % [unit_id.capitalize(), _UNIT_HOTKEYS.get(unit_id, "")]
	_apply_style()


func _apply_style() -> void:
	add_theme_font_size_override("font_size", 11)
	add_theme_color_override("font_color", Color("#e2e8f0"))
	add_theme_color_override("font_pressed_color", Color("#e2e8f0"))
	add_theme_color_override("font_hover_color", Color("#e2e8f0"))
	add_theme_color_override("font_disabled_color", Color("#94a3b8"))

	if disabled:
		var disabled_style: StyleBoxFlat = _make_flat_style(Color("#151c29"))
		add_theme_stylebox_override("normal", disabled_style)
		add_theme_stylebox_override("hover", disabled_style)
		add_theme_stylebox_override("pressed", disabled_style)
		modulate = Color(1, 1, 1, 0.55)
	else:
		add_theme_stylebox_override("normal", _make_flat_style(Color("#1a2434"), Color(1, 1, 1, 0.07)))
		add_theme_stylebox_override("hover", _make_flat_style(Color("#253650"), Color("#4a86c8")))
		add_theme_stylebox_override("pressed", _make_flat_style(Color("#111927"), Color(1, 1, 1, 0.07)))
		modulate = Color(1, 1, 1, 1)


func _make_flat_style(bg: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	if border.a > 0.0:
		style.border_color = border
		style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 6
	style.content_margin_top = 6
	style.content_margin_right = 6
	style.content_margin_bottom = 6
	return style


func _setup_icon() -> void:
	if _icon == null:
		return
	if _UNIT_ICONS.has(unit_id):
		_icon.texture = _UNIT_ICONS[unit_id]
	_icon.custom_minimum_size = Vector2(28, 28)
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.expand_mode = TextureRect.EXPAND_FIT_HEIGHT
	_icon.position = Vector2(36, 4)
	_icon.size = Vector2(28, 28)


func _reposition_labels() -> void:
	if _cost_label:
		_cost_label.position = Vector2(36, 34)
		_cost_label.size = Vector2(28, 16)
	if _time_label:
		_time_label.position = Vector2(32, 52)
		_time_label.size = Vector2(36, 16)


func _shake() -> void:
	var tween: Tween = create_tween()
	var base_x: float = position.x
	tween.tween_property(self, "position:x", base_x + 5, 0.05)
	tween.tween_property(self, "position:x", base_x - 5, 0.05)
	tween.tween_property(self, "position:x", base_x, 0.05)


func _ignore_child_mouse(node: Control) -> void:
	if node:
		node.mouse_filter = MOUSE_FILTER_IGNORE


func _get_player_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == GameManager.Team.PLAYER:
			return b
	return null
