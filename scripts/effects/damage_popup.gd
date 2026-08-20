class_name DamagePopup
extends Label

const RISE_SPEED: float = 40.0
const LIFETIME: float = 1.0

var _timer: float = LIFETIME


func _ready() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func setup(amount: int, is_healing: bool = false) -> void:
	text = ("+" if is_healing else "-") + str(amount)
	modulate = Color.GREEN if is_healing else Color.RED


func setup_immune() -> void:
	text = "IMMUNE"
	modulate = Color(0.75, 0.78, 0.85, 1.0)


## Environmental fire damage (burning ground): orange instead of combat red.
func setup_fire(amount: int) -> void:
	text = "-" + str(amount)
	modulate = Color(1.0, 0.55, 0.15, 1.0)


func _process(delta: float) -> void:
	# Fog of War: a popup at a position the player cannot see must not leak
	# enemy combat (or healing) activity.
	var grid: Node = get_node_or_null("/root/Main/World/GridWorld")
	if grid != null:
		visible = grid.is_visible_to(GameManager.Team.PLAYER, global_position)
	position.y -= RISE_SPEED * delta
	_timer -= delta
	modulate.a = clampf(_timer / 0.3, 0.0, 1.0)
	if _timer <= 0.0:
		queue_free()
