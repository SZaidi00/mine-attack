class_name SettingsPanel
extends RefCounted

## Shared settings popup used by the main menu and the pause menu. create()
## returns a hidden full-rect Control; callers add it as a child and toggle
## `visible`. PROCESS_MODE_ALWAYS keeps it interactive while the tree is
## paused. The card body is a ScrollContainer with three groups: Display
## (map seed, UI scale, accessibility checkboxes, tutorial hints), Audio
## (SFX volume), and Controls (hotkey remapping).

const UIThemeTokens = preload("res://scripts/ui/ui_theme_tokens.gd")
const _Constants = preload("res://scripts/autoload/constants.gd")


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
	card.custom_minimum_size = Vector2(520, 0)
	card.add_theme_stylebox_override("panel", UIThemeTokens.make_metal_card_style())
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_HEADER)
	title.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	var ui_scale_row := _build_display_group(content, root)
	_build_audio_group(content)
	_build_controls_group(content, root, ui_scale_row)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(160, 40)
	close.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	UIThemeTokens.apply_button_theme(close, UIThemeTokens.ButtonVariant.SECONDARY)
	close.pressed.connect(func(): AudioManager.play("click"))
	close.pressed.connect(func(): root.visible = false)
	vbox.add_child(close)

	return root


static func _make_group(content: VBoxContainer, title: String) -> VBoxContainer:
	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	header.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_GOLD)
	content.add_child(header)
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 8)
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(group)
	return group


static func _make_check(parent: Control, text: String, initial: bool, on_toggle: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = initial
	check.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	check.add_theme_color_override("font_hover_color", Color.WHITE)
	check.add_theme_color_override("font_pressed_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	check.toggled.connect(on_toggle)
	parent.add_child(check)
	return check


# ─── Display group ───

## Returns the UI-scale slider so the visibility refresh can resync it.
static func _build_display_group(content: VBoxContainer, root: Control) -> HSlider:
	var group := _make_group(content, "DISPLAY")

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 10)
	seed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	group.add_child(seed_row)

	var seed_label := Label.new()
	seed_label.text = "Map Seed:"
	seed_label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	seed_row.add_child(seed_label)

	# Effective seed of the current/next match (rolled maps show the value the
	# map was generated from once a match has started).
	var seed_value := Label.new()
	seed_value.custom_minimum_size = Vector2(330, 0)
	seed_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	seed_value.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_GOLD)
	seed_value.text = str(GameManager.map_seed) if GameManager.map_seed >= 0 else "Random"
	root.visibility_changed.connect(func():
		seed_value.text = str(GameManager.map_seed) if GameManager.map_seed >= 0 else "Random")
	seed_row.add_child(seed_value)

	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 10)
	scale_row.alignment = BoxContainer.ALIGNMENT_CENTER
	group.add_child(scale_row)

	var scale_label := Label.new()
	scale_label.text = "UI Scale:"
	scale_label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	scale_row.add_child(scale_label)

	var scale_value := Label.new()
	scale_value.custom_minimum_size = Vector2(48, 0)
	scale_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scale_value.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_GOLD)

	var scale_slider := HSlider.new()
	scale_slider.custom_minimum_size = Vector2(270, 0)
	scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_slider.min_value = 0.75
	scale_slider.max_value = 1.5
	scale_slider.step = 0.05
	scale_slider.value = SettingsManager.get_ui_scale()
	scale_value.text = "%d%%" % roundi(scale_slider.value * 100.0)
	scale_slider.value_changed.connect(func(v: float):
		SettingsManager.set_ui_scale(v)
		scale_value.text = "%d%%" % roundi(v * 100.0))
	scale_row.add_child(scale_slider)
	scale_row.add_child(scale_value)

	_make_check(group, "Colorblind mode", SettingsManager.get_colorblind(),
		func(on: bool): SettingsManager.set_colorblind(on))
	_make_check(group, "Reduced motion (no camera shake)", SettingsManager.get_reduced_motion(),
		func(on: bool): SettingsManager.set_reduced_motion(on))
	_make_check(group, "Reduced flash (static warnings)", SettingsManager.get_reduced_flash(),
		func(on: bool): SettingsManager.set_reduced_flash(on))

	# ── Begin tutorial-hints block (keep delimited: slated for restructure) ──
	var tutorial_row := HBoxContainer.new()
	tutorial_row.add_theme_constant_override("separation", 10)
	tutorial_row.alignment = BoxContainer.ALIGNMENT_CENTER
	group.add_child(tutorial_row)

	var tutorial_check := CheckBox.new()
	tutorial_check.text = "Show tutorial hints"
	tutorial_check.button_pressed = SettingsManager.get_show_tutorial()
	tutorial_check.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	tutorial_check.add_theme_color_override("font_hover_color", Color.WHITE)
	tutorial_check.add_theme_color_override("font_pressed_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	tutorial_check.toggled.connect(func(on: bool): SettingsManager.set_show_tutorial(on))
	tutorial_row.add_child(tutorial_check)

	var tutorial_reset := Button.new()
	tutorial_reset.text = "Reset"
	tutorial_reset.tooltip_text = "Show all dismissed tutorial hints again"
	UIThemeTokens.apply_button_theme(tutorial_reset, UIThemeTokens.ButtonVariant.SECONDARY)
	tutorial_reset.pressed.connect(func():
		SettingsManager.reset_tutorial_seen()
		AudioManager.play("click"))
	tutorial_row.add_child(tutorial_reset)
	# ── End tutorial-hints block ──

	return scale_slider


# ─── Audio group ───

static func _build_audio_group(content: VBoxContainer) -> void:
	var group := _make_group(content, "AUDIO")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	group.add_child(row)

	var label := Label.new()
	label.text = "SFX Volume:"
	label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	row.add_child(label)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(44, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_GOLD)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(270, 0)
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


# ─── Controls group (hotkey remapping) ───

static func _build_controls_group(content: VBoxContainer, root: Control, ui_scale_slider: HSlider) -> void:
	var group := _make_group(content, "CONTROLS")
	var state := {"capturing": ""}
	var bind_buttons: Dictionary = {}
	var warning := Label.new()
	warning.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	warning.add_theme_color_override("font_color", UIThemeTokens.COLOR_SNOWSTORM_WARNING)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.custom_minimum_size = Vector2(460, 0)
	warning.visible = false

	for entry: Dictionary in _Constants.REMAPPABLE_ACTIONS:
		var action: String = entry["action"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		group.add_child(row)

		var label := Label.new()
		label.text = entry["label"]
		label.custom_minimum_size = Vector2(180, 0)
		label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
		row.add_child(label)

		var bind_button := Button.new()
		bind_button.text = format_binding(SettingsManager.get_key_binding(action))
		bind_button.custom_minimum_size = Vector2(170, 0)
		bind_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bind_button.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
		UIThemeTokens.apply_button_theme(bind_button, UIThemeTokens.ButtonVariant.SECONDARY)
		row.add_child(bind_button)
		bind_buttons[action] = bind_button

		bind_button.pressed.connect(func():
			if state["capturing"] != "" and state["capturing"] != action:
				var prev: Button = bind_buttons[state["capturing"]]
				prev.text = format_binding(SettingsManager.get_key_binding(state["capturing"]))
			state["capturing"] = action
			warning.visible = false
			bind_button.text = "Press a key…"
			bind_button.grab_focus()
			AudioManager.play("click"))

		bind_button.gui_input.connect(func(event: InputEvent):
			if state["capturing"] != action:
				return
			# Mouse buttons are not remappable: ignore them while capturing.
			if event is InputEventMouseButton:
				return
			if not (event is InputEventKey) or not event.pressed or event.echo:
				return
			var key := event as InputEventKey
			bind_button.accept_event()
			state["capturing"] = ""
			bind_button.release_focus()
			if key.keycode == KEY_ESCAPE and not key.ctrl_pressed and not key.alt_pressed and not key.shift_pressed:
				bind_button.text = format_binding(SettingsManager.get_key_binding(action))
				return
			var conflict: Dictionary = find_binding_conflict(action, key.keycode, key.ctrl_pressed, key.alt_pressed, key.shift_pressed)
			if not conflict.is_empty():
				warning.text = "%s is already bound to %s — rebind that action first" % [_format_key_event(key), conflict["label"]]
				warning.visible = true
				bind_button.text = format_binding(SettingsManager.get_key_binding(action))
				return
			SettingsManager.set_key_binding(action, key.keycode, key.ctrl_pressed, key.alt_pressed, key.shift_pressed)
			bind_button.text = format_binding(SettingsManager.get_key_binding(action))
			AudioManager.play("click"))

	group.add_child(warning)

	# Re-derive the displayed bindings (and UI scale) every time the panel opens.
	root.visibility_changed.connect(func():
		if not root.visible:
			return
		for action in bind_buttons:
			(bind_buttons[action] as Button).text = format_binding(SettingsManager.get_key_binding(action))
		ui_scale_slider.value = SettingsManager.get_ui_scale())


## Human-readable binding text, e.g. "Ctrl+M", "Q", "Space". "Unbound" when
## the dictionary has no keycode.
static func format_binding(binding: Dictionary) -> String:
	if binding.is_empty() or int(binding.get("keycode", 0)) == 0:
		return "Unbound"
	var parts: Array[String] = []
	if bool(binding.get("ctrl", false)):
		parts.append("Ctrl")
	if bool(binding.get("alt", false)):
		parts.append("Alt")
	if bool(binding.get("shift", false)):
		parts.append("Shift")
	parts.append(OS.get_keycode_string(int(binding["keycode"])))
	return "+".join(parts)


static func _format_key_event(key: InputEventKey) -> String:
	return format_binding({
		"keycode": key.keycode,
		"ctrl": key.ctrl_pressed,
		"alt": key.alt_pressed,
		"shift": key.shift_pressed,
	})


## First remappable action (other than `action`) already using this exact
## key+modifier combo, as its REMAPPABLE_ACTIONS entry ({"action", "label"}).
## Returns {} when the binding is free.
static func find_binding_conflict(action: String, keycode: int, ctrl: bool, alt: bool, shift: bool) -> Dictionary:
	for entry: Dictionary in _Constants.REMAPPABLE_ACTIONS:
		if entry["action"] == action:
			continue
		var other: Dictionary = SettingsManager.get_key_binding(entry["action"])
		if other.is_empty():
			continue
		if int(other.get("keycode", 0)) == keycode \
				and bool(other.get("ctrl", false)) == ctrl \
				and bool(other.get("alt", false)) == alt \
				and bool(other.get("shift", false)) == shift:
			return entry
	return {}
