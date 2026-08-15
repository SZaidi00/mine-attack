class_name HUDMenus
extends RefCounted

var hud: HUD
# Kept here (not on HUD) since only the build menu uses it.
var _trap_button: Button = null

const _ICON_LANTERN: Texture2D = preload("res://frost_mines_assets/props/lantern_t1.png")
const _ICON_MINE_LANTERN: Texture2D = preload("res://frost_mines_assets/props/lantern_underground.png")
const _ICON_TOWER: Texture2D = preload("res://frost_mines_assets/props/tower_player.png")
const _ICON_WALL: Texture2D = preload("res://frost_mines_assets/props/wall_player.png")
const _RADIAL_BUTTON_SIZE: Vector2 = Vector2(96, 74)
const _RADIAL_RADIUS: float = 150.0

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


## Radial build menu (Revamp Phase 7): the options fan out in an arc above
## the Build button instead of a list. Picking one hands placement mode to the
## PlayerController, which shows the ghost and handles confirm/cancel clicks.
func _build_build_menu() -> void:
	hud._build_menu = Control.new()
	hud._build_menu.name = "BuildMenu"
	hud._build_menu.visible = false
	hud._build_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Clicks pass through the container; only the option buttons take input.
	hud._build_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud._build_lantern_button = _add_build_option(hud._build_menu, "lantern", _ICON_LANTERN)
	hud._build_mine_lantern_button = _add_build_option(hud._build_menu, "underground_lantern", _ICON_MINE_LANTERN)
	hud._build_tower_button = _add_build_option(hud._build_menu, "tower", _ICON_TOWER)
	hud._build_wall_button = _add_build_option(hud._build_menu, "wall", _ICON_WALL)
	_trap_button = _add_build_option(hud._build_menu, "trap", null)
	hud.add_child(hud._build_menu)


func _add_build_option(parent: Control, kind: String, icon: Texture2D) -> Button:
	var btn: Button = Button.new()
	btn.custom_minimum_size = _RADIAL_BUTTON_SIZE
	btn.size = _RADIAL_BUTTON_SIZE
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color("#e2e8f0"))
	if icon != null:
		btn.icon = _scaled_icon(icon, 30)
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	btn.add_theme_stylebox_override("normal", hud._styling._make_flat_style(hud._styling._COL_BTN_NORMAL, hud._styling._COL_BTN_BORDER))
	btn.add_theme_stylebox_override("hover", hud._styling._make_flat_style(hud._styling._COL_BTN_HOVER, hud._styling._COL_BTN_HOVER_BORDER))
	btn.add_theme_stylebox_override("pressed", hud._styling._make_flat_style(hud._styling._COL_TAB_ACTIVE, hud._styling._COL_TAB_ACTIVE_BORDER))
	btn.add_theme_stylebox_override("disabled", hud._styling._make_flat_style(hud._styling._COL_BTN_DISABLED))
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
		_layout_radial_menu()


## Fans the visible options in an arc above the Build button. Re-run on every
## open (and whenever the trap option appears) so positions stay correct.
func _layout_radial_menu() -> void:
	# Apply the trap's research gate here too — _update_build_menu only runs
	# once the menu is visible, so a fresh menu would flash a stale trap.
	_trap_button.visible = ResearchManager.has_branch(GameManager.Team.PLAYER, "guerrilla")
	var options: Array[Button] = []
	for btn: Button in [hud._build_lantern_button, hud._build_mine_lantern_button, hud._build_tower_button, hud._build_wall_button, _trap_button]:
		if btn.visible:
			options.append(btn)
	var build_rect: Rect2 = hud._build_button.get_global_rect()
	var pivot: Vector2 = Vector2(build_rect.get_center().x, build_rect.position.y)
	var count: int = options.size()
	var viewport_size: Vector2 = hud.get_viewport().get_visible_rect().size
	for i in count:
		var t: float = 0.5 if count == 1 else i / float(count - 1)
		var angle: float = lerpf(deg_to_rad(-165.0), deg_to_rad(-15.0), t)
		var pos: Vector2 = pivot + Vector2(cos(angle), sin(angle)) * _RADIAL_RADIUS - _RADIAL_BUTTON_SIZE * 0.5
		pos.x = clampf(pos.x, 4.0, viewport_size.x - _RADIAL_BUTTON_SIZE.x - 4.0)
		pos.y = clampf(pos.y, 4.0, viewport_size.y - _RADIAL_BUTTON_SIZE.y - 4.0)
		options[i].position = pos


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
	# Trap (Revamp Phase 6): only offered once the Guerrilla Tactics branch is
	# researched; _update_build_menu runs every frame while the menu is open,
	# so the button appears as soon as the research completes.
	var trap_unlocked: bool = ResearchManager.has_branch(team, "guerrilla")
	if _trap_button.visible != trap_unlocked:
		_trap_button.visible = trap_unlocked
		_layout_radial_menu()
	if trap_unlocked:
		var trap_count: int = 0
		for trap in hud.get_tree().get_nodes_in_group("traps"):
			if trap.team == team:
				trap_count += 1
		_trap_button.text = "Trap\n%dg (%d/%d)" % [hud._Constants.TRAP_COST, trap_count, hud._Constants.TRAP_MAX_COUNT]
		_trap_button.disabled = trap_count >= hud._Constants.TRAP_MAX_COUNT \
			or not EconomyManager.can_afford(team, hud._Constants.TRAP_COST)
		_trap_button.tooltip_text = "Hidden spike trap: %d damage to the first enemy unit that steps on it, then consumed. Any walkable cell. Enemies cannot see it in the fog." % roundi(hud._Constants.TRAP_DAMAGE)
	# Grayed out when unaffordable or at max count (Revamp Phase 7): the
	# disabled stylebox only recolors text, so dim the whole button + icon.
	for btn: Button in [hud._build_lantern_button, hud._build_mine_lantern_button, hud._build_tower_button, hud._build_wall_button, _trap_button]:
		btn.modulate = Color(0.45, 0.45, 0.5) if btn.disabled else Color.WHITE
