class_name HUDMenus
extends RefCounted

var hud: HUD

func _init(h: HUD) -> void:
	hud = h


## Full-screen dim pause menu: resume / restart / quit + difficulty and
## resolution selectors (both functional — they apply immediately).
func _build_pause_menu() -> void:
	hud._pause_panel = PanelContainer.new()
	hud._pause_panel.name = "PauseMenu"
	hud._pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	hud._pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud._pause_panel.visible = false
	var dim: StyleBoxFlat = StyleBoxFlat.new()
	dim.bg_color = Color(0.02, 0.03, 0.06, 0.75)
	hud._pause_panel.add_theme_stylebox_override("panel", dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud._pause_panel.add_child(center)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	center.add_child(vbox)

	var title: Label = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	_add_pause_button(vbox, "Resume", func(): hud.get_tree().paused = false)
	_add_pause_button(vbox, "Restart", hud._on_pause_restart)
	_add_pause_button(vbox, "Quit to Menu", hud._quit_to_menu)

	var diff_row: HBoxContainer = HBoxContainer.new()
	var diff_label: Label = Label.new()
	diff_label.text = "Difficulty:"
	diff_row.add_child(diff_label)
	var diff_option: OptionButton = OptionButton.new()
	diff_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for diff_name in GameManager.Difficulty.keys():
		diff_option.add_item(diff_name.capitalize())
	diff_option.selected = GameManager.difficulty
	diff_option.item_selected.connect(func(index: int): GameManager.set_difficulty(index))
	diff_row.add_child(diff_option)
	vbox.add_child(diff_row)

	if SettingsManager.is_supported():
		var res_row: HBoxContainer = HBoxContainer.new()
		var res_label: Label = Label.new()
		res_label.text = "Resolution:"
		res_row.add_child(res_label)
		var res_option: OptionButton = OptionButton.new()
		res_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var available: Array[Vector2i] = SettingsManager.get_available_resolutions()
		var current_res: Vector2i = SettingsManager.get_resolution()
		if current_res not in available:
			available.append(current_res)  # Show the actual size (e.g. manually resized window).
		for res in available:
			res_option.add_item("%d × %d" % [res.x, res.y])
			if res == current_res:
				res_option.selected = res_option.item_count - 1
		res_option.item_selected.connect(func(index: int): SettingsManager.set_resolution(available[index]))
		res_row.add_child(res_option)
		vbox.add_child(res_row)

	hud.add_child(hud._pause_panel)


func _add_pause_button(parent: Control, text: String, callback: Callable) -> void:
	var btn: Button = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(180, 36)
	btn.pressed.connect(func(): AudioManager.play("click"))
	btn.pressed.connect(callback)
	parent.add_child(btn)


## Small popup above the bottom bar with the lantern build options (Revamp
## Phase 1). Picking one hands placement mode to the PlayerController, which
## shows the ghost and handles confirm/cancel clicks.
func _build_build_menu() -> void:
	hud._build_menu = PanelContainer.new()
	hud._build_menu.name = "BuildMenu"
	hud._build_menu.visible = false
	hud._styling._style_panel(hud._build_menu)
	hud._build_menu.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hud._build_menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud._build_menu.position = Vector2(280, -100)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	hud._build_menu.add_child(vbox)
	hud._build_lantern_button = _add_build_option(vbox, "lantern")
	hud._build_mine_lantern_button = _add_build_option(vbox, "underground_lantern")
	hud._build_tower_button = _add_build_option(vbox, "tower")
	hud._build_wall_button = _add_build_option(vbox, "wall")
	hud.add_child(hud._build_menu)


func _add_build_option(parent: Control, kind: String) -> Button:
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(220, 44)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", Color("#e2e8f0"))
	btn.add_theme_stylebox_override("normal", hud._styling._make_flat_style(hud._styling._COL_BTN_NORMAL, hud._styling._COL_BTN_BORDER))
	btn.add_theme_stylebox_override("hover", hud._styling._make_flat_style(hud._styling._COL_BTN_HOVER, hud._styling._COL_BTN_HOVER_BORDER))
	btn.add_theme_stylebox_override("pressed", hud._styling._make_flat_style(hud._styling._COL_TAB_ACTIVE, hud._styling._COL_TAB_ACTIVE_BORDER))
	btn.add_theme_stylebox_override("disabled", hud._styling._make_flat_style(hud._styling._COL_BTN_DISABLED))
	btn.pressed.connect(func(): AudioManager.play("click"))
	btn.pressed.connect(hud._on_build_option.bind(kind))
	parent.add_child(btn)
	return btn


func _toggle_build_menu() -> void:
	hud._build_menu.visible = not hud._build_menu.visible


func _on_build_option(kind: String) -> void:
	hud._build_menu.visible = false
	var pc: PlayerController = hud._get_player_controller()
	if pc:
		pc.start_build_placement(kind)


func _update_build_menu() -> void:
	var team: GameManager.Team = GameManager.Team.PLAYER
	var surface_count: int = 0
	var underground_count: int = 0
	for lantern in hud.get_tree().get_nodes_in_group("lanterns"):
		if lantern.team != team:
			continue
		if lantern.is_underground_lantern:
			underground_count += 1
		else:
			surface_count += 1
	var surface_cost: int = Lantern.cost_for(false, 1)
	hud._build_lantern_button.text = "Lantern — %dg (%d/%d)" % [surface_cost, surface_count, hud._Constants.LANTERN_MAX_COUNT]
	hud._build_lantern_button.disabled = surface_count >= hud._Constants.LANTERN_MAX_COUNT \
		or not EconomyManager.can_afford(team, surface_cost)
	hud._build_lantern_button.tooltip_text = "Static surface light: %d-cell vision. Click, then left-click a surface cell on your half (right-click cancels). Place on an existing lantern to upgrade it (T2 %dg, T3 %dg)." % [hud._Constants.LANTERN_T1_VISION, hud._Constants.LANTERN_T2_COST, hud._Constants.LANTERN_T3_COST]
	var ug_cost: int = Lantern.cost_for(true, 1)
	hud._build_mine_lantern_button.text = "Mine Lantern — %dg (%d/%d)" % [ug_cost, underground_count, hud._Constants.UNDERGROUND_LANTERN_MAX_COUNT]
	hud._build_mine_lantern_button.disabled = underground_count >= hud._Constants.UNDERGROUND_LANTERN_MAX_COUNT \
		or not EconomyManager.can_afford(team, ug_cost)
	hud._build_mine_lantern_button.tooltip_text = "Underground light: %d-cell vision, permanently reveals buried ore in its radius. Must be placed in a dug-out tunnel cell on your half." % hud._Constants.UNDERGROUND_LANTERN_VISION
	var tower_count: int = 0
	for tower in hud.get_tree().get_nodes_in_group("towers"):
		if tower.team == team:
			tower_count += 1
	var tower_cost: int = FactionManager.get_tower_cost(team)
	hud._build_tower_button.text = "Sentry Tower — %dg (%d/%d)" % [tower_cost, tower_count, hud._Constants.TOWER_MAX_COUNT]
	hud._build_tower_button.disabled = tower_count >= hud._Constants.TOWER_MAX_COUNT \
		or not EconomyManager.can_afford(team, tower_cost)
	hud._build_tower_button.tooltip_text = "Static defense: shoots enemies within %d cells (fighters first), doubles as a %d-cell vision source. Surface only, on your half, away from buildings and the mine entry." % [hud._Constants.TOWER_RANGE_CELLS, hud._Constants.TOWER_VISION]
	var wall_count: int = 0
	for wall in hud.get_tree().get_nodes_in_group("walls"):
		if wall.team == team:
			wall_count += 1
	var wall_cost: int = FactionManager.get_wall_cost(team)
	var wall_max: int = FactionManager.get_wall_max_count(team)
	hud._build_wall_button.text = "Wall — %dg (%d/%d)" % [wall_cost, wall_count, wall_max]
	hud._build_wall_button.disabled = wall_count >= wall_max \
		or not EconomyManager.can_afford(team, wall_cost)
	hud._build_wall_button.tooltip_text = "A barrier segment that blocks movement and projectiles (%d HP). Surface only, on your half." % hud._Constants.PLACED_WALL_HP
