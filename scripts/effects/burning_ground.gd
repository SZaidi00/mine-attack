class_name BurningGround
extends Node2D

## Crystal Forge (Revamp Phase 6): wizard fireballs scorch the impact area,
## leaving a patch of burning ground that ticks damage onto enemy units for
## BURNING_GROUND_DURATION seconds. Purely code-drawn: a dark scorch base,
## bright flickering flame layers with rising licks, and a pulsing danger ring
## drawn at exactly `radius` so the damage area is readable at a glance.
## Frees itself when the duration elapses.

const TICK_INTERVAL: float = 0.5

const _DAMAGE_POPUP_SCENE: PackedScene = preload("res://scenes/effects/damage_popup.tscn")

var team: GameManager.Team = GameManager.Team.PLAYER
var radius: float = 40.0
var dps: float = Constants.BURNING_GROUND_DPS
var duration: float = Constants.BURNING_GROUND_DURATION
## If true, this fire damages every unit regardless of team (volcano meteor scorch).
var damage_all_teams: bool = false
## If true, this patch was spawned by a volcano meteor and can be extinguished by snowstorms.
var is_volcano_fire: bool = false

var _elapsed: float = 0.0
var _tick_timer: float = 0.0
var _flicker: float = 0.0


func _ready() -> void:
	_flicker = randf() * TAU  # desync overlapping patches
	add_to_group("burning_grounds")
	queue_redraw()


func _process(delta: float) -> void:
	# Fog of War: a patch the player cannot see must not leak enemy activity
	# (same convention as the coin popup).
	var grid: Node = get_node_or_null("/root/Main/World/GridWorld")
	if grid != null:
		visible = grid.is_visible_to(GameManager.Team.PLAYER, global_position)
	if not GameManager.game_active:
		return
	_elapsed += delta
	_flicker += delta
	if _elapsed >= duration:
		queue_free()
		return
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = TICK_INTERVAL
		_tick_damage()
	queue_redraw()


func _tick_damage() -> void:
	var damage: int = maxi(1, roundi(dps * TICK_INTERVAL))
	for unit in get_tree().get_nodes_in_group("units"):
		if unit._state == Unit.State.DEAD:
			continue
		if not damage_all_teams and unit.team == team:
			continue
		if unit.get_combat_position().distance_to(global_position) <= radius:
			# Environmental: ground fire is attrition, not an attacker — no
			# combat reflexes (same convention as storm exposure), but the tick
			# does raise an orange -X popup so the damage reads. The tick also
			# ignites the unit: it keeps taking reduced burn ticks for a few
			# seconds after leaving the patch.
			unit.take_damage(damage, null, true)
			_spawn_fire_popup(unit, damage)
			unit.apply_burn(dps * Constants.BURN_LINGER_DPS_RATIO, Constants.BURN_LINGER_DURATION)
	_damage_structures(damage)


func _spawn_fire_popup(unit: Node2D, amount: int) -> void:
	var popup: DamagePopup = _DAMAGE_POPUP_SCENE.instantiate()
	popup.setup_fire(amount)
	popup.global_position = unit.get_combat_position() + Vector2(0, -20)
	get_tree().current_scene.add_child(popup)


func _damage_structures(damage: int) -> void:
	# Volcano fires scorch structures; crystal-forge fires do not.
	if not damage_all_teams:
		return
	for group in ["towers", "lanterns", "walls"]:
		for node in get_tree().get_nodes_in_group(group):
			if _is_protected_structure(node):
				continue
			if node.global_position.distance_to(global_position) <= radius:
				node.take_damage(damage)
	# Buildings group includes HQ buildings; skip those but damage nothing else
	# because the only other buildings are the HQ. Mine entries are also protected.
	for building in get_tree().get_nodes_in_group("buildings"):
		if _is_protected_structure(building):
			continue
		if building.global_position.distance_to(global_position) <= radius:
			building.take_damage(damage)
	# HQ volcano damage is disabled by design. Uncomment the block below (and
	# the matching block in Meteor) to enable it on NIGHTMARE/GODLY:
	# if WeatherManager._should_damage_hq():
	# 	for building in get_tree().get_nodes_in_group("buildings"):
	# 		if building.name != "PlayerBuilding" and building.name != "EnemyBuilding":
	# 			continue
	# 		if building.global_position.distance_to(global_position) <= radius:
	# 			building.take_damage(damage)


func _is_protected_structure(node: Node) -> bool:
	# HQ buildings and mine entries are protected from volcano fire.
	if node.is_in_group("mine_entries"):
		return true
	# The two headquarters are the only nodes named PlayerBuilding/EnemyBuilding.
	if node.name == "PlayerBuilding" or node.name == "EnemyBuilding":
		return true
	return false


func _draw() -> void:
	var life_left: float = clampf(1.0 - _elapsed / duration, 0.0, 1.0)
	var pulse: float = 0.75 + 0.25 * sin(_flicker * 9.0)
	# Dark scorch base so the patch reads on bright snow and terrain.
	draw_circle(Vector2.ZERO, radius, Color(0.08, 0.04, 0.02, 0.45 * life_left))
	# Outer glow, mid flame, hot core — alpha pulses and fades with lifetime.
	draw_circle(Vector2.ZERO, radius, Color(0.9, 0.3, 0.05, 0.28 * pulse * life_left))
	draw_circle(Vector2.ZERO, radius * 0.7, Color(1.0, 0.5, 0.1, 0.38 * pulse * life_left))
	draw_circle(Vector2.ZERO, radius * 0.35, Color(1.0, 0.8, 0.35, 0.45 * pulse * life_left))
	# Flickering flame licks rising off the patch.
	for i in 5:
		var angle: float = i * TAU / 5.0 + 0.4
		var base: Vector2 = Vector2.RIGHT.rotated(angle) * radius * 0.45
		var lick: float = (0.5 + 0.5 * sin(_flicker * 7.0 + i * 2.1)) * life_left
		var tip: Vector2 = base + Vector2(0.0, -radius * (0.25 + 0.35 * lick))
		draw_line(base, tip, Color(1.0, 0.55, 0.12, 0.55 * pulse * life_left), 3.5, true)
		draw_line(base, tip, Color(1.0, 0.85, 0.4, 0.4 * pulse * life_left), 1.5, true)
	# Pulsing danger ring at the exact damage radius — this is the readout
	# players use to see where the fire hurts.
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1.0, 0.3, 0.05, 0.7 * pulse * life_left), 2.5)
	# Flickering embers drifting inside the radius.
	for i in 6:
		var ember_angle: float = _flicker * (1.5 + i * 0.3) + i * TAU / 6.0
		var ember_pos: Vector2 = Vector2.RIGHT.rotated(ember_angle) * radius * (0.25 + 0.1 * i)
		draw_circle(ember_pos, 2.5, Color(1.0, 0.65, 0.2, 0.5 * pulse * life_left))
