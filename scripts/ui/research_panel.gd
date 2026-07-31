class_name ResearchPanel
extends PanelContainer

# Research tree panel: docked on the left edge (mirroring the training queue
# panel on the right), toggled from the BottomBar Research button / R hotkey.
# Rows are built in code from Constants.RESEARCH_TECHS so adding a tech to the
# table automatically adds a row. Player side only — the AI researches through
# AIController. One active research per team; cancel refunds 100%.

const _Constants = preload("res://scripts/autoload/constants.gd")

const _TEAM: GameManager.Team = GameManager.Team.PLAYER

const _COL_BTN_NORMAL: Color = Color("#1a2434")
const _COL_BTN_HOVER: Color = Color("#253650")
const _COL_BTN_PRESSED: Color = Color("#111927")
const _COL_BTN_DISABLED: Color = Color("#151c29")
const _COL_BTN_BORDER: Color = Color(1, 1, 1, 0.07)
const _COL_BTN_HOVER_BORDER: Color = Color("#4a86c8")
const _COL_TEXT: Color = Color("#e2e8f0")
const _COL_TEXT_DIM: Color = Color("#94a3b8")

const _TECH_ICONS: Dictionary = {
	"fortify": preload("res://frost_mines_assets/icons/icon_hp.png"),
	"ore_sonar": preload("res://frost_mines_assets/icons/icon_coin.png"),
	"bulwark": preload("res://frost_mines_assets/icons/icon_swordsman.png"),
	"longbow": preload("res://frost_mines_assets/icons/icon_archer.png"),
	"inferno": preload("res://frost_mines_assets/icons/icon_wizard.png"),
	"reinforced_pack": preload("res://frost_mines_assets/icons/icon_miner.png"),
}

var _tech_buttons: Dictionary = {}  # tech_id -> Button
var _active_label: Label
var _progress_bar: ProgressBar
var _cancel_button: Button
var _scan_button: Button


func _ready() -> void:
	_build_ui()
	ResearchManager.research_changed.connect(_on_research_changed)
	EconomyManager.coin_changed.connect(_on_economy_changed)
	_refresh()


func _process(_delta: float) -> void:
	_update_active_progress()
	_update_scan_button()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Research"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", _COL_TEXT_DIM)
	vbox.add_child(title)

	_active_label = Label.new()
	_active_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_active_label.add_theme_font_size_override("font_size", 11)
	_active_label.add_theme_color_override("font_color", _COL_TEXT)
	vbox.add_child(_active_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 14)
	_progress_bar.max_value = 1.0
	_style_progress_bar()
	vbox.add_child(_progress_bar)

	_cancel_button = Button.new()
	_cancel_button.text = "Cancel (100% refund)"
	_cancel_button.add_theme_font_size_override("font_size", 12)
	_style_button(_cancel_button)
	_cancel_button.pressed.connect(_cancel_research)
	vbox.add_child(_cancel_button)

	vbox.add_child(HSeparator.new())

	for tech_id in _Constants.RESEARCH_TECHS:
		var btn := Button.new()
		btn.icon = _TECH_ICONS.get(tech_id)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 12)
		_style_button(btn)
		btn.pressed.connect(_start_research.bind(tech_id))
		vbox.add_child(btn)
		_tech_buttons[tech_id] = btn

	vbox.add_child(HSeparator.new())

	_scan_button = Button.new()
	_scan_button.add_theme_font_size_override("font_size", 12)
	_style_button(_scan_button)
	_scan_button.pressed.connect(_scan)
	vbox.add_child(_scan_button)


func _refresh() -> void:
	var busy: bool = ResearchManager.is_researching(_TEAM)
	for tech_id in _tech_buttons:
		var btn: Button = _tech_buttons[tech_id]
		var tech: Dictionary = _Constants.RESEARCH_TECHS[tech_id]
		var level: int = ResearchManager.get_level(_TEAM, tech_id)
		var max_level: int = ResearchManager.get_max_level(tech_id)
		var next: Dictionary = ResearchManager.get_next_level_data(_TEAM, tech_id)
		if next.is_empty():
			btn.text = "%s  L%d (MAX)" % [tech.name, max_level]
			btn.disabled = true
		else:
			btn.text = "%s  L%d — %dg / %ds" % [tech.name, level + 1, next.cost, int(next.time)]
			btn.disabled = busy or not EconomyManager.can_afford(_TEAM, next.cost)
	_cancel_button.visible = busy


func _update_active_progress() -> void:
	var active: Dictionary = ResearchManager.get_active(_TEAM)
	if active.is_empty():
		_progress_bar.value = 0.0
		_active_label.text = "No active research"
		return
	var pct: float = clampf(1.0 - active.remaining / active.total, 0.0, 1.0)
	_progress_bar.value = pct
	var tech_name: String = _Constants.RESEARCH_TECHS[active.tech_id].name
	_active_label.text = "%s L%d — %d%%" % [tech_name, active.level, int(pct * 100)]


func _update_scan_button() -> void:
	var level: int = ResearchManager.get_sonar_level(_TEAM)
	if level <= 0:
		_scan_button.text = "Scan (needs Ore Sonar)"
		_scan_button.disabled = true
		return
	var cd: float = ResearchManager.get_scan_cooldown_remaining(_TEAM)
	if cd > 0.0:
		_scan_button.text = "Scan — %ds" % int(ceil(cd))
		_scan_button.disabled = true
	else:
		_scan_button.text = "Scan for Ore (L%d)" % level
		_scan_button.disabled = false


func _start_research(tech_id: String) -> void:
	if ResearchManager.start_research(_TEAM, tech_id):
		AudioManager.play("click")
	_refresh()


func _cancel_research() -> void:
	if ResearchManager.cancel_research(_TEAM):
		AudioManager.play("click")
	_refresh()


func _scan() -> void:
	if ResearchManager.scan(_TEAM) >= 0:
		AudioManager.play("click")


func _on_research_changed(_team: GameManager.Team) -> void:
	_refresh()


func _on_economy_changed(_team: GameManager.Team) -> void:
	_refresh()


func _style_button(btn: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		match state:
			"normal":
				style.bg_color = _COL_BTN_NORMAL
				style.border_color = _COL_BTN_BORDER
			"hover":
				style.bg_color = _COL_BTN_HOVER
				style.border_color = _COL_BTN_HOVER_BORDER
			"pressed":
				style.bg_color = _COL_BTN_PRESSED
				style.border_color = _COL_BTN_BORDER
			"disabled":
				style.bg_color = _COL_BTN_DISABLED
				style.border_color = _COL_BTN_BORDER
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		btn.add_theme_stylebox_override(state, style)


func _style_progress_bar() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#121a28")
	bg.set_corner_radius_all(7)
	_progress_bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#8a6d1f")
	fill.set_corner_radius_all(7)
	_progress_bar.add_theme_stylebox_override("fill", fill)
