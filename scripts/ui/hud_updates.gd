class_name HUDUpdates
extends RefCounted

var hud: HUD

func _init(h: HUD) -> void:
	hud = h


## Revamp Phase 2: faction icons in the top bar. The player's own faction is
## always shown; the enemy's stays hidden until a scout identifies it.
func _setup_faction_icons() -> void:
	if hud._player_faction_icon:
		var player_faction: FactionData = FactionManager.get_faction(GameManager.Team.PLAYER)
		if player_faction != null and player_faction.icon != null:
			hud._player_faction_icon.texture = player_faction.icon
		else:
			hud._player_faction_icon.visible = false
	if hud._enemy_faction_icon:
		hud._enemy_faction_icon.visible = false
		if FactionManager.is_faction_identified(GameManager.Team.ENEMY):
			_on_faction_identified(GameManager.Team.ENEMY)
		elif not FactionManager.faction_identified.is_connected(_on_faction_identified):
			FactionManager.faction_identified.connect(_on_faction_identified)


func _on_faction_identified(team: GameManager.Team) -> void:
	if team != GameManager.Team.ENEMY or hud._enemy_faction_icon == null:
		return
	var enemy_faction: FactionData = FactionManager.get_faction(GameManager.Team.ENEMY)
	if enemy_faction != null and enemy_faction.icon != null:
		hud._enemy_faction_icon.texture = enemy_faction.icon
		hud._enemy_faction_icon.visible = true


func _sync_speed_buttons() -> void:
	for speed: float in hud._speed_buttons:
		var btn: Button = hud._speed_buttons[speed]
		if btn.button_pressed != (GameManager.game_speed == speed):
			btn.set_pressed_no_signal(GameManager.game_speed == speed)


func _sync_view_buttons() -> void:
	var pc: PlayerController = hud._get_player_controller()
	var underground: bool = pc.is_underground_view() if pc else false
	if hud._surface_button.button_pressed != (not underground):
		hud._surface_button.set_pressed_no_signal(not underground)
	if hud._underground_button.button_pressed != underground:
		hud._underground_button.set_pressed_no_signal(underground)


## The Attack/Defend/Garrison buttons are toggles reflecting the persistent
## stance mode: the active mode stays highlighted (radio-style).
func _sync_stance_buttons(pc: PlayerController) -> void:
	var stance: String = pc.get_stance()
	for stance_name: String in hud._stance_buttons:
		var btn: Button = hud._stance_buttons[stance_name]
		if btn.button_pressed != (stance == stance_name):
			btn.set_pressed_no_signal(stance == stance_name)


## Selection readout in the top bar: a count for groups, and the unit's name
## plus live HP when exactly one unit is selected (click a unit to inspect it).
func _update_selection_label(pc: PlayerController) -> void:
	var selected: Array = pc.get_selected_units().filter(func(u): return is_instance_valid(u))
	if selected.size() == 1:
		var unit = selected[0]
		var data = unit.get("data")
		if data != null:
			hud._selection_label.text = "%s — HP %d/%d" % [data.unit_name, unit.get("hp"), data.max_hp]
			if data.is_miner:
				hud._selection_label.text += " — Gold %d/%d" % [unit.get("carried_coin"), data.carry_capacity]
			return
	hud._selection_label.text = "Selected: %d" % selected.size()


func _update_unit_breakdown() -> void:
	var counts: Dictionary = { "Miner": 0, "Swordsman": 0, "Archer": 0, "Wizard": 0, "Dragon": 0 }
	for unit in hud.get_tree().get_nodes_in_group("player"):
		var data = unit.get("data")
		if data == null:
			continue
		var unit_name: String = data.unit_name
		if counts.has(unit_name):
			counts[unit_name] += 1
	for unit_name: String in hud._unit_count_labels:
		hud._unit_count_labels[unit_name].text = "%d" % counts[unit_name]


func _update_upgrade_button() -> void:
	var level: int = EconomyManager.get_miner_level(GameManager.Team.PLAYER)
	var cost: int = EconomyManager.get_miner_upgrade_cost(GameManager.Team.PLAYER)
	if cost < 0:
		hud._upgrade_button.text = "Upgrade Miner\nMax Level"
		hud._upgrade_button.disabled = true
		hud._upgrade_button.tooltip_text = "Miners are fully upgraded"
	else:
		hud._upgrade_button.text = "Upgrade Miner\nLv %d → %d | %d" % [level, level + 1, cost]
		var affordable: bool = EconomyManager.can_afford(GameManager.Team.PLAYER, cost)
		hud._upgrade_button.disabled = not affordable
		hud._upgrade_button.tooltip_text = "" if affordable else "Not enough coin (%d needed)" % cost


func _update_fighter_upgrade_buttons() -> void:
	for unit_id: String in hud._fighter_upgrade_buttons:
		var btn: Button = hud._fighter_upgrade_buttons[unit_id]
		var level: int = EconomyManager.get_fighter_level(GameManager.Team.PLAYER, unit_id)
		var cost: int = EconomyManager.get_fighter_upgrade_cost(GameManager.Team.PLAYER, unit_id)
		if cost < 0:
			btn.text = "%s\nMax Level" % unit_id.capitalize()
			btn.disabled = true
			btn.tooltip_text = "%s is fully upgraded" % unit_id.capitalize()
		else:
			btn.text = "%s\nLv %d → %d | %d" % [unit_id.capitalize(), level, level + 1, cost]
			var affordable: bool = EconomyManager.can_afford(GameManager.Team.PLAYER, cost)
			btn.disabled = not affordable
			btn.tooltip_text = "" if affordable else "Not enough coin (%d needed)" % cost


func _initialize_hp_labels() -> void:
	var player_building: Node2D = hud._get_player_building()
	if player_building:
		hud._player_hp_label.text = "%d" % player_building.get("_hp")
	var enemy_building: Node2D = hud._get_enemy_building()
	if enemy_building:
		hud._enemy_hp_label.text = "%d" % enemy_building.get("_hp")
