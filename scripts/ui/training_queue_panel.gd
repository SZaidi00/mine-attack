class_name TrainingQueuePanel
extends Control

const _Constants = preload("res://scripts/autoload/constants.gd")

const _PROGRESS_BG: Texture2D = preload("res://frost_mines_assets/ui/progress_bg.png")
const _PROGRESS_FILL: Texture2D = preload("res://frost_mines_assets/ui/progress_fill.png")
const _BUTTON_NORMAL: Texture2D = preload("res://frost_mines_assets/ui/button_normal.png")
const _BUTTON_HOVER: Texture2D = preload("res://frost_mines_assets/ui/button_hover.png")
const _BUTTON_PRESSED: Texture2D = preload("res://frost_mines_assets/ui/button_pressed.png")

@onready var _progress_bar: ProgressBar = $ProgressBar
@onready var _current_label: Label = $CurrentLabel
@onready var _queue_container: HBoxContainer = $QueueContainer

var _building: Node2D = null
var _queue_buttons: Array[Button] = []


func _ready() -> void:
	custom_minimum_size = Vector2(260, 70)
	_building = _get_player_building()
	if _building:
		_building.queue_changed.connect(_on_queue_changed)
	_style_progress_bar()
	_on_queue_changed([])


func _process(_delta: float) -> void:
	_update_progress()


func _style_progress_bar() -> void:
	if _progress_bar == null:
		return
	_progress_bar.custom_minimum_size = Vector2(140, 6)
	var bg: StyleBoxTexture = StyleBoxTexture.new()
	bg.texture = _PROGRESS_BG
	bg.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	bg.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	_progress_bar.add_theme_stylebox_override("background", bg)
	var fill: StyleBoxTexture = StyleBoxTexture.new()
	fill.texture = _PROGRESS_FILL
	fill.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	fill.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	_progress_bar.add_theme_stylebox_override("fill", fill)
	if _current_label:
		_current_label.add_theme_color_override("font_color", Color("#e2e8f0"))
		_current_label.add_theme_font_size_override("font_size", 11)


func _update_progress() -> void:
	if _progress_bar == null or _building == null:
		if _progress_bar:
			_progress_bar.value = 0.0
		return
	var queue: Array = _building.call("get_queue")
	if queue.is_empty():
		_progress_bar.value = 0.0
		if _current_label:
			_current_label.text = "Queue Empty"
		return

	var current = queue[0]
	var pct: float = 1.0 - (current.remaining / current.data.train_time)
	pct = clampf(pct, 0.0, 1.0)
	_progress_bar.value = pct
	if _current_label:
		_current_label.text = "%s — %d%%" % [current.id.capitalize(), int(pct * 100)]


func _on_queue_changed(_entries: Array) -> void:
	# Rebuild queued-item buttons (skip the currently training item at index 0).
	for btn in _queue_buttons:
		btn.queue_free()
	_queue_buttons.clear()

	if _queue_container == null or _building == null:
		return
	var queue: Array = _building.call("get_queue")

	for i in range(1, queue.size()):
		var entry = queue[i]
		var btn: Button = Button.new()
		btn.text = entry.id.capitalize().substr(0, 3)
		btn.tooltip_text = "Click to cancel and refund %d coin" % entry.data.cost
		btn.custom_minimum_size = Vector2(70, 40)
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color", Color("#94a3b8"))
		btn.add_theme_stylebox_override("normal", _make_textured_style(_BUTTON_NORMAL))
		btn.add_theme_stylebox_override("hover", _make_textured_style(_BUTTON_HOVER))
		btn.add_theme_stylebox_override("pressed", _make_textured_style(_BUTTON_PRESSED))
		btn.pressed.connect(_cancel_queue.bind(i))
		_queue_container.add_child(btn)
		_queue_buttons.append(btn)


func _make_textured_style(texture: Texture2D) -> StyleBoxTexture:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = texture
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.content_margin_left = 4
	style.content_margin_top = 4
	style.content_margin_right = 4
	style.content_margin_bottom = 4
	return style


func _cancel_queue(index: int) -> void:
	if _building:
		_building.call("cancel_queue", index)


func _get_player_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == GameManager.Team.PLAYER:
			return b
	return null
