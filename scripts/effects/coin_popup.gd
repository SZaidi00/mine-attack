class_name CoinPopup
extends Label

const RISE_SPEED: float = 30.0
const LIFETIME: float = 1.2

var _timer: float = LIFETIME


func _ready() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	modulate = Color.GOLD


func setup(amount: int) -> void:
	text = "+" + str(amount)


func _process(delta: float) -> void:
	position.y -= RISE_SPEED * delta
	_timer -= delta
	modulate.a = clampf(_timer / 0.3, 0.0, 1.0)
	if _timer <= 0.0:
		queue_free()
