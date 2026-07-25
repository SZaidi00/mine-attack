extends Control

## Minimal main menu (Phase 7.3): title, difficulty select, Play / Quit.
## Polish (background art, audio) is Phase 8 territory.

const _PANEL_BG: Texture2D = preload("res://frost_mines_assets/ui/panel_background.png")
const _BUTTON_NORMAL: Texture2D = preload("res://frost_mines_assets/ui/button_normal.png")
const _BUTTON_HOVER: Texture2D = preload("res://frost_mines_assets/ui/button_hover.png")
const _BUTTON_PRESSED: Texture2D = preload("res://frost_mines_assets/ui/button_pressed.png")

var _difficulty_option: OptionButton


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg: ColorRect = ColorRect.new()
	bg.color = Color("#0f172a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var title: Label = Label.new()
	title.text = "MINEATTACK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color("#e2e8f0"))
	vbox.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "Frost Mines"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color("#94a3b8"))
	vbox.add_child(subtitle)

	var diff_row: HBoxContainer = HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	var diff_label: Label = Label.new()
	diff_label.text = "Difficulty:"
	diff_label.add_theme_color_override("font_color", Color("#e2e8f0"))
	diff_row.add_child(diff_label)
	_difficulty_option = OptionButton.new()
	_difficulty_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for diff_name in GameManager.Difficulty.keys():
		_difficulty_option.add_item(diff_name.capitalize())
	_difficulty_option.selected = GameManager.difficulty
	diff_row.add_child(_difficulty_option)
	vbox.add_child(diff_row)

	_add_menu_button(vbox, "Play", _on_play)
	_add_menu_button(vbox, "Quit", func(): get_tree().quit())


func _add_menu_button(parent: Control, text: String, callback: Callable) -> void:
	var btn: Button = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(220, 44)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color("#e2e8f0"))
	btn.add_theme_stylebox_override("normal", _make_textured_style(_BUTTON_NORMAL))
	btn.add_theme_stylebox_override("hover", _make_textured_style(_BUTTON_HOVER))
	btn.add_theme_stylebox_override("pressed", _make_textured_style(_BUTTON_PRESSED))
	btn.pressed.connect(func(): AudioManager.play("click"))
	btn.pressed.connect(callback)
	parent.add_child(btn)


func _make_textured_style(texture: Texture2D) -> StyleBoxTexture:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = texture
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	return style


func _on_play() -> void:
	GameManager.set_difficulty(_difficulty_option.selected as GameManager.Difficulty)
	get_tree().change_scene_to_file("res://scenes/main.tscn")
