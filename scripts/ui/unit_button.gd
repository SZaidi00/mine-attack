class_name UnitButton
extends Button

const _Constants = preload("res://scripts/autoload/constants.gd")

const _BUTTON_NORMAL: Texture2D = preload("res://frost_mines_assets/ui/button_normal.png")
const _BUTTON_HOVER: Texture2D = preload("res://frost_mines_assets/ui/button_hover.png")
const _BUTTON_PRESSED: Texture2D = preload("res://frost_mines_assets/ui/button_pressed.png")
const _BUTTON_DISABLED: Texture2D = preload("res://frost_mines_assets/ui/button_disabled.png")
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
	if not success:
		_shake()


func _on_economy_changed(_team: GameManager.Team) -> void:
	_update_state()


func _on_queue_changed(_entries: Array) -> void:
	_update_state()


func _update_state() -> void:
	var can_afford: bool = false
	var has_space: bool = false

	var player_coin: int = EconomyManager.get_coin(GameManager.Team.PLAYER)
	can_afford = player_coin >= _Constants.COSTS.get(unit_id, 999999)

	var building: Node2D = _get_player_building()
	if building:
		var queue: Array = building.call("get_queue")
		var queue_count: int = queue.size()
		var current_pop: int = EconomyManager.get_population(GameManager.Team.PLAYER)
		# One more unit must still fit under the cap.
		has_space = queue_count < _Constants.MAX_QUEUE_SIZE and current_pop < _Constants.MAX_UNITS

	disabled = not (can_afford and has_space)
	_apply_style()


func _apply_style() -> void:
	add_theme_font_size_override("font_size", 11)
	add_theme_color_override("font_color", Color("#e2e8f0"))
	add_theme_color_override("font_pressed_color", Color("#e2e8f0"))
	add_theme_color_override("font_hover_color", Color("#e2e8f0"))
	add_theme_color_override("font_disabled_color", Color("#94a3b8"))

	if disabled:
		add_theme_stylebox_override("normal", _make_textured_style(_BUTTON_DISABLED))
		add_theme_stylebox_override("hover", _make_textured_style(_BUTTON_DISABLED))
		add_theme_stylebox_override("pressed", _make_textured_style(_BUTTON_DISABLED))
		modulate = Color(1, 1, 1, 0.6)
	else:
		add_theme_stylebox_override("normal", _make_textured_style(_BUTTON_NORMAL))
		add_theme_stylebox_override("hover", _make_textured_style(_BUTTON_HOVER))
		add_theme_stylebox_override("pressed", _make_textured_style(_BUTTON_PRESSED))
		modulate = Color(1, 1, 1, 1)


func _make_textured_style(texture: Texture2D) -> StyleBoxTexture:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = texture
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
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
