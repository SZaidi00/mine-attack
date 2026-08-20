class_name HUDMenus
extends RefCounted

const UIThemeTokens = preload("res://scripts/ui/ui_theme_tokens.gd")

var hud: HUD

const _ICON_LANTERN: Texture2D = preload("res://frost_mines_assets/icons/button_build_lantern.png")
const _ICON_MINE_LANTERN: Texture2D = preload("res://frost_mines_assets/props/lantern_underground.png")
const _ICON_TOWER: Texture2D = preload("res://frost_mines_assets/icons/button_build_tower.png")
const _ICON_WALL: Texture2D = preload("res://frost_mines_assets/icons/button_build_wall.png")
const _ICON_COIN: Texture2D = preload("res://frost_mines_assets/icons/icon_coin.png")

const _CARD_SIZE: Vector2 = Vector2(220, 110)
const _ICON_SIZE: int = 42
const _COIN_SIZE: int = 12

enum _CardState { AVAILABLE, UNAFFORDABLE, CAPPED, LOCKED }


class _BuildCard:
	extends RefCounted
	var kind: String
	var display_name: String
	var button: Button
	var icon_rect: TextureRect
	var glyph_label: Label
	var name_label: Label
	var cost_row: HBoxContainer
	var cost_icon: TextureRect
	var cost_label: Label
	var count_label: Label


var _build_cards: Array[_BuildCard] = []
var _selected_kind: String = ""
var _dim: ColorRect = null


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
	var dim: StyleBoxFlat = UIThemeTokens.make_panel_style(Color(0.02, 0.03, 0.06, 0.75), Color(0.0, 0.0, 0.0, 0.0))
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
	title.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
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
	btn.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	UIThemeTokens.apply_button_theme(btn, UIThemeTokens.ButtonVariant.SECONDARY)
	btn.pressed.connect(func(): AudioManager.play("click"))
	btn.pressed.connect(callback)
	parent.add_child(btn)


## Build menu (Revamp Phase 5 — Blueprint Tray): a frosted-steel tray of
## compact blueprint cards. Picking a structure keeps the tray open and
## highlights the selected card while the PlayerController ghost handles
## placement. Pigeons train immediately and close the tray.
func _build_build_menu() -> void:
	hud._build_menu = Control.new()
	hud._build_menu.name = "BuildMenu"
	hud._build_menu.visible = false
	hud._build_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud._build_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	hud._build_menu.z_index = 10

	# Dim the game behind the tray; clicking the dim closes the popup.
	_dim = ColorRect.new()
	_dim.name = "BuildMenuDim"
	_dim.color = Color(0.02, 0.03, 0.06, 0.75)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(_on_dim_clicked)
	hud._build_menu.add_child(_dim)

	# Bottom-centered blueprint tray.
	var tray := PanelContainer.new()
	tray.name = "BuildTray"
	tray.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tray.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tray.position = Vector2(0, -120)
	tray.custom_minimum_size = Vector2(1000, 260)
	tray.mouse_filter = Control.MOUSE_FILTER_STOP
	tray.add_theme_stylebox_override("panel", UIThemeTokens.make_panel_style())
	hud._build_menu.add_child(tray)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	tray.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)

	var eyebrow := Label.new()
	eyebrow.text = "Construction"
	eyebrow.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	eyebrow.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_GOLD)
	title_box.add_child(eyebrow)

	var title := Label.new()
	title.text = "Blueprint Tray"
	title.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_HEADER)
	title.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	title_box.add_child(title)

	var hint := Label.new()
	hint.text = "ESC / Right-click to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	hint.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(hint)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	UIThemeTokens.apply_button_theme(close_button, UIThemeTokens.ButtonVariant.SECONDARY)
	close_button.pressed.connect(_close_build_menu)
	header.add_child(close_button)

	var grid := GridContainer.new()
	grid.name = "BuildMenuGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)

	_build_cards.clear()
	_build_cards.append(_add_build_card(grid, "lantern", "Lantern", _ICON_LANTERN))
	_build_cards.append(_add_build_card(grid, "underground_lantern", "Mine Lantern", _ICON_MINE_LANTERN))
	_build_cards.append(_add_build_card(grid, "tower", "Tower", _ICON_TOWER))
	_build_cards.append(_add_build_card(grid, "wall", "Wall", _ICON_WALL))
	_build_cards.append(_add_build_card(grid, "trap", "Trap", null, "◇"))
	_build_cards.append(_add_build_card(grid, "pigeon", "Pigeon", null, "↗"))

	var footer := Label.new()
	footer.text = "Select a blueprint to place"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	footer.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_DIM)
	vbox.add_child(footer)

	hud.add_child(hud._build_menu)

	# Prime the first paint so styles and counts are valid before the menu opens.
	_update_build_menu()


func _add_build_card(parent: Control, kind: String, display_name: String, texture: Texture2D, glyph: String = "") -> _BuildCard:
	var card := _BuildCard.new()
	card.kind = kind
	card.display_name = display_name

	var btn: Button = Button.new()
	btn.custom_minimum_size = _CARD_SIZE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(_on_build_card_pressed.bind(card))
	btn.pressed.connect(func(): AudioManager.play("click"))
	card.button = btn

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 4)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.add_child(content)

	if texture != null:
		var icon: TextureRect = TextureRect.new()
		icon.texture = _scaled_icon(texture, _ICON_SIZE)
		icon.custom_minimum_size = Vector2(_ICON_SIZE, _ICON_SIZE)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_FIT_HEIGHT
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.icon_rect = icon
		content.add_child(icon)
	else:
		var glyph_label: Label = Label.new()
		glyph_label.text = glyph
		glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph_label.custom_minimum_size = Vector2(_ICON_SIZE, _ICON_SIZE)
		glyph_label.add_theme_font_size_override("font_size", 28)
		glyph_label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_GOLD)
		glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.glyph_label = glyph_label
		content.add_child(glyph_label)

	var name_label: Label = Label.new()
	name_label.text = display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.name_label = name_label
	content.add_child(name_label)

	var cost_row: HBoxContainer = HBoxContainer.new()
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_row.add_theme_constant_override("separation", 4)
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.cost_row = cost_row
	content.add_child(cost_row)

	var coin: TextureRect = TextureRect.new()
	coin.texture = _ICON_COIN
	coin.custom_minimum_size = Vector2(_COIN_SIZE, _COIN_SIZE)
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.expand_mode = TextureRect.EXPAND_FIT_HEIGHT
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.cost_icon = coin
	cost_row.add_child(coin)

	var cost_label: Label = Label.new()
	cost_label.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.cost_label = cost_label
	cost_row.add_child(cost_label)

	var count_label: Label = Label.new()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_label.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.count_label = count_label
	cost_row.add_child(count_label)

	_apply_card_style(card, _CardState.AVAILABLE, false)
	parent.add_child(btn)
	return card


func _on_build_card_pressed(card: _BuildCard) -> void:
	if card.button.disabled:
		return
	var pc: PlayerController = hud._get_player_controller()
	if pc == null:
		return
	if card.kind == "pigeon":
		pc.train_unit("pigeon")
		_close_build_menu()
		return
	pc.start_build_placement(card.kind)
	_selected_kind = card.kind
	_set_menu_for_placement(true)


func _set_menu_for_placement(active: bool) -> void:
	if hud._build_menu == null:
		return
	if active:
		if _dim != null:
			_dim.visible = false
		hud._build_menu.mouse_filter = Control.MOUSE_FILTER_PASS
	else:
		if _dim != null:
			_dim.visible = true
		hud._build_menu.mouse_filter = Control.MOUSE_FILTER_STOP


func _on_dim_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_build_menu()


func close_build_menu() -> void:
	_close_build_menu()


func _close_build_menu() -> void:
	if _selected_kind != "":
		var pc: PlayerController = hud._get_player_controller()
		if pc != null:
			pc.cancel_build_mode()
		_selected_kind = ""
		_set_menu_for_placement(false)
	if hud._build_menu != null:
		hud._build_menu.visible = false


func _toggle_build_menu() -> void:
	if hud._build_menu.visible:
		_close_build_menu()
	else:
		_selected_kind = ""
		_set_menu_for_placement(false)
		hud._build_menu.visible = true
		_update_build_menu()


func is_menu_in_placement_mode() -> bool:
	return _selected_kind != ""


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

	var tower_count: int = 0
	for tower in hud.get_tree().get_nodes_in_group("towers"):
		if tower.team == team:
			tower_count += 1

	var wall_count: int = 0
	for wall in hud.get_tree().get_nodes_in_group("walls"):
		if wall.team == team:
			wall_count += 1

	var trap_count: int = 0
	var trap_unlocked: bool = ResearchManager.has_branch(team, "guerrilla")
	if trap_unlocked:
		for trap in hud.get_tree().get_nodes_in_group("traps"):
			if trap.team == team:
				trap_count += 1

	var pigeon_count: int = _count_team_pigeons()
	var pigeon_cost: int = FactionManager.get_unit_cost(team, "pigeon")
	var has_tower: bool = _player_has_built_tower()

	for card in _build_cards:
		var state: _CardState
		var cost: int = 0
		var count: int = 0
		var max_count: int = 0
		var can_afford := true
		var tooltip := ""

		match card.kind:
			"lantern":
				cost = Lantern.cost_for(false, 1)
				count = surface_count
				max_count = hud._Constants.LANTERN_MAX_COUNT
				can_afford = EconomyManager.can_afford(team, cost)
				tooltip = "Static surface light: %d-cell vision. Click, then left-click a surface cell on your half (right-click cancels). Place on an existing lantern to upgrade it (T2 %dg, T3 %dg)." % [hud._Constants.LANTERN_T1_VISION, hud._Constants.LANTERN_T2_COST, hud._Constants.LANTERN_T3_COST]
				if count >= max_count:
					state = _CardState.CAPPED
				elif not can_afford:
					state = _CardState.UNAFFORDABLE
				else:
					state = _CardState.AVAILABLE
			"underground_lantern":
				cost = Lantern.cost_for(true, 1)
				count = underground_count
				max_count = hud._Constants.UNDERGROUND_LANTERN_MAX_COUNT
				can_afford = EconomyManager.can_afford(team, cost)
				tooltip = "Underground light: %d-cell vision, permanently reveals buried ore in its radius. Must be placed in a dug-out tunnel cell on your half." % hud._Constants.UNDERGROUND_LANTERN_VISION
				if count >= max_count:
					state = _CardState.CAPPED
				elif not can_afford:
					state = _CardState.UNAFFORDABLE
				else:
					state = _CardState.AVAILABLE
			"tower":
				cost = FactionManager.get_tower_cost(team)
				if ResearchManager.has_branch(team, "siege_master"):
					cost = roundi(cost * hud._Constants.SIEGE_MASTER_TOWER_COST_MULT)
				count = tower_count
				max_count = hud._Constants.TOWER_MAX_COUNT
				can_afford = EconomyManager.can_afford(team, cost)
				tooltip = "Static defense: shoots enemies within %d cells (fighters first), doubles as a %d-cell vision source. Surface only, on your half, away from buildings and the mine entry." % [hud._Constants.TOWER_RANGE_CELLS, hud._Constants.TOWER_VISION]
				if count >= max_count:
					state = _CardState.CAPPED
				elif not can_afford:
					state = _CardState.UNAFFORDABLE
				else:
					state = _CardState.AVAILABLE
			"wall":
				cost = FactionManager.get_wall_cost(team)
				max_count = FactionManager.get_wall_max_count(team)
				count = wall_count
				can_afford = EconomyManager.can_afford(team, cost)
				tooltip = "A barrier segment that blocks movement and projectiles (%d HP). Surface only, on your half." % hud._Constants.PLACED_WALL_HP
				if count >= max_count:
					state = _CardState.CAPPED
				elif not can_afford:
					state = _CardState.UNAFFORDABLE
				else:
					state = _CardState.AVAILABLE
			"trap":
				if not trap_unlocked:
					state = _CardState.LOCKED
					tooltip = "Research Guerrilla Tactics to unlock traps"
				else:
					cost = hud._Constants.TRAP_COST
					count = trap_count
					max_count = hud._Constants.TRAP_MAX_COUNT
					can_afford = EconomyManager.can_afford(team, cost)
					tooltip = "Hidden spike trap: %d damage to the first enemy unit that steps on it, then consumed. Any walkable cell. Enemies cannot see it in the fog." % roundi(hud._Constants.TRAP_DAMAGE)
					if count >= max_count:
						state = _CardState.CAPPED
					elif not can_afford:
						state = _CardState.UNAFFORDABLE
					else:
						state = _CardState.AVAILABLE
			"pigeon":
				count = pigeon_count
				max_count = hud._Constants.PIGEON_MAX_COUNT
				if not has_tower:
					state = _CardState.LOCKED
					tooltip = "Requires a built sentry tower to train pigeons"
				else:
					cost = pigeon_cost
					can_afford = EconomyManager.can_afford(team, cost) and EconomyManager.can_add_population(team, 1)
					if count >= max_count:
						state = _CardState.CAPPED
						tooltip = "Max pigeon scouts reached (%d)" % max_count
					elif not can_afford:
						state = _CardState.UNAFFORDABLE
						tooltip = "Not enough coin or population cap reached"
					else:
						state = _CardState.AVAILABLE
						tooltip = "Flying scout trained at a sentry tower. Auto-patrols the enemy side and returns. Only archers, wizards, dragons, and towers can shoot it."

		var selected := card.kind == _selected_kind
		_apply_card_style(card, state, selected)
		card.button.disabled = state != _CardState.AVAILABLE

		card.name_label.text = card.display_name
		card.name_label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY if state == _CardState.AVAILABLE else UIThemeTokens.COLOR_TEXT_DIM)

		if state == _CardState.LOCKED:
			card.cost_icon.visible = false
			card.cost_label.text = "Locked"
			card.cost_label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_DIM)
			card.count_label.text = ""
		else:
			card.cost_icon.visible = true
			card.cost_label.text = "%d" % cost
			card.cost_label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_GOLD if can_afford else UIThemeTokens.COLOR_TEXT_DIM)
			card.count_label.text = "%d/%d" % [count, max_count]
			var count_color: Color = UIThemeTokens.COLOR_TEXT_GOLD if state == _CardState.CAPPED else UIThemeTokens.COLOR_TEXT_DIM
			card.count_label.add_theme_color_override("font_color", count_color)

		card.button.tooltip_text = tooltip


## Pixel-art icons are authored larger than the card; shrink them with
## nearest-neighbor so they stay crisp.
func _scaled_icon(texture: Texture2D, max_height: int) -> ImageTexture:
	var img: Image = texture.get_image()
	var scale: float = max_height / float(img.get_height())
	img.resize(maxi(1, roundi(img.get_width() * scale)), max_height, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


func _apply_card_style(card: _BuildCard, state: _CardState, selected: bool) -> void:
	var btn: Button = card.button
	if selected:
		var style: StyleBoxFlat = _make_selected_stylebox()
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_stylebox_override("disabled", style)
		btn.modulate = Color.WHITE
		return

	btn.add_theme_stylebox_override("normal", _make_stylebox("normal", state))
	btn.add_theme_stylebox_override("hover", _make_stylebox("hover", state))
	btn.add_theme_stylebox_override("pressed", _make_stylebox("pressed", state))
	btn.add_theme_stylebox_override("disabled", _make_stylebox("disabled", state))
	btn.modulate = _state_modulate(state)


func _make_stylebox(variant: String, state: _CardState) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.set_corner_radius_all(UIThemeTokens.RADIUS_BUTTON)
	style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8

	match variant:
		"normal":
			match state:
				_CardState.AVAILABLE:
					style.bg_color = UIThemeTokens.COLOR_BUTTON_NORMAL
					style.border_color = UIThemeTokens.COLOR_BUTTON_BORDER
				_CardState.UNAFFORDABLE:
					style.bg_color = Color("#151b26")
					style.border_color = Color(1.0, 1.0, 1.0, 0.04)
				_CardState.CAPPED:
					style.bg_color = Color("#1a1d22")
					style.border_color = UIThemeTokens.COLOR_UPGRADE_BORDER
				_CardState.LOCKED:
					style.bg_color = Color("#11151c")
					style.border_color = Color(1.0, 1.0, 1.0, 0.03)
		"hover":
			match state:
				_CardState.AVAILABLE:
					style.bg_color = UIThemeTokens.COLOR_BUTTON_HOVER
					style.border_color = UIThemeTokens.COLOR_BUTTON_HOVER_BORDER
				_:
					var base: StyleBoxFlat = _make_stylebox("normal", state)
					style.bg_color = base.bg_color.lightened(0.04)
					style.border_color = Color(UIThemeTokens.COLOR_BUTTON_HOVER_BORDER.r, UIThemeTokens.COLOR_BUTTON_HOVER_BORDER.g, UIThemeTokens.COLOR_BUTTON_HOVER_BORDER.b, 0.25)
		"pressed":
			match state:
				_CardState.AVAILABLE:
					style.bg_color = UIThemeTokens.COLOR_BUTTON_PRESSED
					style.border_color = UIThemeTokens.COLOR_BUTTON_BORDER
				_:
					var base: StyleBoxFlat = _make_stylebox("normal", state)
					style.bg_color = base.bg_color.darkened(0.05)
					style.border_color = base.border_color
		"disabled":
			match state:
				_CardState.UNAFFORDABLE:
					style.bg_color = Color("#151b26")
					style.border_color = Color(1.0, 1.0, 1.0, 0.04)
				_CardState.CAPPED:
					style.bg_color = Color("#1a1d22")
					style.border_color = Color(UIThemeTokens.COLOR_UPGRADE_BORDER.r, UIThemeTokens.COLOR_UPGRADE_BORDER.g, UIThemeTokens.COLOR_UPGRADE_BORDER.b, 0.5)
				_CardState.LOCKED, _:
					style.bg_color = Color("#11151c")
					style.border_color = Color(1.0, 1.0, 1.0, 0.03)
	return style


func _make_selected_stylebox() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.set_corner_radius_all(UIThemeTokens.RADIUS_BUTTON)
	style.set_border_width_all(2)
	style.border_color = UIThemeTokens.COLOR_TEXT_GOLD
	style.bg_color = Color("#1c2434")
	style.shadow_color = Color(UIThemeTokens.COLOR_TEXT_GOLD.r, UIThemeTokens.COLOR_TEXT_GOLD.g, UIThemeTokens.COLOR_TEXT_GOLD.b, 0.28)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0.0, 2.0)
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	return style


func _state_modulate(state: _CardState) -> Color:
	match state:
		_CardState.AVAILABLE:
			return Color.WHITE
		_CardState.UNAFFORDABLE:
			return Color(0.55, 0.55, 0.62)
		_CardState.CAPPED:
			return Color(0.5, 0.5, 0.55)
		_CardState.LOCKED:
			return Color(0.38, 0.38, 0.42)
	return Color.WHITE


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
