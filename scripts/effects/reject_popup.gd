class_name RejectPopup
extends Node2D

## Brief red-X indicator flashed at the target of a rejected command
## (Phase 1: rejections must never be silent or invisible).

const LIFETIME: float = 0.7
const RISE_SPEED: float = 24.0

var _timer: float = LIFETIME


func _process(delta: float) -> void:
	position.y -= RISE_SPEED * delta
	_timer -= delta
	modulate.a = clampf(_timer / 0.25, 0.0, 1.0)
	if _timer <= 0.0:
		queue_free()


func _draw() -> void:
	var s: float = 8.0
	var w: float = 3.0
	draw_line(Vector2(-s, -s), Vector2(s, s), Color.RED, w)
	draw_line(Vector2(-s, s), Vector2(s, -s), Color.RED, w)
