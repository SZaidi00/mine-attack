extends Control

## First-match tutorial hints: a table of contextual tips evaluated on a 1s
## poll. One card at a time; dismissing (or 12s auto-dismiss) marks the hint
## seen in SettingsManager so it never shows again. Gated on
## SettingsManager.get_show_tutorial() and GameManager.game_active.

const UIThemeTokens = preload("res://scripts/ui/ui_theme_tokens.gd")

const _Constants = preload("res://scripts/autoload/constants.gd")
const _POLL_INTERVAL: float = 1.0
const _AUTO_DISMISS_SEC: float = 12.0
const _CARD_WIDTH: float = 360.0

var _hints: Array[Dictionary] = []
var _current_card: PanelContainer = null
var _current_id: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_hints()
	var timer := Timer.new()
	timer.wait_time = _POLL_INTERVAL
	timer.autostart = true
	timer.timeout.connect(poll_hints)
	add_child(timer)


func has_active_hint() -> bool:
	return is_instance_valid(_current_card) and _current_id != ""


## Evaluates the hint table and shows the first unseen, satisfied hint when
## none is on screen. Called by the poll timer (and directly by tests).
func poll_hints() -> void:
	if has_active_hint():
		return
	if not GameManager.game_active:
		return
	if not SettingsManager.get_show_tutorial():
		return
	var seen: Array[String] = SettingsManager.get_tutorial_seen()
	for hint: Dictionary in _hints:
		if hint.id in seen:
			continue
		if hint.condition.call():
			_show_hint(hint)
			return


## Dismisses the active card and marks its id seen (button + auto-dismiss).
func dismiss_current() -> void:
	if _current_id == "":
		return
	SettingsManager.mark_tutorial_seen(_current_id)
	_current_id = ""
	if is_instance_valid(_current_card):
		_current_card.queue_free()
	_current_card = null


func _show_hint(hint: Dictionary) -> void:
	var card := _build_card(hint)
	add_child(card)
	_current_card = card
	_current_id = hint.id
	_auto_dismiss_later(hint.id)


func _auto_dismiss_later(id: String) -> void:
	await get_tree().create_timer(_AUTO_DISMISS_SEC).timeout
	if _current_id == id and is_instance_valid(_current_card):
		dismiss_current()


func _build_card(hint: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.position = Vector2.ZERO
	var style := UIThemeTokens.make_panel_style()
	style.border_color = UIThemeTokens.COLOR_TEXT_GOLD
	style.border_width_left = 3
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	row.add_child(text_col)

	var eyebrow := Label.new()
	eyebrow.text = "TIP"
	eyebrow.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_SMALL)
	eyebrow.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_DIM)
	text_col.add_child(eyebrow)

	var title := Label.new()
	title.text = hint.title
	title.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	title.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_GOLD)
	text_col.add_child(title)

	var body := Label.new()
	body.text = hint.body
	body.custom_minimum_size = Vector2(_CARD_WIDTH, 0)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", UIThemeTokens.FONT_SIZE_BODY)
	body.add_theme_color_override("font_color", UIThemeTokens.COLOR_TEXT_PRIMARY)
	text_col.add_child(body)

	var got_it := Button.new()
	got_it.text = "Got it"
	UIThemeTokens.apply_button_theme(got_it, UIThemeTokens.ButtonVariant.SECONDARY)
	got_it.pressed.connect(dismiss_current)
	row.add_child(got_it)
	return card


# ─── Hint table ───
# Conditions use public autoload/group APIs only; keep them cheap (polled 1×/s).

func _build_hints() -> void:
	_hints = [
		{
			"id": "first_miner",
			"title": "Miners fuel everything",
			"body": "Your miners dig underground ore and haul it home. Click the Miner button (or press 1) to train more — a bigger crew means a faster economy.",
			"condition": _cond_first_miner,
		},
		{
			"id": "first_deposit",
			"title": "Coin keeps flowing",
			"body": "Deposited ore becomes spendable coin, and both sides also trickle a small baseline income — so you always have some cash coming in. Spend it on miners early.",
			"condition": _cond_first_deposit,
		},
		{
			"id": "train_army",
			"title": "Don't forget an army",
			"body": "The enemy won't wait forever. Train fighters (keys 2–5) and set their stance with the bottom-row buttons: Attack chases, Defend holds your half, Garrison guards the base.",
			"condition": _cond_train_army,
		},
		{
			"id": "fighter_orders",
			"title": "Commanding your units",
			"body": "Right-click the ground to move, or right-click an enemy to attack. Press Q then left-click to attack-move — your fighters engage everything on the way.",
			"condition": _cond_fighter_selected,
		},
		{
			"id": "miner_upgrade",
			"title": "Deeper layers, richer ore",
			"body": "You can afford a miner upgrade (bottom-left button). Each level lets miners dig into deeper layers where the ore veins are richer.",
			"condition": _cond_miner_upgrade,
		},
		{
			"id": "weather_warning",
			"title": "Bad weather incoming",
			"body": "A weather event is starting! Surface units take frost damage in snowstorms and meteors hammer the ground during eruptions — send miners underground and pull fighters under cover until it passes.",
			"condition": _cond_weather_warning,
		},
		{
			"id": "faction_identified",
			"title": "Enemy faction identified",
			"body": "",
			"condition": _cond_faction_identified,
		},
		{
			"id": "research_available",
			"title": "Research is available",
			"body": "You have coin for a technology. Press R to open the Doctrine Deck: timed upgrades across combat, economy, and defense branches — tier-3 capstones are mutually exclusive.",
			"condition": _cond_research_available,
		},
		{
			"id": "base_damaged",
			"title": "Your base is under threat",
			"body": "Your building is below 60% health! Train an Engineer (key 7) to repair it, raise walls and towers with the Build menu, and intercept attackers before they reach the base.",
			"condition": _cond_base_damaged,
		},
		{
			"id": "underground_defense",
			"title": "The mine has enemies too",
			"body": "Crawlers can tunnel under the central wall and ambush your miners. Guard the mine with your own crawler (key 8), place traps with the Guerrilla research, and keep a lantern lit underground.",
			"condition": _cond_underground_defense,
		},
	]


# ─── Conditions ───

func _cond_first_miner() -> bool:
	return EconomyManager.get_units_trained(GameManager.Team.PLAYER) >= 1


func _cond_first_deposit() -> bool:
	return EconomyManager.get_coin_mined(GameManager.Team.PLAYER) > 0


func _cond_train_army() -> bool:
	if GameManager.match_time < 60.0:
		return false
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == GameManager.Team.PLAYER:
			return true
	return false


func _cond_fighter_selected() -> bool:
	var pc := get_node_or_null("/root/Main/PlayerController")
	if pc == null:
		return false
	for unit in pc.get_selected_units():
		if unit.data != null and unit.data.is_fighter:
			return true
	return false


func _cond_miner_upgrade() -> bool:
	# get_miner_upgrade_cost returns -1 once every level is bought.
	var cost: int = EconomyManager.get_miner_upgrade_cost(GameManager.Team.PLAYER)
	return cost > 0 and EconomyManager.get_coin(GameManager.Team.PLAYER) >= cost


func _cond_weather_warning() -> bool:
	return WeatherManager.is_snowstorm_warning() \
		or WeatherManager.is_snowstorm_active() \
		or WeatherManager.is_volcano_warning() \
		or WeatherManager.is_volcano_active()


func _cond_faction_identified() -> bool:
	if not FactionManager.is_faction_identified(GameManager.Team.ENEMY):
		return false
	var faction: FactionData = FactionManager.get_faction(GameManager.Team.ENEMY)
	if faction != null:
		var summary: String = faction.description.strip_edges()
		_set_hint_body("faction_identified", "The enemy is %s! %s" % [faction.faction_name, summary])
	return true


func _cond_research_available() -> bool:
	if GameManager.match_time < 30.0:
		return false
	var team := GameManager.Team.PLAYER
	var coin: int = EconomyManager.get_coin(team)
	for tech_id in _Constants.RESEARCH_TECHS:
		if ResearchManager.is_locked(team, tech_id):
			continue
		if not ResearchManager.are_prerequisites_met(team, tech_id):
			continue
		var data: Dictionary = ResearchManager.get_next_level_data(team, tech_id)
		if not data.is_empty() and int(data.get("cost", 0)) <= coin:
			return true
	return false


func _cond_base_damaged() -> bool:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == GameManager.Team.PLAYER and float(b.get("_hp")) < float(b.max_hp) * 0.6:
			return true
	return false


func _cond_underground_defense() -> bool:
	if ResearchManager.has_branch(GameManager.Team.PLAYER, "guerrilla"):
		return true
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == GameManager.Team.PLAYER and unit.data != null and unit.data.is_crawler:
			return true
	return false


func _set_hint_body(id: String, body: String) -> void:
	for hint: Dictionary in _hints:
		if hint.id == id:
			hint.body = body
			return
