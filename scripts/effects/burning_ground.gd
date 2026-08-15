class_name BurningGround
extends Node2D

## Crystal Forge (Revamp Phase 6): wizard fireballs scorch the impact area,
## leaving a patch of burning ground that ticks damage onto enemy units for
## BURNING_GROUND_DURATION seconds. Purely code-drawn (flickering fire
## circle); frees itself when the duration elapses.

const TICK_INTERVAL: float = 0.5

var team: GameManager.Team = GameManager.Team.PLAYER
var radius: float = 40.0
var dps: float = Constants.BURNING_GROUND_DPS
var duration: float = Constants.BURNING_GROUND_DURATION

var _elapsed: float = 0.0
var _tick_timer: float = 0.0
var _flicker: float = 0.0


func _ready() -> void:
	_flicker = randf() * TAU  # desync overlapping patches
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
		if unit.team == team or unit._state == Unit.State.DEAD:
			continue
		if unit.get_combat_position().distance_to(global_position) <= radius:
			# Environmental: ground fire is attrition, not an attacker — no
			# popups or combat reflexes (same convention as storm exposure).
			unit.take_damage(damage, null, true)


func _draw() -> void:
	var life_left: float = clampf(1.0 - _elapsed / duration, 0.0, 1.0)
	var pulse: float = 0.75 + 0.25 * sin(_flicker * 9.0)
	# Outer glow, mid flame, hot core — alpha pulses and fades with lifetime.
	draw_circle(Vector2.ZERO, radius, Color(0.9, 0.3, 0.05, 0.10 * pulse * life_left))
	draw_circle(Vector2.ZERO, radius * 0.7, Color(1.0, 0.5, 0.1, 0.16 * pulse * life_left))
	draw_circle(Vector2.ZERO, radius * 0.35, Color(1.0, 0.8, 0.35, 0.22 * pulse * life_left))
	# Flickering embers drifting inside the radius.
	for i in 6:
		var angle: float = _flicker * (1.5 + i * 0.3) + i * TAU / 6.0
		var ember_pos: Vector2 = Vector2.RIGHT.rotated(angle) * radius * (0.25 + 0.1 * i)
		draw_circle(ember_pos, 2.5, Color(1.0, 0.65, 0.2, 0.5 * pulse * life_left))
