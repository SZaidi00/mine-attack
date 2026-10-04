class_name TutorialPanel
extends RefCounted

## First-time-player tutorial: a paginated set of illustrated reference
## screens covering the goal, economy, units, structures, research, weather,
## and controls. create() returns a hidden full-rect Control; callers add it
## as a child and toggle `visible`, same as SettingsPanel.

const UIThemeTokens = preload("res://scripts/ui/ui_theme_tokens.gd")

const _ICON_MINER: Texture2D = preload("res://frost_mines_assets/icons/icon_miner.png")
const _ICON_SWORDSMAN: Texture2D = preload("res://frost_mines_assets/icons/icon_swordsman.png")
const _ICON_ARCHER: Texture2D = preload("res://frost_mines_assets/icons/icon_archer.png")
const _ICON_WIZARD: Texture2D = preload("res://frost_mines_assets/icons/icon_wizard.png")
const _ICON_DRAGON: Texture2D = preload("res://frost_mines_assets/icons/icon_dragon.png")
const _ICON_ENGINEER: Texture2D = preload("res://frost_mines_assets/icons/icon_engineer.png")
const _ICON_CRAWLER: Texture2D = preload("res://frost_mines_assets/icons/icon_crawler.png")
const _ICON_BUILDING: Texture2D = preload("res://frost_mines_assets/icons/icon_building.png")
const _ICON_LANTERN: Texture2D = preload("res://frost_mines_assets/icons/button_build_lantern.png")
const _ICON_TOWER: Texture2D = preload("res://frost_mines_assets/icons/button_build_tower.png")
const _ICON_WALL: Texture2D = preload("res://frost_mines_assets/icons/button_build_wall.png")
const _ICON_TRAP: Texture2D = preload("res://frost_mines_assets/icons/icon_attack.png")
const _ICON_COIN: Texture2D = preload("res://frost_mines_assets/icons/icon_coin.png")
const _ICON_RESEARCH: Texture2D = preload("res://frost_mines_assets/icons/tech_deep_delve.png")
const _ICON_SNOWSTORM: Texture2D = preload("res://frost_mines_assets/icons/icon_snowstorm.png")
const _ICON_LAVA: Texture2D = preload("res://frost_mines_assets/icons/icon_lava.png")
const _ICON_WEATHER: Texture2D = preload("res://frost_mines_assets/icons/icon_weather_alert.png")

# Each page: title, intro paragraph, and icon/heading/text rows.
const _PAGES: Array = [
	{
		"title": "WELCOME TO MINEATTACK",
		"intro": "A single-player real-time strategy duel in the frost mines. You command the BLUE team from the base on the left; a scripted AI commands the RED team on the right. Destroy the enemy building before it destroys yours.\n\nEvery match is fought on two fronts: the SURFACE battlefield, where armies clash, and the UNDERGROUND mine, where your economy lives. Press Tab at any time to flip the camera between them.",
		"entries": [],
	},
	{
		"title": "ECONOMY & MINERS",
		"intro": "Coin funds everything: units, structures, and research. Your building also trickles a small baseline income, but the mine is where fortunes are made.",
		"entries": [
			{"icon": _ICON_MINER, "heading": "Miners (train with 1)", "text": "Your workforce. Send them underground to dig ore, then they haul it back and deposit coin at your building."},
			{"icon": _ICON_COIN, "heading": "Miners dig gold", "text": "Right-click ore to order mining runs. Ore depletes over time, so keep pushing into deeper, richer veins."},
			{"icon": _ICON_MINER, "heading": "Miner upgrades", "text": "Upgrade miners at your building to unlock deeper mine layers (level 1 reaches layers 1–2, level 2 layers 3–4, level 3 layers 5–7)."},
			{"icon": _ICON_COIN, "heading": "Never fully broke", "text": "If every miner is dead and you cannot afford a new one, a welfare trickle kicks in so the economy can always recover."},
		],
	},
	{
		"title": "UNITS",
		"intro": "Train units from your building with the number keys. Every unit has a role — build an army that covers several of them.",
		"entries": [
			{"icon": _ICON_SWORDSMAN, "heading": "Swordsman (2)", "text": "Cheap melee frontline. Upgrade fighters to level 3 for more HP and damage."},
			{"icon": _ICON_ARCHER, "heading": "Archer (3)", "text": "Ranged fighter that kites away from melee threats; also shoots down dragons and pigeons."},
			{"icon": _ICON_WIZARD, "heading": "Wizard (4)", "text": "Expensive AoE spell damage. With Necromancy research, wizards raise undead from fallen warriors."},
			{"icon": _ICON_DRAGON, "heading": "Dragon (5)", "text": "Flying heavy hitter, strong against air and ground. Only archers and other fliers can answer it."},
			{"icon": _ICON_ENGINEER, "heading": "Engineer (7)", "text": "Support unit with no attack. Channels repairs on damaged walls, towers, lanterns, and buildings for a coin cost. Idle engineers seek work on their own."},
			{"icon": _ICON_CRAWLER, "heading": "Crawler (8)", "text": "Underground-only raider: it dives into the mine at spawn and can never surface or dig. Raid enemy miners through breached walls."},
			{"icon": _ICON_TOWER, "heading": "Pigeon (6)", "text": "Trained from towers. A flying scout that extends your vision — fragile, so keep it away from archers."},
		],
	},
	{
		"title": "STRUCTURES",
		"intro": "Open the radial build menu with the Build button on the HUD and place structures on the map. Placement costs coin, and each option greys out when unaffordable.",
		"entries": [
			{"icon": _ICON_BUILDING, "heading": "Your building", "text": "Trains every unit, receives miner deposits, and is your life line — when it falls, the match is lost. The enemy's building is your win condition."},
			{"icon": _ICON_LANTERN, "heading": "Lanterns", "text": "Provide vision on the surface and underground, piercing the fog of war. Upgrade tiers 1→3 for wider sight."},
			{"icon": _ICON_TOWER, "heading": "Towers", "text": "Static surface defenses that auto-attack enemies in range — and train pigeons."},
			{"icon": _ICON_WALL, "heading": "Walls", "text": "Single-cell barriers that block movement and projectiles. They must be torn down before troops pass."},
			{"icon": _ICON_TRAP, "heading": "Traps", "text": "Hidden area damage triggered by enemy units. Requires the Guerrilla research; only miners can place them."},
		],
	},
	{
		"title": "RESEARCH",
		"intro": "Press R to open the Doctrine Deck. Research is timed and paid with coin, and your choices shape the whole match — pick a strategy and commit.",
		"entries": [
			{"icon": _ICON_RESEARCH, "heading": "Discipline roots", "text": "Tier-1 roots: Deep Delve (mine deeper) or Surface War (stronger surface army) — these two are mutually exclusive. Fortification, Dragon Mastery, Arctic Training, and Survival Instinct are independent."},
			{"icon": _ICON_RESEARCH, "heading": "Branching tiers", "text": "Tier-2 techs can both be researched. Tier-3 capstones lock each other out — Deep Delve ends in a three-way choice: Crystal Forge, Earth Shield, or Necromancy."},
			{"icon": _ICON_RESEARCH, "heading": "Tier-4 capstones", "text": "The top-tier techs (Deep Fortress, Total War, Storm Dragon) require techs from two different disciplines, so plan a path early."},
			{"icon": _ICON_COIN, "heading": "Respec", "text": "Made a bad call? A one-time 500g respec resets every research choice so you can rebuild your tree."},
		],
	},
	{
		"title": "WEATHER & THE MOUNTAIN",
		"intro": "The mine is alive. Random events shake up both teams — watch the warning banners and react.",
		"entries": [
			{"icon": _ICON_SNOWSTORM, "heading": "Snowstorms", "text": "Cut vision and movement, and slowly damage surface units. Shelter your army underground or finish the fight fast. Survival Instinct research blunts the damage."},
			{"icon": _ICON_WEATHER, "heading": "Volcano eruptions", "text": "Meteors rain on the surface and leave burning ground. A snowstorm that overlaps the burns extinguishes them."},
			{"icon": _ICON_LAVA, "heading": "Lava rises", "text": "Lava climbs the mine from the bottom up. Deeper layers become deadly, and flooded cells eventually resurface as fresh rock and ore."},
			{"icon": _ICON_LAVA, "heading": "Cave-ins", "text": "3×3 rock blocks can drop without warning, damaging and shoving anything beneath. Keep the crew spread out."},
		],
	},
	{
		"title": "CONTROLS & TIPS",
		"intro": "Left-click selects, right-click orders. Every order marker shows what your units understood: blue rings are moves, red are attacks, gold is mining.",
		"entries": [
			{"icon": _ICON_SWORDSMAN, "heading": "Keys", "text": "1–8 train units · Tab surface/underground · Q attack-move · F cycle formation (line / column / spread) · R research · Space pause · Esc menu · F3 debug overlay."},
			{"icon": _ICON_ARCHER, "heading": "Smart selection", "text": "Drag a box to select groups. Ctrl+A all units, Ctrl+M miners, Ctrl+F fighters, Ctrl+D dragons, K disbands. Ctrl+1–9 saves a control group, Alt+1–9 recalls it."},
			{"icon": _ICON_TOWER, "heading": "Queue orders", "text": "Shift + right-click queues waypoints behind the current order, so a squad can patrol or run a multi-leg route without babysitting."},
			{"icon": _ICON_LANTERN, "heading": "Scout", "text": "The enemy faction is hidden until you get a unit close to their building. Send a swordsman or pigeon early so you know what you are facing."},
		],
		"quote": "\"If you can't figure out the game, you don't deserve to play\"\n— Salman Hashmi",
	},
]


static func create() -> Control:
	var root := Control.new()
	root.name = "TutorialPanel"
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
	card.custom_minimum_size = Vector2(760, 0)
	card.add_theme_stylebox_override("panel", UIThemeTokens.make_metal_card_style())
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	vbox.add_child(title)

	var page_counter := Label.new()
	page_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_counter.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	page_counter.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_DIM)
	vbox.add_child(page_counter)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(140, 40)
	back.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	UIThemeTokens.apply_button_theme(back, UIThemeTokens.ButtonVariant.SECONDARY)
	buttons.add_child(back)

	var next := Button.new()
	next.text = "Next"
	next.custom_minimum_size = Vector2(140, 40)
	next.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	UIThemeTokens.apply_button_theme(next, UIThemeTokens.ButtonVariant.PRIMARY)
	buttons.add_child(next)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(140, 40)
	close.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	UIThemeTokens.apply_button_theme(close, UIThemeTokens.ButtonVariant.SECONDARY)
	close.pressed.connect(func(): AudioManager.play("click"))
	close.pressed.connect(func(): root.visible = false)
	buttons.add_child(close)

	var state := {"page": 0}

	var refresh := func() -> void:
		var page_index: int = state["page"]
		var page: Dictionary = _PAGES[page_index]
		title.text = page["title"]
		page_counter.text = "Page %d of %d" % [page_index + 1, _PAGES.size()]
		back.disabled = page_index == 0
		next.text = "Finish" if page_index == _PAGES.size() - 1 else "Next"
		for child in content.get_children():
			child.queue_free()
		_build_page(content, page)
		content.get_parent().scroll_vertical = 0

	back.pressed.connect(func(): AudioManager.play("click"))
	back.pressed.connect(func():
		state["page"] = maxi(0, state["page"] - 1)
		refresh.call())
	next.pressed.connect(func(): AudioManager.play("click"))
	next.pressed.connect(func():
		if state["page"] >= _PAGES.size() - 1:
			root.visible = false
		else:
			state["page"] += 1
			refresh.call())

	refresh.call()
	return root


static func _build_page(content: VBoxContainer, page: Dictionary) -> void:
	var intro := Label.new()
	intro.text = page["intro"]
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	intro.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	content.add_child(intro)

	for entry: Dictionary in page["entries"]:
		content.add_child(_build_entry_row(entry))

	if page.has("quote"):
		content.add_child(_build_quote_label(page["quote"]))


static func _build_quote_label(quote: String) -> Label:
	var label := Label.new()
	label.text = quote
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY + 2)
	label.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_GOLD)
	label.add_theme_color_override("font_outline_color", Color("#0b1120"))
	label.add_theme_constant_override("outline_size", 4)
	return label


static func _build_entry_row(entry: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIThemeTokens.make_recessed_panel_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	var icon := TextureRect.new()
	icon.texture = entry["icon"]
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	var heading := Label.new()
	heading.text = entry["heading"]
	heading.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY + 1)
	heading.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_GOLD)
	vbox.add_child(heading)

	var body := Label.new()
	body.text = entry["text"]
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	body.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_DIM)
	vbox.add_child(body)

	return panel
