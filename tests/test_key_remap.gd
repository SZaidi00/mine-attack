extends GutTest

# Hotkey remapping: set_key_binding persists to settings.cfg and rebuilds the
# InputMap action events (keycode + modifiers), lmb/rmb mouse events are never
# touched, conflicts with other remappable actions are rejected by the capture
# flow, and stored bindings re-apply from apply_saved_bindings().

const ACTION := "attack_move"

var _original: Dictionary


func before_all() -> void:
	_original = SettingsManager.get_key_binding(ACTION)


func after_all() -> void:
	# Restore the default binding in settings.cfg and the InputMap.
	if not _original.is_empty():
		SettingsManager.set_key_binding(ACTION,
			int(_original["keycode"]), bool(_original["ctrl"]),
			bool(_original["alt"]), bool(_original["shift"]))


func test_set_key_binding_persists_and_applies() -> void:
	SettingsManager.set_key_binding(ACTION, KEY_Z, true, false, true)
	var binding: Dictionary = SettingsManager.get_key_binding(ACTION)
	assert_eq(int(binding["keycode"]), KEY_Z)
	assert_true(bool(binding["ctrl"]), "ctrl modifier preserved")
	assert_false(bool(binding["alt"]))
	assert_true(bool(binding["shift"]), "shift modifier preserved")

	var cfg := ConfigFile.new()
	assert_eq(cfg.load(SettingsManager.CONFIG_PATH), OK)
	var stored: Dictionary = cfg.get_value("input", ACTION, {})
	assert_eq(int(stored.get("keycode", 0)), KEY_Z, "binding persisted to settings.cfg")

	var found: bool = false
	for event in InputMap.action_get_events(ACTION):
		if event is InputEventKey:
			found = true
			assert_eq(event.keycode, KEY_Z, "InputMap rebuilt with the new keycode")
			assert_true(event.ctrl_pressed)
			assert_true(event.shift_pressed)
	assert_true(found, "InputMap has a key event for the action")


func test_only_key_events_replaced() -> void:
	SettingsManager.set_key_binding(ACTION, KEY_Z, false, false, false)
	var keys: int = 0
	for event in InputMap.action_get_events(ACTION):
		if event is InputEventKey:
			keys += 1
	assert_eq(keys, 1, "exactly one key event after remapping")


func test_mouse_button_actions_untouched() -> void:
	SettingsManager.set_key_binding(ACTION, KEY_Z, false, false, false)
	for action in ["lmb", "rmb"]:
		var events: Array = InputMap.action_get_events(action)
		assert_true(events.size() > 0, "%s has bindings" % action)
		for event in events:
			assert_true(event is InputEventMouseButton,
				"%s keeps only mouse-button events (got %s)" % [action, event])


func test_apply_saved_bindings_rebuilds_input_map() -> void:
	SettingsManager.set_key_binding(ACTION, KEY_Z, true, false, false)
	SettingsManager.apply_saved_bindings()
	var binding: Dictionary = SettingsManager.get_key_binding(ACTION)
	assert_eq(int(binding["keycode"]), KEY_Z)
	assert_true(bool(binding["ctrl"]))


func test_conflict_detection() -> void:
	# Ctrl+M is Select Miners by default.
	var conflict: Dictionary = SettingsPanel.find_binding_conflict(ACTION, KEY_M, true, false, false)
	assert_eq(conflict.get("action"), "select_miners", "Ctrl+M conflicts with Select Miners")
	var free: Dictionary = SettingsPanel.find_binding_conflict(ACTION, KEY_F9, false, false, false)
	assert_true(free.is_empty(), "an unused key has no conflict")


func test_capture_rebinds_key() -> void:
	var panel: Control = SettingsPanel.create()
	get_tree().root.add_child(panel)
	panel.visible = true
	var btn: Button = _find_bind_button(panel)
	assert_not_null(btn, "found the %s binding button" % ACTION)
	btn.emit_signal("pressed")
	assert_eq(btn.text, "Press a key…", "button entered capture mode")
	var key := InputEventKey.new()
	key.keycode = KEY_N
	key.pressed = true
	btn.emit_signal("gui_input", key)
	assert_eq(int(SettingsManager.get_key_binding(ACTION)["keycode"]), KEY_N, "capture applied the new key")
	assert_eq(btn.text, SettingsPanel.format_binding(SettingsManager.get_key_binding(ACTION)))
	panel.free()


func test_capture_rejects_conflict() -> void:
	SettingsManager.set_key_binding(ACTION, KEY_Z, false, false, false)
	var panel: Control = SettingsPanel.create()
	get_tree().root.add_child(panel)
	panel.visible = true
	var btn: Button = _find_bind_button(panel)
	btn.emit_signal("pressed")
	var key := InputEventKey.new()
	key.keycode = KEY_M
	key.ctrl_pressed = true
	key.pressed = true
	btn.emit_signal("gui_input", key)
	assert_eq(int(SettingsManager.get_key_binding(ACTION)["keycode"]), KEY_Z,
		"conflicting binding (Ctrl+M = Select Miners) not applied")
	var warning: Label = _find_conflict_warning(panel)
	assert_not_null(warning, "warning label exists")
	assert_true(warning.visible, "warning shown on conflict")
	assert_string_contains(warning.text, "Select Miners")
	panel.free()


func test_escape_cancels_capture() -> void:
	SettingsManager.set_key_binding(ACTION, KEY_Z, false, false, false)
	var panel: Control = SettingsPanel.create()
	get_tree().root.add_child(panel)
	panel.visible = true
	var btn: Button = _find_bind_button(panel)
	var before: String = btn.text
	btn.emit_signal("pressed")
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	btn.emit_signal("gui_input", key)
	assert_eq(int(SettingsManager.get_key_binding(ACTION)["keycode"]), KEY_Z, "binding unchanged")
	assert_eq(btn.text, before, "button text restored after cancel")
	panel.free()


func _find_bind_button(panel: Control) -> Button:
	var wanted: String = SettingsPanel.format_binding(SettingsManager.get_key_binding(ACTION))
	var found: Array[Button] = []
	_collect_buttons(panel, found)
	for btn in found:
		if btn.text == wanted:
			return btn
	return null


func _collect_buttons(node: Node, out: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(child)
		_collect_buttons(child, out)


func _find_conflict_warning(panel: Control) -> Label:
	var found: Array[Label] = []
	_collect_labels(panel, found)
	for label in found:
		if label.text.contains("already bound"):
			return label
	return null


func _collect_labels(node: Node, out: Array[Label]) -> void:
	for child in node.get_children():
		if child is Label:
			out.append(child)
		_collect_labels(child, out)
