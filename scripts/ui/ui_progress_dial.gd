class_name UIProgressDial
extends Control

const UIThemeTokens = preload("res://scripts/ui/ui_theme_tokens.gd")

var value: float = 0.0:
	set(next):
		value = clampf(next, 0.0, 1.0)
		queue_redraw()
var icon: Texture2D = null:
	set(next):
		icon = next
		queue_redraw()
var progress_color: Color = UIThemeTokens.COLOR_TEXT_GOLD:
	set(next):
		progress_color = next
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(48, 48)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := size * 0.5
	var radius := maxf(1.0, minf(size.x, size.y) * 0.5 - 3.0)
	draw_circle(center, radius + 1.0, Color(0.025, 0.045, 0.075, 0.92))
	draw_arc(center, radius, 0.0, TAU, 64, Color(UIThemeTokens.COLOR_BRASS, 0.30), 2.0, true)
	draw_arc(center, radius - 4.0, 0.0, TAU, 64, Color(UIThemeTokens.COLOR_TEXT_DIM, 0.16), 1.0, true)
	for i in range(12):
		var angle := -PI * 0.5 + float(i) * TAU / 12.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(center + direction * (radius - 1.0), center + direction * (radius - 4.0), Color(UIThemeTokens.COLOR_BRASS, 0.48), 1.0, true)
	if value > 0.0:
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * value, 64, progress_color, 2.5, true)
	if icon != null:
		var icon_size := Vector2.ONE * radius * 1.08
		draw_texture_rect(icon, Rect2(center - icon_size * 0.5, icon_size), false)
