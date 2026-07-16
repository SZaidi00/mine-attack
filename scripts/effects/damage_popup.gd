class_name DamagePopup
extends Label

const RISE_SPEED: float = 40.0
const LIFETIME: float = 1.0

var _timer: float = LIFETIME


func _ready() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func setup(amount: int, is_healing: bool = false) -> void:
	text = "-" + str(amount)
	modulate = Color.GREEN if is_healing else Color.RED


func _process(delta: float) -> void:
	position.y -= RISE_SPEED * delta
	_timer -= delta
	modulate.a = clampf(_timer / 0.3, 0.0, 1.0)
	if _timer <= 0.0:
		queue_free()
