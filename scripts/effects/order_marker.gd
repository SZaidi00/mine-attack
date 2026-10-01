class_name OrderMarker
extends Node2D

## Brief expanding ring flashed at the world destination of a player order
## (move: blue, attack: red, mining: gold). Fades out over its lifetime.

const LIFETIME: float = 0.5
const RADIUS_START: float = 6.0
const RADIUS_END: float = 24.0

var _timer: float = LIFETIME
var _color: Color = Color.WHITE


func setup(color: Color) -> void:
	_color = color


func _process(delta: float) -> void:
	_timer -= delta
	queue_redraw()
	if _timer <= 0.0:
		queue_free()


func _draw() -> void:
	var t: float = 1.0 - clampf(_timer / LIFETIME, 0.0, 1.0)
	var radius: float = lerpf(RADIUS_START, RADIUS_END, t)
	var alpha: float = 1.0 - t
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(_color, alpha), 2.0)
