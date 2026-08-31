class_name SettingsPanel
extends RefCounted

## Shared settings popup (SFX volume slider) used by the main menu and the
## pause menu. create() returns a hidden full-rect Control; callers add it as
## a child and toggle `visible`. PROCESS_MODE_ALWAYS keeps it interactive
## while the tree is paused.

const UIThemeTokens = preload("res://scripts/ui/ui_theme_tokens.gd")


static func create() -> Control:
	var root := Control.new()
	root.name = "SettingsPanel"
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			root.visible = false)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(420, 0)
	card.add_theme_stylebox_override("panel", UIThemeTokens.make_metal_card_style())
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_HEADER)
	title.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	vbox.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)

	var label := Label.new()
	label.text = "SFX Volume:"
	label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	row.add_child(label)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(44, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_GOLD)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(180, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = SettingsManager.get_sfx_volume() * 100.0
	value_label.text = "%d%%" % roundi(slider.value)
	slider.value_changed.connect(func(v: float):
		SettingsManager.set_sfx_volume(v / 100.0)
		value_label.text = "%d%%" % roundi(v))
	slider.drag_ended.connect(func(_value_changed: bool): AudioManager.play("coin"))
	row.add_child(slider)
	row.add_child(value_label)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(160, 40)
	close.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	UIThemeTokens.apply_button_theme(close, UIThemeTokens.ButtonVariant.SECONDARY)
	close.pressed.connect(func(): AudioManager.play("click"))
	close.pressed.connect(func(): root.visible = false)
	vbox.add_child(close)

	return root
