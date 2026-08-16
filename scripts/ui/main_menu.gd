extends Control

## Main menu: night-sky backdrop with falling snow, both bases on the ground
## strip, and a centered card with title, difficulty / resolution selects,
## Play / Quit.

const _SKY: Texture2D = preload("res://frost_mines_assets/backgrounds/surface_sky.png")
const _GROUND: Texture2D = preload("res://frost_mines_assets/backgrounds/surface_ground.png")
const _BUILDING_PLAYER: Texture2D = preload("res://frost_mines_assets/buildings/building_player.png")
const _BUILDING_ENEMY: Texture2D = preload("res://frost_mines_assets/buildings/building_enemy.png")
const _MINER_PLAYER: Texture2D = preload("res://frost_mines_assets/units/miner_l1_player.png")
const _SWORDSMAN_PLAYER: Texture2D = preload("res://frost_mines_assets/units/swordsman_player.png")
const _SWORDSMAN_ENEMY: Texture2D = preload("res://frost_mines_assets/units/swordsman_enemy.png")
const _PANEL_BG: Texture2D = preload("res://frost_mines_assets/ui/panel_background.png")
const _BUTTON_NORMAL: Texture2D = preload("res://frost_mines_assets/ui/button_normal.png")
const _BUTTON_HOVER: Texture2D = preload("res://frost_mines_assets/ui/button_hover.png")
const _BUTTON_PRESSED: Texture2D = preload("res://frost_mines_assets/ui/button_pressed.png")
const _BUTTON_UPGRADE: Texture2D = preload("res://frost_mines_assets/ui/button_upgrade.png")

var _difficulty_option: OptionButton
# Revamp Phase 2: two-step menu — the main card leads into faction select.
var _main_center: CenterContainer
var _faction_center: CenterContainer
var _selected_faction_id: String = ""
var _faction_cards: Dictionary = {}  # faction_id -> PanelContainer
var _play_button: Button
# Revamp Phase 7: faction-themed background particles on the select screen
# (purple sparks / red embers / yellow steam), tinted on selection.
var _faction_particles: CPUParticles2D
const _FACTION_PARTICLE_COLORS: Dictionary = {
	"arcane": Color(0.77, 0.52, 0.99, 0.55),  # purple sparks
	"brute": Color(0.97, 0.44, 0.44, 0.55),  # red embers
	"industrial": Color(0.98, 0.79, 0.21, 0.45),  # yellow steam
}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_card()
	_build_faction_select()


func _build_background() -> void:
	var sky := TextureRect.new()
	sky.texture = _SKY
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)

	var ground := TextureRect.new()
	ground.texture = _GROUND
	ground.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ground.custom_minimum_size = Vector2(0, 150)
	ground.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ground.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)

	# Both bases face off on the ground strip: player left, enemy right.
	_add_sprite(_BUILDING_PLAYER, Vector2(0.10, 1.0), Vector2(180, 240), Vector2(0, -150 - 240))
	_add_sprite(_MINER_PLAYER, Vector2(0.16, 1.0), Vector2(48, 72), Vector2(0, -150 - 72))
	_add_sprite(_SWORDSMAN_PLAYER, Vector2(0.19, 1.0), Vector2(48, 72), Vector2(0, -150 - 72))
	_add_sprite(_BUILDING_ENEMY, Vector2(0.90, 1.0), Vector2(180, 240), Vector2(-180, -150 - 240))
	_add_sprite(_SWORDSMAN_ENEMY, Vector2(0.82, 1.0), Vector2(48, 72), Vector2(-48, -150 - 72))

	_add_snow()


## Decorative sprite anchored at a relative screen position (fraction of the
## viewport size), with an extra pixel offset on top.
func _add_sprite(texture: Texture2D, anchor_fraction: Vector2, sprite_size: Vector2, offset: Vector2) -> void:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.custom_minimum_size = sprite_size
	rect.size = sprite_size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	# Position after the parent has a real size (deferred one frame so layout
	# has run); anchored relative so window resizes keep the composition.
	rect.set_meta("anchor_fraction", anchor_fraction)
	rect.set_meta("pixel_offset", offset)
	_reposition_sprite.call_deferred(rect)


func _reposition_sprite(rect: TextureRect) -> void:
	if not is_instance_valid(rect):
		return
	var anchor_fraction: Vector2 = rect.get_meta("anchor_fraction")
	var offset: Vector2 = rect.get_meta("pixel_offset")
	rect.position = size * anchor_fraction + offset


func _add_snow() -> void:
	var snow := CPUParticles2D.new()
	snow.amount = 200
	snow.lifetime = 10.0
	snow.preprocess = 10.0  # Screen is already dusted when the menu appears.
	snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow.emission_rect_extents = Vector2(1400, 8)
	snow.direction = Vector2(0, 1)
	snow.spread = 10.0
	snow.initial_velocity_min = 35.0
	snow.initial_velocity_max = 80.0
	snow.gravity = Vector2(0, 10)
	snow.scale_amount_min = 0.8
	snow.scale_amount_max = 2.2
	snow.texture = _make_soft_dot_texture()
	snow.position = Vector2(1280, -10)
	add_child(snow)


func _make_soft_dot_texture() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(8):
		for y in range(8):
			var d: float = Vector2(x - 3.5, y - 3.5).length()
			if d <= 3.5:
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d / 3.5, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _build_card() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_main_center = center

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(460, 0)
	var card_style := _make_textured_style(_PANEL_BG)
	card_style.content_margin_left = 40
	card_style.content_margin_top = 32
	card_style.content_margin_right = 40
	card_style.content_margin_bottom = 32
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var title := Label.new()
	title.text = "MINEATTACK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color("#e2e8f0"))
	title.add_theme_color_override("font_outline_color", Color("#0b1120"))
	title.add_theme_constant_override("outline_size", 10)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "F R O S T   M I N E S"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color("#fbbf24"))
	vbox.add_child(subtitle)

	var separator := HSeparator.new()
	vbox.add_child(separator)

	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var diff_label := Label.new()
	diff_label.text = "Difficulty:"
	diff_label.add_theme_color_override("font_color", Color("#e2e8f0"))
	diff_row.add_child(diff_label)
	_difficulty_option = OptionButton.new()
	_difficulty_option.custom_minimum_size = Vector2(160, 0)
	for diff_name in GameManager.Difficulty.keys():
		_difficulty_option.add_item(diff_name.capitalize())
	_difficulty_option.selected = GameManager.difficulty
	diff_row.add_child(_difficulty_option)
	vbox.add_child(diff_row)

	if SettingsManager.is_supported():
		var res_row := HBoxContainer.new()
		res_row.add_theme_constant_override("separation", 8)
		res_row.alignment = BoxContainer.ALIGNMENT_CENTER
		var res_label := Label.new()
		res_label.text = "Resolution:"
		res_label.add_theme_color_override("font_color", Color("#e2e8f0"))
		res_row.add_child(res_label)
		var res_option := OptionButton.new()
		res_option.custom_minimum_size = Vector2(160, 0)
		var available := SettingsManager.get_available_resolutions()
		var current := SettingsManager.get_resolution()
		if current not in available:
			available.append(current)  # Show the actual size (e.g. manually resized window).
		for res in available:
			res_option.add_item("%d × %d" % [res.x, res.y])
			if res == current:
				res_option.selected = res_option.item_count - 1
		res_option.item_selected.connect(func(index: int): SettingsManager.set_resolution(available[index]))
		res_row.add_child(res_option)
		vbox.add_child(res_row)

	_add_menu_button(vbox, "Next", _show_faction_select, true)
	_add_menu_button(vbox, "Quit", func(): get_tree().quit(), false)

	var hint := Label.new()
	hint.text = "Train with 1–4 · Tab switches view · Space pauses"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("#94a3b8"))
	vbox.add_child(hint)


func _add_menu_button(parent: Control, text: String, callback: Callable, primary: bool) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(240, 48 if primary else 40)
	btn.add_theme_font_size_override("font_size", 20 if primary else 16)
	btn.add_theme_color_override("font_color", Color("#fbbf24") if primary else Color("#e2e8f0"))
	btn.add_theme_color_override("font_hover_color", Color("#fde68a") if primary else Color("#ffffff"))
	btn.add_theme_color_override("font_pressed_color", Color("#fbbf24") if primary else Color("#e2e8f0"))
	var normal_texture: Texture2D = _BUTTON_UPGRADE if primary else _BUTTON_NORMAL
	btn.add_theme_stylebox_override("normal", _make_textured_style(normal_texture))
	btn.add_theme_stylebox_override("hover", _make_textured_style(_BUTTON_UPGRADE if primary else _BUTTON_HOVER))
	btn.add_theme_stylebox_override("pressed", _make_textured_style(_BUTTON_PRESSED))
	btn.pressed.connect(func(): AudioManager.play("click"))
	btn.pressed.connect(callback)
	parent.add_child(btn)


func _make_textured_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	return style


## Step 2 (Revamp Phase 2): three faction cards. The choice is hidden from
## the opponent — the AI's faction is a secret random pick made on Play.
func _build_faction_select() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.visible = false
	add_child(center)
	_faction_center = center

	var card := PanelContainer.new()
	var card_style := _make_textured_style(_PANEL_BG)
	card_style.content_margin_left = 40
	card_style.content_margin_top = 32
	card_style.content_margin_right = 40
	card_style.content_margin_bottom = 32
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var title := Label.new()
	title.text = "CHOOSE YOUR FACTION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("#e2e8f0"))
	title.add_theme_color_override("font_outline_color", Color("#0b1120"))
	title.add_theme_constant_override("outline_size", 8)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "The enemy's faction is hidden — scout their base to identify it"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#94a3b8"))
	vbox.add_child(hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)

	for faction_id: String in ["arcane", "brute", "industrial"]:
		var faction: FactionData = FactionManager.FACTIONS[faction_id]
		row.add_child(_build_faction_card(faction))

	# Re-select the last pick so returning to the menu keeps the choice.
	if FactionManager.player_faction_id != "":
		_select_faction(FactionManager.player_faction_id)

	_build_faction_particles()

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 40)
	back.add_theme_font_size_override("font_size", 16)
	back.add_theme_color_override("font_color", Color("#e2e8f0"))
	back.add_theme_stylebox_override("normal", _make_textured_style(_BUTTON_NORMAL))
	back.add_theme_stylebox_override("hover", _make_textured_style(_BUTTON_HOVER))
	back.add_theme_stylebox_override("pressed", _make_textured_style(_BUTTON_PRESSED))
	back.pressed.connect(func(): AudioManager.play("click"))
	back.pressed.connect(_show_main_card)
	buttons.add_child(back)

	_play_button = Button.new()
	_play_button.text = "Play"
	_play_button.custom_minimum_size = Vector2(240, 48)
	_play_button.add_theme_font_size_override("font_size", 20)
	_play_button.add_theme_color_override("font_color", Color("#fbbf24"))
	_play_button.add_theme_color_override("font_hover_color", Color("#fde68a"))
	_play_button.add_theme_stylebox_override("normal", _make_textured_style(_BUTTON_UPGRADE))
	_play_button.add_theme_stylebox_override("hover", _make_textured_style(_BUTTON_UPGRADE))
	_play_button.add_theme_stylebox_override("pressed", _make_textured_style(_BUTTON_PRESSED))
	_play_button.disabled = _selected_faction_id == ""
	_play_button.pressed.connect(func(): AudioManager.play("click"))
	_play_button.pressed.connect(_on_play)
	buttons.add_child(_play_button)


func _build_faction_card(faction: FactionData) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(260, 320)
	panel.add_theme_stylebox_override("panel", _faction_card_style(faction, false))
	_faction_cards[faction.faction_id] = panel

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var icon := TextureRect.new()
	icon.texture = faction.icon
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon)

	var name_label := Label.new()
	name_label.text = faction.faction_name.to_upper()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", faction.menu_color)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var desc := Label.new()
	desc.text = faction.description
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color("#94a3b8"))
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc)

	for highlight: String in faction.highlights:
		var bullet := Label.new()
		bullet.text = "• " + highlight
		bullet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bullet.add_theme_font_size_override("font_size", 12)
		bullet.add_theme_color_override("font_color", Color("#e2e8f0"))
		bullet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(bullet)

	var select := Button.new()
	select.text = "Select"
	select.custom_minimum_size = Vector2(140, 36)
	select.add_theme_font_size_override("font_size", 15)
	select.add_theme_color_override("font_color", Color("#e2e8f0"))
	select.add_theme_stylebox_override("normal", _make_textured_style(_BUTTON_NORMAL))
	select.add_theme_stylebox_override("hover", _make_textured_style(_BUTTON_HOVER))
	select.add_theme_stylebox_override("pressed", _make_textured_style(_BUTTON_PRESSED))
	select.pressed.connect(func(): AudioManager.play("click"))
	select.pressed.connect(_select_faction.bind(faction.faction_id))
	vbox.add_child(select)
	return panel


func _faction_card_style(faction: FactionData, selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#151c29") if not selected else Color("#1c2434")
	style.border_color = Color("#fbbf24") if selected else faction.menu_color.darkened(0.5)
	style.set_border_width_all(3 if selected else 1)
	style.set_corner_radius_all(10)
	if selected:
		# Gold glow bleeding out from behind the card.
		style.shadow_color = Color(0.98, 0.75, 0.14, 0.35)
		style.shadow_size = 18
	style.content_margin_left = 16
	style.content_margin_top = 16
	style.content_margin_right = 16
	style.content_margin_bottom = 16
	return style


## Revamp Phase 7: subtle faction-colored motes rising from the bottom edge
## while the faction select screen is open; tinted by the current pick.
func _build_faction_particles() -> void:
	_faction_particles = CPUParticles2D.new()
	_faction_particles.amount = 60
	_faction_particles.lifetime = 5.0
	_faction_particles.preprocess = 5.0  # Already drifting when the screen opens.
	_faction_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_faction_particles.emission_rect_extents = Vector2(1400, 8)
	_faction_particles.direction = Vector2(0, -1)
	_faction_particles.spread = 15.0
	_faction_particles.initial_velocity_min = 12.0
	_faction_particles.initial_velocity_max = 35.0
	_faction_particles.gravity = Vector2(0, -6)
	_faction_particles.scale_amount_min = 0.6
	_faction_particles.scale_amount_max = 1.8
	_faction_particles.texture = _make_soft_dot_texture()
	_faction_particles.emitting = _selected_faction_id != ""
	if _selected_faction_id != "":
		_faction_particles.color = _FACTION_PARTICLE_COLORS[_selected_faction_id]
	add_child(_faction_particles)
	# Behind the faction cards, in front of the backdrop.
	move_child(_faction_particles, _faction_center.get_index())
	_reposition_faction_particles.call_deferred()


func _reposition_faction_particles() -> void:
	if not is_instance_valid(_faction_particles):
		return
	_faction_particles.position = Vector2(size.x * 0.5, size.y + 10.0)
	_faction_particles.emission_rect_extents = Vector2(size.x * 0.55, 8.0)


func _select_faction(faction_id: String) -> void:
	_selected_faction_id = faction_id
	for id: String in _faction_cards:
		_faction_cards[id].add_theme_stylebox_override("panel", _faction_card_style(FactionManager.FACTIONS[id], id == faction_id))
	if _play_button != null:
		_play_button.disabled = false
	if _faction_particles != null:
		_faction_particles.color = _FACTION_PARTICLE_COLORS[faction_id]
		_faction_particles.emitting = _faction_center.visible


func _show_faction_select() -> void:
	_main_center.visible = false
	_faction_center.visible = true
	_reposition_faction_particles()
	_faction_particles.emitting = _selected_faction_id != ""


func _show_main_card() -> void:
	_faction_center.visible = false
	_main_center.visible = true
	_faction_particles.emitting = false


func _on_play() -> void:
	GameManager.set_difficulty(_difficulty_option.selected as GameManager.Difficulty)
	FactionManager.set_player_faction(_selected_faction_id)
	FactionManager.pick_random_enemy_faction()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
