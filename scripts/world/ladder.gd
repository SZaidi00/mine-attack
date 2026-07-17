extends Node2D

const _RAIL_COLOR: Color = Color(0.5, 0.35, 0.2)
const _RUNG_COLOR: Color = Color(0.65, 0.5, 0.3)

@export var top_position: Vector2 = Vector2.ZERO
@export var bottom_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("ladders")
	queue_redraw()


func get_top_position() -> Vector2:
	return top_position


func get_bottom_position() -> Vector2:
	return bottom_position


func _draw() -> void:
	var local_top: Vector2 = to_local(top_position)
	var local_bottom: Vector2 = to_local(bottom_position)
	var height: float = local_top.distance_to(local_bottom)
	if height <= 0.0:
		return

	var rail_offset: float = 5.0
	var rail_width: float = 3.0
	var rung_count: int = maxi(4, int(height / 14.0))

	# Side rails.
	draw_line(local_top + Vector2(-rail_offset, 0.0), local_bottom + Vector2(-rail_offset, 0.0), _RAIL_COLOR, rail_width)
	draw_line(local_top + Vector2(rail_offset, 0.0), local_bottom + Vector2(rail_offset, 0.0), _RAIL_COLOR, rail_width)

	# Rungs.
	for i in range(rung_count):
		var t: float = float(i) / float(rung_count - 1)
		var pos: Vector2 = local_top.lerp(local_bottom, t)
		draw_line(pos + Vector2(-rail_offset, 0.0), pos + Vector2(rail_offset, 0.0), _RUNG_COLOR, 2.0)
