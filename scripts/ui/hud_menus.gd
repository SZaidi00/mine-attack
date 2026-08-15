class_name HUDMenus
extends RefCounted

var hud: HUD
# Kept here (not on HUD) since only the build menu uses it.
var _trap_button: Button = null

const _ICON_LANTERN: Texture2D = preload("res://frost_mines_assets/props/lantern_t1.png")
const _ICON_MINE_LANTERN: Texture2D = preload("res://frost_mines_assets/props/lantern_underground.png")
const _ICON_TOWER: Texture2D = preload("res://frost_mines_assets/props/tower_player.png")
const _ICON_WALL: Texture2D = preload("res://frost_mines_assets/props/wall_player.png")
const _GRID_BUTTON_SIZE: Vector2 = Vector2(200, 110)

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


## Build menu modal (Revamp Phase 7): a centered popup panel like the
## research tree. Picking an option hands placement mode to the
## PlayerController, which shows the ghost and handles confirm/cancel clicks.
func _build_build_menu() -> void:
	hud._build_menu = Control.new()
	hud._build_menu.name = "BuildMenu"
	hud._build_menu.visible = false
	hud._build_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud._build_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	hud._build_menu.z_index = 10

	# Dim the game behind the menu; clicking the dim closes the popup.
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			hud._build_menu.visible = false
	)
	hud._build_menu.add_child(dim)

	# Centered card, styled like the research-tree panel.
	var card := PanelContainer.new()
	card.name = "BuildMenuCard"
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(720, 420)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	hud._styling._style_panel(card)
	hud._build_menu.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)
	var title := Label.new()
	title.text = "Build"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#e2e8f0"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.add_theme_font_size_override("font_size", 12)
	close_button.add_theme_stylebox_override("normal", hud._styling._make_flat_style(hud._styling._COL_BTN_NORMAL, hud._styling._COL_BTN_BORDER))
	close_button.add_theme_stylebox_override("hover", hud._styling._make_flat_style(hud._styling._COL_BTN_HOVER, hud._styling._COL_BTN_HOVER_BORDER))
	close_button.add_theme_stylebox_override("pressed", hud._styling._make_flat_style(hud._styling._COL_BTN_PRESSED, hud._styling._COL_BTN_BORDER))
	close_button.pressed.connect(func() -> void: hud._build_menu.visible = false)
	header.add_child(close_button)

	var grid := GridContainer.new()
	grid.name = "BuildMenuGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)

	hud._build_lantern_button = _add_build_option(grid, "lantern", _ICON_LANTERN)
	hud._build_mine_lantern_button = _add_build_option(grid, "underground_lantern", _ICON_MINE_LANTERN)
	hud._build_tower_button = _add_build_option(grid, "tower", _ICON_TOWER)
	hud._build_wall_button = _add_build_option(grid, "wall", _ICON_WALL)
	_trap_button = _add_build_option(grid, "trap", null)
	hud._build_pigeon_button = _add_build_option(grid, "pigeon", null)

	hud.add_child(hud._build_menu)


func _add_build_option(parent: Control, kind: String, icon: Texture2D) -> Button:
	var btn: Button = Button.new()
	btn.custom_minimum_size = _GRID_BUTTON_SIZE
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color("#e2e8f0"))
	if icon != null:
		btn.icon = _scaled_icon(icon, 40)
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	btn.add_theme_stylebox_override("normal", hud._styling._make_flat_style(hud._styling._COL_BTN_NORMAL, hud._styling._COL_BTN_BORDER, 8, 8))
	btn.add_theme_stylebox_override("hover", hud._styling._make_flat_style(hud._styling._COL_BTN_HOVER, hud._styling._COL_BTN_HOVER_BORDER, 8, 8))
	btn.add_theme_stylebox_override("pressed", hud._styling._make_flat_style(hud._styling._COL_TAB_ACTIVE, hud._styling._COL_TAB_ACTIVE_BORDER, 8, 8))
	btn.add_theme_stylebox_override("disabled", hud._styling._make_flat_style(hud._styling._COL_BTN_DISABLED, Color(0, 0, 0, 0), 8, 8))
	btn.pressed.connect(func(): AudioManager.play("click"))
	btn.pressed.connect(_on_build_option.bind(kind))
	parent.add_child(btn)
	return btn


## Pixel-art prop sprites are authored up to 48×72; shrink them to a
## menu-friendly height with nearest-neighbor so they stay crisp.
func _scaled_icon(texture: Texture2D, max_height: int) -> ImageTexture:
	var img: Image = texture.get_image()
	var scale: float = max_height / float(img.get_height())
	img.resize(maxi(1, roundi(img.get_width() * scale)), max_height, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


func _toggle_build_menu() -> void:
	hud._build_menu.visible = not hud._build_menu.visible
	if hud._build_menu.visible:
		_update_build_menu()


func _on_build_option(kind: String) -> void:
	hud._build_menu.visible = false
	var pc: PlayerController = hud._get_player_controller()
	if pc == null:
		return
	if kind == "pigeon":
		pc.train_unit("pigeon")
	else:
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
	hud._build_lantern_button.text = "Lantern\n%dg (%d/%d)" % [surface_cost, surface_count, hud._Constants.LANTERN_MAX_COUNT]
	hud._build_lantern_button.disabled = surface_count >= hud._Constants.LANTERN_MAX_COUNT \
		or not EconomyManager.can_afford(team, surface_cost)
	hud._build_lantern_button.tooltip_text = "Static surface light: %d-cell vision. Click, then left-click a surface cell on your half (right-click cancels). Place on an existing lantern to upgrade it (T2 %dg, T3 %dg)." % [hud._Constants.LANTERN_T1_VISION, hud._Constants.LANTERN_T2_COST, hud._Constants.LANTERN_T3_COST]
	var ug_cost: int = Lantern.cost_for(true, 1)
	hud._build_mine_lantern_button.text = "Mine\n%dg (%d/%d)" % [ug_cost, underground_count, hud._Constants.UNDERGROUND_LANTERN_MAX_COUNT]
	hud._build_mine_lantern_button.disabled = underground_count >= hud._Constants.UNDERGROUND_LANTERN_MAX_COUNT \
		or not EconomyManager.can_afford(team, ug_cost)
	hud._build_mine_lantern_button.tooltip_text = "Underground light: %d-cell vision, permanently reveals buried ore in its radius. Must be placed in a dug-out tunnel cell on your half." % hud._Constants.UNDERGROUND_LANTERN_VISION
	var tower_count: int = 0
	for tower in hud.get_tree().get_nodes_in_group("towers"):
		if tower.team == team:
			tower_count += 1
	var tower_cost: int = FactionManager.get_tower_cost(team)
	# Siege Master (Revamp Phase 6): display the actual discounted cost.
	if ResearchManager.has_branch(team, "siege_master"):
		tower_cost = roundi(tower_cost * hud._Constants.SIEGE_MASTER_TOWER_COST_MULT)
	hud._build_tower_button.text = "Tower\n%dg (%d/%d)" % [tower_cost, tower_count, hud._Constants.TOWER_MAX_COUNT]
	hud._build_tower_button.disabled = tower_count >= hud._Constants.TOWER_MAX_COUNT \
		or not EconomyManager.can_afford(team, tower_cost)
	hud._build_tower_button.tooltip_text = "Static defense: shoots enemies within %d cells (fighters first), doubles as a %d-cell vision source. Surface only, on your half, away from buildings and the mine entry." % [hud._Constants.TOWER_RANGE_CELLS, hud._Constants.TOWER_VISION]
	var wall_count: int = 0
	for wall in hud.get_tree().get_nodes_in_group("walls"):
		if wall.team == team:
			wall_count += 1
	var wall_cost: int = FactionManager.get_wall_cost(team)
	var wall_max: int = FactionManager.get_wall_max_count(team)
	hud._build_wall_button.text = "Wall\n%dg (%d/%d)" % [wall_cost, wall_count, wall_max]
	hud._build_wall_button.disabled = wall_count >= wall_max \
		or not EconomyManager.can_afford(team, wall_cost)
	hud._build_wall_button.tooltip_text = "A barrier segment that blocks movement and projectiles (%d HP). Surface only, on your half." % hud._Constants.PLACED_WALL_HP
	# Trap (Revamp Phase 6): shown locked until Guerrilla Tactics is researched.
	var trap_unlocked: bool = ResearchManager.has_branch(team, "guerrilla")
	if not trap_unlocked:
		_trap_button.text = "Trap\n(locked)"
		_trap_button.disabled = true
		_trap_button.tooltip_text = "Research Guerrilla Tactics to unlock traps"
	else:
		var trap_count: int = 0
		for trap in hud.get_tree().get_nodes_in_group("traps"):
			if trap.team == team:
				trap_count += 1
		_trap_button.text = "Trap\n%dg (%d/%d)" % [hud._Constants.TRAP_COST, trap_count, hud._Constants.TRAP_MAX_COUNT]
		_trap_button.disabled = trap_count >= hud._Constants.TRAP_MAX_COUNT \
			or not EconomyManager.can_afford(team, hud._Constants.TRAP_COST)
		_trap_button.tooltip_text = "Hidden spike trap: %d damage to the first enemy unit that steps on it, then consumed. Any walkable cell. Enemies cannot see it in the fog." % roundi(hud._Constants.TRAP_DAMAGE)
	# Pigeon scout: trained from sentry towers.
	var pigeon_count: int = _count_team_pigeons()
	var pigeon_cost: int = FactionManager.get_unit_cost(team, "pigeon")
	var has_tower: bool = _player_has_built_tower()
	hud._build_pigeon_button.text = "Pigeon\n%dg (%d/%d)" % [pigeon_cost, pigeon_count, hud._Constants.PIGEON_MAX_COUNT]
	hud._build_pigeon_button.disabled = not has_tower or pigeon_count >= hud._Constants.PIGEON_MAX_COUNT \
		or not EconomyManager.can_afford(team, pigeon_cost) \
		or not EconomyManager.can_add_population(team, 1)
	if not has_tower:
		hud._build_pigeon_button.tooltip_text = "Requires a built sentry tower to train pigeons"
	elif pigeon_count >= hud._Constants.PIGEON_MAX_COUNT:
		hud._build_pigeon_button.tooltip_text = "Max pigeon scouts reached (%d)" % hud._Constants.PIGEON_MAX_COUNT
	elif hud._build_pigeon_button.disabled:
		hud._build_pigeon_button.tooltip_text = "Not enough coin or population cap reached"
	else:
		hud._build_pigeon_button.tooltip_text = "Flying scout trained at a sentry tower. Auto-patrols the enemy side and returns. Only archers, wizards, dragons, and towers can shoot it."
	# Grayed out when unaffordable or at max count (Revamp Phase 7): the
	# disabled stylebox only recolors text, so dim the whole button + icon.
	for btn: Button in [hud._build_lantern_button, hud._build_mine_lantern_button, hud._build_tower_button, hud._build_wall_button, _trap_button, hud._build_pigeon_button]:
		btn.modulate = Color(0.45, 0.45, 0.5) if btn.disabled else Color.WHITE


func _count_team_pigeons() -> int:
	var n: int = 0
	var team: GameManager.Team = GameManager.Team.PLAYER
	for u in hud.get_tree().get_nodes_in_group("units"):
		if u.team == team and u.data != null and u.data.is_scout and u.get("_state") != null and u.get("_state") != Unit.State.DEAD:
			n += 1
	for tower in hud.get_tree().get_nodes_in_group("towers"):
		if tower.team == team:
			n += tower.call("get_pigeon_queue_count")
	return n


func _player_has_built_tower() -> bool:
	for tower in hud.get_tree().get_nodes_in_group("towers"):
		if tower.team == GameManager.Team.PLAYER and tower.is_built():
			return true
	return false
