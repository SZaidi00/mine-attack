class_name TrainingQueuePanel
extends PanelContainer

## Frosted-steel production module for the player building's training queue.
## Shows the active training item with progress, a compact list of queued
## units, capacity readout, and Pause / Clear actions.

const UIThemeTokens = preload("res://scripts/ui/ui_theme_tokens.gd")
const _Constants = preload("res://scripts/autoload/constants.gd")

const _ICON_MINER: Texture2D = preload("res://frost_mines_assets/icons/icon_miner.png")
const _ICON_SWORDSMAN: Texture2D = preload("res://frost_mines_assets/icons/icon_swordsman.png")
const _ICON_ARCHER: Texture2D = preload("res://frost_mines_assets/icons/icon_archer.png")
const _ICON_WIZARD: Texture2D = preload("res://frost_mines_assets/icons/icon_wizard.png")
const _ICON_DRAGON: Texture2D = preload("res://frost_mines_assets/icons/icon_dragon.png")
const _ICON_PIGEON: Texture2D = preload("res://frost_mines_assets/icons/icon_swordsman.png")  # No pigeon icon yet; fallback.

const _UNIT_ICONS: Dictionary = {
	"miner": _ICON_MINER,
	"swordsman": _ICON_SWORDSMAN,
	"archer": _ICON_ARCHER,
	"wizard": _ICON_WIZARD,
	"dragon": _ICON_DRAGON,
	"pigeon": _ICON_PIGEON,
}

var _building: Node2D = null

# Dynamic UI references.
var _title_label: Label = null
var _status_label: Label = null
var _count_label: Label = null
var _active_panel: PanelContainer = null
var _active_icon: TextureRect = null
var _active_name: Label = null
var _active_ready: Label = null
var _active_percent: Label = null
var _progress_bar: ProgressBar = null
var _queued_container: VBoxContainer = null
var _empty_label: Label = null
var _pause_button: Button = null
var _clear_button: Button = null

var _queued_rows: Array[Control] = []
var _last_queue_size: int = -1
var _last_paused: bool = false


func _ready() -> void:
	_building = _get_player_building()
	if _building:
		_building.queue_changed.connect(_on_queue_changed)
		# queue_paused_changed may not exist on older building references; guard.
		if _building.has_signal("queue_paused_changed"):
			_building.queue_paused_changed.connect(_on_queue_paused_changed)
	_build_ui()
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _build_ui() -> void:
	# Clear any scene-injected children so this panel owns its layout.
	for child in get_children():
		child.queue_free()

	add_theme_stylebox_override("panel", UIThemeTokens.make_panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UIThemeTokens.DENSE_PADDING)
	margin.add_theme_constant_override("margin_top", UIThemeTokens.DENSE_PADDING)
	margin.add_theme_constant_override("margin_right", UIThemeTokens.DENSE_PADDING)
	margin.add_theme_constant_override("margin_bottom", UIThemeTokens.DENSE_PADDING)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Header row.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var header_text := VBoxContainer.new()
	header_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_text)

	_title_label = Label.new()
	_title_label.text = "Training queue"
	_title_label.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_HEADER)
	_title_label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	header_text.add_child(_title_label)

	_status_label = Label.new()
	_status_label.text = "No active training"
	_status_label.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	_status_label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_DIM)
	header_text.add_child(_status_label)

	_count_label = Label.new()
	_count_label.text = "0"
	_count_label.add_theme_font_size_override("font_size", 20)
	_count_label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_GOLD)
	header.add_child(_count_label)

	# Active item panel.
	_active_panel = PanelContainer.new()
	_active_panel.visible = false
	_active_panel.add_theme_stylebox_override("panel", _make_active_panel_style())
	vbox.add_child(_active_panel)

	var active_row := HBoxContainer.new()
	active_row.add_theme_constant_override("separation", 8)
	_active_panel.add_child(active_row)

	_active_icon = TextureRect.new()
	_active_icon.custom_minimum_size = Vector2(34, 34)
	_active_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_active_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	active_row.add_child(_active_icon)

	var active_text := VBoxContainer.new()
	active_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_row.add_child(active_text)

	_active_name = Label.new()
	_active_name.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	_active_name.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	active_text.add_child(_active_name)

	_active_ready = Label.new()
	_active_ready.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	_active_ready.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_DIM)
	active_text.add_child(_active_ready)

	_active_percent = Label.new()
	_active_percent.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	_active_percent.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_GOLD)
	active_row.add_child(_active_percent)

	# Progress bar for active item.
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 10)
	_progress_bar.max_value = 1.0
	_progress_bar.value = 0.0
	_progress_bar.visible = false
	UIThemeTokens.apply_progress_bar_theme(_progress_bar, UIThemeTokens.ProgressVariant.BLUE)
	vbox.add_child(_progress_bar)

	# Queued items list.
	_queued_container = VBoxContainer.new()
	_queued_container.add_theme_constant_override("separation", 5)
	_queued_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_queued_container)

	_empty_label = Label.new()
	_empty_label.text = "Queue clear"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	_empty_label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_DIM)
	_queued_container.add_child(_empty_label)

	# Actions footer.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	vbox.add_child(actions)

	_pause_button = Button.new()
	_pause_button.text = "Pause"
	_pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_button.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	UIThemeTokens.apply_button_theme(_pause_button, UIThemeTokens.ButtonVariant.SECONDARY)
	_pause_button.pressed.connect(_on_pause_pressed)
	actions.add_child(_pause_button)

	_clear_button = Button.new()
	_clear_button.text = "Clear"
	_clear_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clear_button.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	UIThemeTokens.apply_button_theme(_clear_button, UIThemeTokens.ButtonVariant.DANGER)
	_clear_button.pressed.connect(_on_clear_pressed)
	actions.add_child(_clear_button)


func _make_active_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UIThemeTokens.COLOR_RECESSED_BG
	style.border_color = Color(UIThemeTokens.COLOR_TEXT_GOLD.r, UIThemeTokens.COLOR_TEXT_GOLD.g, UIThemeTokens.COLOR_TEXT_GOLD.b, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(UIThemeTokens.RADIUS_BUTTON)
	style.content_margin_left = UIThemeTokens.DENSE_PADDING
	style.content_margin_top = UIThemeTokens.DENSE_PADDING
	style.content_margin_right = UIThemeTokens.DENSE_PADDING
	style.content_margin_bottom = UIThemeTokens.DENSE_PADDING
	return style


func _make_queued_row_style(ghost: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UIThemeTokens.COLOR_RECESSED_BG.r, UIThemeTokens.COLOR_RECESSED_BG.g, UIThemeTokens.COLOR_RECESSED_BG.b, 0.65 if ghost else 1.0)
	style.border_color = Color(1, 1, 1, 0.06)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 6
	style.content_margin_top = 5
	style.content_margin_right = 6
	style.content_margin_bottom = 5
	return style


func _on_queue_changed(_entries: Array) -> void:
	_refresh()


func _on_queue_paused_changed(_paused: bool) -> void:
	_refresh()


func _on_pause_pressed() -> void:
	if _building and _building.has_method("toggle_queue_paused"):
		_building.call("toggle_queue_paused")
		AudioManager.play("click")


func _on_clear_pressed() -> void:
	if _building and _building.has_method("clear_queue"):
		_building.call("clear_queue")
		AudioManager.play("click")


func _refresh() -> void:
	if _building == null:
		_set_empty_state()
		return
	var queue: Array = _building.call("get_queue")
	var paused: bool = false
	if _building.has_method("is_queue_paused"):
		paused = _building.call("is_queue_paused")

	_count_label.text = "%d" % queue.size()

	if queue.is_empty():
		_set_empty_state()
		_pause_button.disabled = true
		_clear_button.disabled = true
		return

	_pause_button.disabled = false
	_clear_button.disabled = false
	_pause_button.text = "Resume" if paused else "Pause"

	var active = queue[0]
	var pct: float = 1.0 - (active.remaining / active.train_time)
	pct = clampf(pct, 0.0, 1.0)
	var pop_blocked: bool = not EconomyManager.can_add_population(_building.get("team"), active.data.population)

	_active_panel.visible = true
	_progress_bar.visible = true
	_progress_bar.value = pct
	_active_icon.texture = _UNIT_ICONS.get(active.id, null)
	_active_name.text = active.id.capitalize()

	if paused:
		_status_label.text = "Paused by player"
		_active_ready.text = "Training paused"
	elif pop_blocked:
		_status_label.text = "Paused at population cap"
		_active_ready.text = "Waiting for population space"
	else:
		_status_label.text = "%d in production" % queue.size()
		_active_ready.text = "Ready in %.1fs" % active.remaining
	_active_percent.text = "%d%%" % int(pct * 100)

	# Rebuild queued rows only when the queue size/order changes.
	if queue.size() != _last_queue_size or paused != _last_paused:
		_rebuild_queued_rows(queue, active)
		_last_queue_size = queue.size()
		_last_paused = paused

	_empty_label.visible = false


func _rebuild_queued_rows(queue: Array, active) -> void:
	for row in _queued_rows:
		row.queue_free()
	_queued_rows.clear()

	if queue.size() <= 1:
		_empty_label.visible = true
		return

	_empty_label.visible = false
	for i in range(1, queue.size()):
		var entry = queue[i]
		var row := _make_queued_row(entry, i)
		_queued_container.add_child(row)
		_queued_rows.append(row)


func _make_queued_row(entry, index: int) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_queued_row_style(false))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	row.add_child(hbox)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _UNIT_ICONS.get(entry.id, null)
	hbox.add_child(icon)

	var name_label := Label.new()
	name_label.text = "%d. %s" % [index, entry.id.capitalize()]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	name_label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	hbox.add_child(name_label)

	var time_label := Label.new()
	time_label.text = "%.1fs" % entry.remaining
	time_label.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	time_label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_GOLD)
	hbox.add_child(time_label)

	var cancel := Button.new()
	cancel.text = "×"
	cancel.tooltip_text = "Cancel and refund %d coin" % entry.get("cost", 0)
	cancel.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	UIThemeTokens.apply_button_theme(cancel, UIThemeTokens.ButtonVariant.DANGER)
	cancel.pressed.connect(_cancel_index.bind(index))
	hbox.add_child(cancel)

	return row


func _cancel_index(index: int) -> void:
	if _building:
		_building.call("cancel_queue", index)
		AudioManager.play("click")


func _set_empty_state() -> void:
	_active_panel.visible = false
	_progress_bar.visible = false
	_status_label.text = "No active training"
	_pause_button.disabled = true
	_clear_button.disabled = true
	_pause_button.text = "Pause"
	for row in _queued_rows:
		row.queue_free()
	_queued_rows.clear()
	_empty_label.visible = true
	_last_queue_size = 0


func _get_player_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == GameManager.Team.PLAYER:
			return b
	return null
