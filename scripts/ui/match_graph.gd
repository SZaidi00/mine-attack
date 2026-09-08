extends Control
class_name MatchGraph

## Post-match line charts for the game-over panel: coin and population over
## time for both teams, drawn from the MatchStats timeline (5s samples plus
## the t=0 baseline and the match-end point). Pure _draw() rendering — no
## child nodes — and mouse-transparent so it never eats panel clicks.

const UIThemeTokens = preload("res://scripts/ui/ui_theme_tokens.gd")

const _PAD_LEFT: float = 40.0
const _PAD_RIGHT: float = 10.0
const _PAD_TOP: float = 20.0
const _PAD_BOTTOM: float = 8.0
const _FONT_SIZE: int = 12

var timeline: Array = []


func _init(p_timeline: Array = []) -> void:
	timeline = p_timeline
	custom_minimum_size = Vector2(560, 300)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if timeline.size() < 2:
		return
	var gap: float = 8.0
	var chart_h: float = (size.y - gap) / 2.0
	_draw_chart(Rect2(Vector2.ZERO, Vector2(size.x, chart_h)), "player_coin", "enemy_coin", "COIN")
	_draw_chart(Rect2(Vector2(0, chart_h + gap), Vector2(size.x, chart_h)), "player_pop", "enemy_pop", "POPULATION")


func _draw_chart(rect: Rect2, player_key: String, enemy_key: String, title: String) -> void:
	var font: Font = ThemeDB.fallback_font
	draw_rect(rect, UIThemeTokens.COLOR_RECESSED_BG, true)
	draw_rect(rect, UIThemeTokens.COLOR_RECESSED_BORDER, false, 1.0)

	var t_max: float = maxf(1.0, float(timeline[-1].get("t", 1)))
	var v_max: float = 1.0
	for sample: Dictionary in timeline:
		v_max = maxf(v_max, float(sample.get(player_key, 0)))
		v_max = maxf(v_max, float(sample.get(enemy_key, 0)))

	var plot := Rect2(
		rect.position + Vector2(_PAD_LEFT, _PAD_TOP),
		rect.size - Vector2(_PAD_LEFT + _PAD_RIGHT, _PAD_TOP + _PAD_BOTTOM)
	)

	# Title, legend, and the value axis' max label.
	draw_string(font, rect.position + Vector2(6, 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, _FONT_SIZE, UIThemeTokens.COLOR_TEXT_DIM)
	var legend_y: float = rect.position.y + 14
	var you_w: float = font.get_string_size("You", HORIZONTAL_ALIGNMENT_LEFT, -1, _FONT_SIZE).x
	var enemy_w: float = font.get_string_size("Enemy", HORIZONTAL_ALIGNMENT_LEFT, -1, _FONT_SIZE).x
	draw_string(font, Vector2(rect.end.x - _PAD_RIGHT - enemy_w, legend_y), "Enemy", HORIZONTAL_ALIGNMENT_LEFT, -1, _FONT_SIZE, UIThemeTokens.COLOR_ENEMY)
	draw_string(font, Vector2(rect.end.x - _PAD_RIGHT - enemy_w - you_w - 10, legend_y), "You", HORIZONTAL_ALIGNMENT_LEFT, -1, _FONT_SIZE, UIThemeTokens.COLOR_PLAYER)
	draw_string(font, Vector2(rect.position.x + 4, plot.position.y + 4), _format_value(v_max), HORIZONTAL_ALIGNMENT_LEFT, _PAD_LEFT - 6, _FONT_SIZE - 1, UIThemeTokens.COLOR_TEXT_DIM)

	# Baseline (y=0) grid line.
	var baseline_y: float = plot.end.y
	draw_line(Vector2(plot.position.x, baseline_y), Vector2(plot.end.x, baseline_y), UIThemeTokens.COLOR_PANEL_BORDER, 1.0)

	_draw_series(plot, player_key, t_max, v_max, UIThemeTokens.COLOR_PLAYER)
	_draw_series(plot, enemy_key, t_max, v_max, UIThemeTokens.COLOR_ENEMY)


func _draw_series(plot: Rect2, key: String, t_max: float, v_max: float, color: Color) -> void:
	var points := PackedVector2Array()
	for sample: Dictionary in timeline:
		var x: float = plot.position.x + plot.size.x * float(sample.get("t", 0)) / t_max
		var y: float = plot.end.y - plot.size.y * float(sample.get(key, 0)) / v_max
		points.append(Vector2(x, y))
	if points.size() >= 2:
		draw_polyline(points, color, 2.0, true)


## Compact axis label: 1234 -> "1.2k".
func _format_value(v: float) -> String:
	if v >= 1000.0:
		return "%.1fk" % (v / 1000.0)
	return str(int(v))
