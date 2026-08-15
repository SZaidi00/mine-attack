class_name Trap
extends Node2D

## Guerrilla Tactics (Revamp Phase 6): a hidden spike trap placed via the
## build menu. Arms immediately; the first enemy unit stepping within half a
## cell takes TRAP_DAMAGE and the trap is consumed. Code-drawn; enemy traps
## stay invisible unless the player team can currently see the cell (Fog of
## War).

var team: GameManager.Team = GameManager.Team.PLAYER
# Coin spent on this trap (consistency with tower/wall).
var total_cost: int = 0


func _ready() -> void:
	add_to_group("traps")
	queue_redraw()


func _process(_delta: float) -> void:
	# Fog of War: enemy traps stay hidden in unexplored/unseen cells.
	var grid: Node = get_node_or_null("/root/Main/World/GridWorld")
	if grid != null:
		visible = team == GameManager.Team.PLAYER \
			or grid.is_visible_to(GameManager.Team.PLAYER, global_position)
	if not GameManager.game_active:
		return
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == team or unit._state == Unit.State.DEAD:
			continue
		if unit.global_position.distance_to(global_position) <= GridWorld.CELL_SIZE * 0.5:
			unit.take_damage(roundi(Constants.TRAP_DAMAGE))
			queue_free()
			return


func _draw() -> void:
	# Base plate with spikes pointing outward.
	draw_circle(Vector2.ZERO, 10.0, Color(0.25, 0.22, 0.2, 0.9))
	draw_arc(Vector2.ZERO, 10.0, 0, TAU, 12, Color(0.55, 0.5, 0.45), 1.5)
	for i in 5:
		var dir: Vector2 = Vector2.RIGHT.rotated(i * TAU / 5.0)
		draw_line(dir * 4.0, dir * 9.0, Color(0.85, 0.85, 0.9), 2.0)
	# Team marker dot at the center.
	var team_color: Color = GameManager.COLOR_PLAYER if team == GameManager.Team.PLAYER else GameManager.COLOR_ENEMY
	draw_circle(Vector2.ZERO, 2.5, team_color)
