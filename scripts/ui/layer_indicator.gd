class_name LayerIndicator
extends Control

const _LAYER_LABELS: Array[String] = ["L1", "L2", "L3", "L4", "L5", "L6", "L7"]

var _level: int = 1


func _ready() -> void:
	custom_minimum_size = Vector2(220, 44)
	_update_level()
	EconomyManager.miner_level_changed.connect(_on_miner_level_changed)
	queue_redraw()


func _on_miner_level_changed(team: GameManager.Team) -> void:
	if team != GameManager.Team.PLAYER:
		return
	_update_level()
	queue_redraw()


func _update_level() -> void:
	_level = EconomyManager.get_miner_level(GameManager.Team.PLAYER)


func _draw() -> void:
	var start: Vector2 = Vector2.ZERO
	var box_size: float = 20.0
	var gap: float = 8.0
	var font: Font = get_theme_font("font", "Label")
	var font_size: int = 10

	for i in range(_LAYER_LABELS.size()):
		var accessible: bool = _is_accessible(i + 1)
		var rect: Rect2 = Rect2(start.x + i * (box_size + gap), start.y, box_size, box_size)
		var border_color: Color = Color("#3b82f6") if accessible else Color("#475569")
		draw_rect(rect, Color("#0f172a"), true)
		draw_rect(rect, border_color, false, 2.0)

		if accessible:
			draw_rect(rect.grow(-5), Color("#3b82f6"), true)

		var text_pos: Vector2 = rect.position + Vector2(box_size / 2.0, box_size + 14)
		draw_string(font, text_pos, _LAYER_LABELS[i], HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color("#94a3b8"))


func _is_accessible(layer: int) -> bool:
	if _level >= 3:
		return true
	if _level >= 2:
		return layer <= 4
	return layer <= 2
